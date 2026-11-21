#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

project="${PROJECT:-ThumbnailMaker.xcodeproj}"
scheme="${SCHEME:-ThumbnailMaker}"
derived_data="${DERIVED_DATA:-.build-ci}"
result_dir="${RESULT_DIR:-$derived_data/results}"
run_catalyst="${RUN_CATALYST:-1}"
run_ui_smoke="${RUN_UI_SMOKE:-0}"
run_ui_extended="${RUN_UI_EXTENDED:-0}"
simulator_selector="${CI_SIMULATOR_SELECTOR:-iphone}"
reset_simulator_before_tests="${CI_RESET_SIMULATOR_BEFORE_TESTS:-${CI:+1}}"
reset_simulator_before_tests="${reset_simulator_before_tests:-0}"

mkdir -p "$result_dir"
rm -rf \
  "$result_dir/unit.xcresult" \
  "$result_dir/ui-smoke.xcresult" \
  "$result_dir/ui-extended.xcresult"

run_xcodebuild() {
  if command -v xcbeautify >/dev/null 2>&1; then
    local xcode_status
    set +e
    xcodebuild "$@" | xcbeautify
    xcode_status=${PIPESTATUS[0]}
    set -e
    return "$xcode_status"
  else
    xcodebuild "$@"
  fi
}

prepare_simulator_for_unit_tests() {
  local settle_seconds="${SIMULATOR_SETTLE_SECONDS:-8}"

  if [[ "$reset_simulator_before_tests" == "1" ]]; then
    echo "Resetting simulator $udid before unit tests to avoid stale diagnostic state."
    xcrun simctl terminate "$udid" com.williamjiamin.ThumbnailMaker >/dev/null 2>&1 || true
    xcrun simctl terminate "$udid" com.williamjiamin.ThumbnailMakerUITests.xctrunner >/dev/null 2>&1 || true
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    if ! xcrun simctl erase "$udid"; then
      echo "simctl erase failed for $udid; shutting down all simulators and retrying once."
      xcrun simctl shutdown all >/dev/null 2>&1 || true
      xcrun simctl erase "$udid"
    fi
  fi

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  if ! xcrun simctl bootstatus "$udid" -b; then
    echo "Simulator bootstatus did not report ready before unit tests; continuing to xcodebuild for diagnostic output."
  fi
  sleep "$settle_seconds"
}

prepare_simulator_for_ui_tests() {
  local settle_seconds="${SIMULATOR_SETTLE_SECONDS:-8}"

  xcrun simctl terminate "$udid" com.williamjiamin.ThumbnailMaker >/dev/null 2>&1 || true
  xcrun simctl terminate "$udid" com.williamjiamin.ThumbnailMakerUITests.xctrunner >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  if ! xcrun simctl bootstatus "$udid" -b; then
    echo "Simulator bootstatus did not report ready before UI tests; continuing to xcodebuild for diagnostic output."
  fi
  sleep "$settle_seconds"
}

is_transient_ui_launch_failure() {
  local log_path="$1"

  grep -Eq \
    'Simulator device failed to launch .*ThumbnailMakerUITests\.xctrunner|Failed to install or launch the test runner|Application failed preflight checks|The request to open .*ThumbnailMakerUITests\.xctrunner.*failed|reason: Busy \("Application failed preflight checks"\)' \
    "$log_path"
}

run_ui_xcodebuild() {
  local label="$1"
  shift

  local retries="${UI_TEST_RETRIES:-1}"
  local log_path="$result_dir/$label.log"
  local result_bundle=""
  local args=("$@")
  local attempts
  local attempt
  local i
  local status

  if ! [[ "$retries" =~ ^[0-9]+$ ]]; then
    echo "UI_TEST_RETRIES must be a non-negative integer, got '$retries'" >&2
    return 2
  fi
  attempts=$((retries + 1))

  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "-resultBundlePath" && $((i + 1)) -lt ${#args[@]} ]]; then
      result_bundle="${args[$((i + 1))]}"
      break
    fi
  done

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    echo "Running $label UI tests, attempt $attempt/$attempts"
    rm -f "$log_path"
    if [[ -n "$result_bundle" ]]; then
      rm -rf "$result_bundle"
    fi

    prepare_simulator_for_ui_tests

    set +e
    if command -v xcbeautify >/dev/null 2>&1; then
      xcodebuild "${args[@]}" 2>&1 | tee "$log_path" | xcbeautify
      status=${PIPESTATUS[0]}
    else
      xcodebuild "${args[@]}" 2>&1 | tee "$log_path"
      status=${PIPESTATUS[0]}
    fi
    set -e

    if [[ "$status" -eq 0 ]]; then
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]] && is_transient_ui_launch_failure "$log_path"; then
      echo "$label failed due to transient simulator launch/preflight state; retrying."
      continue
    fi

    return "$status"
  done
}

echo "CI host: $(hostname)"
echo "CI gate capabilities: UNIT=1 UI_SMOKE=$run_ui_smoke UI_EXTENDED=$run_ui_extended CATALYST=$run_catalyst"

destination="$(scripts/pick-simulator.sh "$simulator_selector")"
udid="${destination##*id=}"

prepare_simulator_for_unit_tests

run_xcodebuild build-for-testing \
  -project "$project" \
  -scheme "$scheme" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO

run_xcodebuild test-without-building \
  -project "$project" \
  -scheme "$scheme" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:ThumbnailMakerTests \
  -resultBundlePath "$result_dir/unit.xcresult" \
  CODE_SIGNING_ALLOWED=NO

if [[ "$run_ui_smoke" == "1" ]]; then
  run_ui_xcodebuild ui-smoke test-without-building \
    -project "$project" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testLaunchAccessibilityAudit \
    -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumEditorAccessibilityAudit \
    -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testUndoRedoKeyboardShortcutsRevertOverlayText \
    -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testTitleIdeaStripShowsAndAppliesVariant \
    -resultBundlePath "$result_dir/ui-smoke.xcresult" \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "$run_ui_extended" == "1" ]]; then
  extended_ui_tests=(
    ThumbnailMakerUITests/ThumbnailMakerUITests/testLaunchAccessibilityAudit
    ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsAccessibilityAudit
    ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumEditorAccessibilityAudit
    ThumbnailMakerUITests/ThumbnailMakerUITests/testLayerControlsRemainAccessibleAtLargeDynamicType
    ThumbnailMakerUITests/ThumbnailMakerUITests/testDirectManipulationHandlesAppearForTextOverlay
    ThumbnailMakerUITests/ThumbnailMakerUITests/testLayerVisibilityAndLockControlsAffectTextChrome
    ThumbnailMakerUITests/ThumbnailMakerUITests/testImageLayerSelectionShowsCanvasChromeAndLayerActions
    ThumbnailMakerUITests/ThumbnailMakerUITests/testShapeLayerSelectionShowsCanvasChromeAndLayerActions
    ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumCanvasShowsSingleOverlayChromeByDefault
    ThumbnailMakerUITests/ThumbnailMakerUITests/testUndoRedoKeyboardShortcutsRevertOverlayText
    ThumbnailMakerUITests/ThumbnailMakerUITests/testTitleIdeaStripShowsAndAppliesVariant
  )

  extended_only_testing_args=()
  for test_name in "${extended_ui_tests[@]}"; do
    extended_only_testing_args+=("-only-testing:$test_name")
  done

  run_ui_xcodebuild ui-extended test-without-building \
    -project "$project" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    "${extended_only_testing_args[@]}" \
    -resultBundlePath "$result_dir/ui-extended.xcresult" \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "$run_catalyst" == "1" ]]; then
  run_xcodebuild build \
    -project "$project" \
    -scheme "$scheme" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -derivedDataPath "$derived_data-catalyst" \
    CODE_SIGNING_ALLOWED=NO
fi

echo "CI gate passed. Result bundles: $result_dir"
echo "CI gate summary: UNIT=1 UI_SMOKE=$run_ui_smoke UI_EXTENDED=$run_ui_extended CATALYST=$run_catalyst"

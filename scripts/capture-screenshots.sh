#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

project="${PROJECT:-ThumbnailMaker.xcodeproj}"
scheme="${SCHEME:-ThumbnailMaker}"
derived_data="${DERIVED_DATA:-.build-screenshots}"
run_id="${SCREENSHOT_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
output_root="${OUTPUT_DIR:-artifacts/app-store-screenshots/$run_id}"
result_dir="${RESULT_DIR:-$output_root/results}"
run_iphone="${RUN_IPHONE_SCREENSHOTS:-1}"
run_ipad="${RUN_IPAD_SCREENSHOTS:-1}"
run_mac="${RUN_MAC_SCREENSHOTS:-0}"
iphone_selector="${IPHONE_SCREENSHOT_SELECTOR:-iphone-max}"
ipad_selector="${IPAD_SCREENSHOT_SELECTOR:-ipad-13}"
mac_derived_data="${MAC_DERIVED_DATA:-${derived_data}-catalyst}"
mac_app_name="${MAC_APP_NAME:-ThumbnailMaker}"
mac_window_x="${MAC_SCREENSHOT_X:-0}"
mac_window_y="${MAC_SCREENSHOT_Y:-0}"
mac_window_width="${MAC_SCREENSHOT_WIDTH:-1280}"
mac_window_height="${MAC_SCREENSHOT_HEIGHT:-800}"
mac_window_timeout="${MAC_SCREENSHOT_TIMEOUT:-30}"
screenshot_archs="${SCREENSHOT_ARCHS:-}"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

output_root="$(absolute_path "$output_root")"
result_dir="$(absolute_path "$result_dir")"

mkdir -p "$output_root" "$result_dir"

run_xcodebuild() {
  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "$@" | xcbeautify
  else
    xcodebuild "$@"
  fi
}

cleanup_mac_app() {
  osascript -e "tell application \"$mac_app_name\" to quit" >/dev/null 2>&1 || true
  pkill -x "$mac_app_name" >/dev/null 2>&1 || true
}

remove_dir_if_safe() {
  local directory="$1"
  local label="${2:-directory}"

  if [[ -z "$directory" || "$directory" == "/" ]]; then
    echo "Refusing to remove unsafe $label path: ${directory:-<empty>}" >&2
    return 1
  fi

  case "$directory" in
    /*) ;;
    *) directory="$(absolute_path "$directory")" ;;
  esac

  if [[ -d "$directory" ]]; then
    echo "Removing $label: $directory"
    rm -rf "$directory"
  fi
}

reclaim_ios_screenshot_artifacts() {
  local normalized_result_dir="$result_dir"
  local normalized_output_root="$output_root"

  case "$normalized_result_dir" in
    /*) ;;
    *) normalized_result_dir="$(absolute_path "$normalized_result_dir")" ;;
  esac

  remove_dir_if_safe "$derived_data" "iOS screenshot derived data"

  if [[ "$normalized_result_dir" == "$normalized_output_root" ]]; then
    echo "Skipping result cleanup because RESULT_DIR equals OUTPUT_DIR: $normalized_result_dir"
  elif [[ "$normalized_output_root/" == "$normalized_result_dir"/* ]]; then
    echo "Skipping result cleanup because RESULT_DIR contains OUTPUT_DIR: $normalized_result_dir"
  else
    remove_dir_if_safe "$normalized_result_dir" "screenshot result bundles"
  fi
}

boot_destination() {
  local destination="$1"
  local udid="${destination##*id=}"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
}

validate_png_file() {
  local png_path="$1"
  local device_slug="$2"

  python3 - "$png_path" "$device_slug" <<'PY'
import os
import struct
import sys
import zlib

png_path, device_slug = sys.argv[1:3]

allowed_dimensions = {
    "mac": {
        (1280, 800),
        (1440, 900),
        (2560, 1600),
        (2880, 1800),
    },
}

def png_chunks(path):
    with open(path, "rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"{path} is not a PNG screenshot")
        while True:
            length_bytes = handle.read(4)
            if not length_bytes:
                break
            length = struct.unpack(">I", length_bytes)[0]
            kind = handle.read(4)
            data = handle.read(length)
            handle.read(4)
            yield kind, data
            if kind == b"IEND":
                break

def png_size_and_pixels(path):
    width = height = None
    bit_depth = color_type = interlace = None
    idat = bytearray()

    for kind, data in png_chunks(path):
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            idat.extend(data)

    if width is None or height is None:
        raise SystemExit(f"{path} is missing a PNG IHDR chunk")

    return width, height, bit_depth, color_type, interlace, bytes(idat)

def paeth_predictor(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

def sampled_color_count(width, height, bit_depth, color_type, interlace, idat):
    if bit_depth != 8 or color_type not in {0, 2, 4, 6} or interlace != 0:
        return None

    channels_by_color_type = {0: 1, 2: 3, 4: 2, 6: 4}
    bytes_per_pixel = channels_by_color_type[color_type]
    stride = width * bytes_per_pixel
    raw = zlib.decompress(idat)
    expected_length = height * (stride + 1)
    if len(raw) < expected_length:
        raise SystemExit(f"{png_path} has truncated image data")

    samples = set()
    previous = bytearray(stride)
    offset = 0
    x_step = max(1, width // 64)
    y_step = max(1, height // 64)

    for y in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride

        for i in range(stride):
            left = row[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
            up = previous[i]
            upper_left = previous[i - bytes_per_pixel] if i >= bytes_per_pixel else 0

            if filter_type == 1:
                row[i] = (row[i] + left) & 0xFF
            elif filter_type == 2:
                row[i] = (row[i] + up) & 0xFF
            elif filter_type == 3:
                row[i] = (row[i] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                row[i] = (row[i] + paeth_predictor(left, up, upper_left)) & 0xFF
            elif filter_type != 0:
                raise SystemExit(f"{png_path} uses unsupported PNG filter {filter_type}")

        if y % y_step == 0:
            for x in range(0, width, x_step):
                index = x * bytes_per_pixel
                samples.add(bytes(row[index:index + bytes_per_pixel]))

        previous = row

    return len(samples)

width, height, bit_depth, color_type, interlace, idat = png_size_and_pixels(png_path)
expected = allowed_dimensions.get(device_slug)
if expected and (width, height) not in expected:
    expected_text = ", ".join(f"{w}x{h}" for w, h in sorted(expected))
    raise SystemExit(
        f"{os.path.basename(png_path)} is {width}x{height}; expected one of {expected_text}"
    )

if device_slug == "mac":
    file_size = os.path.getsize(png_path)
    if file_size < 80 * 1024:
        raise SystemExit(
            f"{os.path.basename(png_path)} is only {file_size} bytes; "
            "this often means macOS Screen Recording permission produced a blank capture"
        )

    color_count = sampled_color_count(width, height, bit_depth, color_type, interlace, idat)
    if color_count is not None and color_count < 8:
        raise SystemExit(
            f"{os.path.basename(png_path)} appears blank or single-color ({color_count} sampled colors)"
        )

print(f"{device_slug}: {os.path.basename(png_path)} {width}x{height}")
PY
}

export_attachments() {
  local result_bundle="$1"
  local device_slug="$2"
  local raw_dir="$output_root/$device_slug/raw"
  local final_dir="$output_root/$device_slug"

  rm -rf "$raw_dir"
  mkdir -p "$raw_dir" "$final_dir"

  if xcrun xcresulttool export attachments --help >/dev/null 2>&1; then
    xcrun xcresulttool export attachments \
      --path "$result_bundle" \
      --output-path "$raw_dir"
  else
    echo "xcresulttool export attachments is unavailable; cannot extract screenshot attachments." >&2
    exit 1
  fi

  python3 - "$raw_dir" "$final_dir" "$device_slug" <<'PY'
import json
import os
import re
import shutil
import struct
import subprocess
import sys

raw_dir, final_dir, device_slug = sys.argv[1:4]
manifest_path = os.path.join(raw_dir, "manifest.json")

allowed_dimensions = {
    "iphone-max": {
        (1260, 2736), (2736, 1260),
        (1290, 2796), (2796, 1290),
        (1320, 2868), (2868, 1320),
    },
    "ipad-13": {
        (2064, 2752), (2752, 2064),
        (2048, 2732), (2732, 2048),
    },
}

# Keep this in sync with AppStoreScreenshotTests.attachScreenshot(named:).
required_names = {
    "iphone-max": {
        "01-iphone-editor-wysiwyg.png",
        "02-iphone-template-gallery.png",
        "03-iphone-template-applied.png",
        "04-iphone-ai-title-ideas.png",
        "05-iphone-export-readiness.png",
    },
    "ipad-13": {
        "01-ipad-simple-regular-editor.png",
        "02-ipad-premium-regular-editor.png",
        "03-ipad-premium-landscape-editor.png",
    },
}

def clean_name(name):
    base, ext = os.path.splitext(name)
    base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", base)
    base = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip("-")
    return f"{base or 'screenshot'}{ext.lower() or '.png'}"

def png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG screenshot")
    return struct.unpack(">II", header[16:24])

def rotate_to_landscape_if_needed(path):
    width, height = png_size(path)
    if "landscape" not in os.path.basename(path).lower() or width > height:
        return
    rotated_path = f"{path}.rotated.png"
    subprocess.run(
        ["sips", "-r", "90", path, "--out", rotated_path],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    os.replace(rotated_path, path)

with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

copied = []
for test_entry in manifest:
    for attachment in test_entry.get("attachments", []):
        exported = attachment.get("exportedFileName")
        suggested = attachment.get("suggestedHumanReadableName") or exported
        if not exported:
            continue
        src = os.path.join(raw_dir, exported)
        if not os.path.isfile(src):
            continue
        dest_name = clean_name(suggested)
        dest = os.path.join(final_dir, dest_name)
        index = 2
        while os.path.exists(dest):
            stem, ext = os.path.splitext(dest_name)
            dest = os.path.join(final_dir, f"{stem}-{index}{ext}")
            index += 1
        shutil.copy2(src, dest)
        copied.append(dest)

if not copied:
    raise SystemExit(f"No screenshot attachments were exported for {device_slug}")

required = required_names.get(device_slug)
if required:
    present = {os.path.basename(path) for path in copied}
    missing = sorted(required - present)
    if missing:
        raise SystemExit(
            f"{device_slug} is missing required App Store screenshots:\n"
            + "\n".join(missing)
        )

expected = allowed_dimensions.get(device_slug)
bad_dimensions = []
for path in copied:
    rotate_to_landscape_if_needed(path)
    size = png_size(path)
    if expected and size not in expected:
        bad_dimensions.append((path, size))

if bad_dimensions:
    expected_text = ", ".join(f"{w}x{h}" for w, h in sorted(expected))
    lines = [
        f"{os.path.basename(path)} is {size[0]}x{size[1]}"
        for path, size in bad_dimensions
    ]
    raise SystemExit(
        f"{device_slug} screenshots do not match App Store dimensions "
        f"({expected_text}):\n" + "\n".join(lines)
    )

for path in copied:
    size = png_size(path)
    print(f"{device_slug}: {os.path.basename(path)} {size[0]}x{size[1]}")
PY

  remove_dir_if_safe "$raw_dir" "$device_slug raw screenshot exports"
  remove_dir_if_safe "$result_bundle" "$device_slug screenshot result bundle"
}

wait_for_mac_window() {
  local deadline=$((SECONDS + mac_window_timeout))
  local window_state

  while (( SECONDS < deadline )); do
    window_state="$(osascript <<OSA 2>/dev/null | tr -d '[:space:]' || true
tell application "System Events"
  if exists process "$mac_app_name" then
    tell process "$mac_app_name"
      set frontmost to true
      if exists window 1 then
        set position of window 1 to {$mac_window_x, $mac_window_y}
        set size of window 1 to {$mac_window_width, $mac_window_height}
        delay 0.2
        set windowPosition to position of window 1
        set windowSize to size of window 1
        return ((item 1 of windowPosition) as text) & "," & ((item 2 of windowPosition) as text) & "," & ((item 1 of windowSize) as text) & "," & ((item 2 of windowSize) as text)
      end if
    end tell
  end if
end tell
return ""
OSA
)"

    if [[ "$window_state" == *,*,*,* ]]; then
      printf '%s\n' "$window_state"
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for the Mac Catalyst app window." >&2
  return 1
}

capture_mac_screenshot() {
  local mac_output_dir="$output_root/mac"
  local app_path
  local window_state
  local actual_x
  local actual_y
  local actual_width
  local actual_height
  local screenshot_path="$mac_output_dir/01-mac-catalyst-editor.png"
  local full_screenshot_path="$mac_output_dir/full-display.png"

  mkdir -p "$mac_output_dir"

  local mac_build_settings=(
    COMPILER_INDEX_STORE_ENABLE=NO
    ONLY_ACTIVE_ARCH=YES
    DEBUG_INFORMATION_FORMAT=dwarf
  )
  if [[ -n "$screenshot_archs" ]]; then
    mac_build_settings+=("ARCHS=$screenshot_archs")
  fi

  run_xcodebuild build \
    -project "$project" \
    -scheme "$scheme" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -derivedDataPath "$mac_derived_data" \
    "${mac_build_settings[@]}" \
    CODE_SIGNING_ALLOWED=NO

  app_path="$(find "$mac_derived_data/Build/Products" \
    -path "*Debug-maccatalyst*" \
    -type d \
    -name "$mac_app_name.app" \
    -print \
    -quit 2>/dev/null || true)"

  if [[ -z "$app_path" ]]; then
    app_path="$(find "$mac_derived_data/Build/Products" \
      -path "*Debug-maccatalyst*" \
      -type d \
      -name "*.app" \
      ! -name "*UITests-Runner.app" \
      -print \
      -quit 2>/dev/null || true)"
  fi

  if [[ -z "$app_path" || ! -d "$app_path" ]]; then
    echo "Could not find a built Mac Catalyst app under $mac_derived_data." >&2
    exit 1
  fi

  trap cleanup_mac_app EXIT
  cleanup_mac_app

  open -n "$app_path" --args \
    -UITestUnlockPremium \
    -UITestSeedPremiumEditor \
    -DisableDraftPersistence \
    -RenderMacAppStoreScreenshot "$screenshot_path"

  for _ in {1..60}; do
    if [[ -s "$screenshot_path" ]]; then
      validate_png_file "$screenshot_path" mac
      cleanup_mac_app
      return 0
    fi
    sleep 1
  done

  echo "App-side Mac screenshot render did not produce a PNG; falling back to display capture." >&2
  cleanup_mac_app

  open -n "$app_path" --args \
    -UITestUnlockPremium \
    -UITestSeedSelectedImage \
    -UITestSeedPremiumEditor \
    -DisableDraftPersistence

  if window_state="$(wait_for_mac_window)"; then
    IFS=',' read -r actual_x actual_y actual_width actual_height <<< "$window_state"

    if (( actual_width < mac_window_width || actual_height < mac_window_height )); then
      echo "Mac window is ${actual_width}x${actual_height}; expected at least ${mac_window_width}x${mac_window_height}." >&2
      exit 1
    fi
  else
    echo "Mac window automation unavailable; capturing the configured default region." >&2
    /usr/bin/pgrep -fl "$mac_app_name" >&2 || true
    actual_x="$mac_window_x"
    actual_y="$mac_window_y"
    actual_width="$mac_window_width"
    actual_height="$mac_window_height"
    sleep 3
  fi

  if ! screencapture -x -R"${actual_x},${actual_y},${mac_window_width},${mac_window_height}" "$screenshot_path"; then
    echo "Region capture failed; capturing the full display and resizing to ${mac_window_width}x${mac_window_height}." >&2
    if ! screencapture -x "$full_screenshot_path"; then
      echo "Full-display capture failed; macOS Screen Recording or display access may be unavailable." >&2
      exit 1
    fi

    /usr/bin/sips -z "$mac_window_height" "$mac_window_width" "$full_screenshot_path" \
      --out "$screenshot_path" >/dev/null
    rm -f "$full_screenshot_path"
  fi

  validate_png_file "$screenshot_path" mac
  cleanup_mac_app
}

run_screenshot_tests() {
  local selector="$1"
  local device_slug="$2"
  shift 2
  local tests=("$@")

  local destination
  destination="$(scripts/pick-simulator.sh "$selector")"
  boot_destination "$destination"

  local result_bundle="$result_dir/$device_slug.xcresult"
  rm -rf "$result_bundle"

  local only_testing_args=()
  for test_name in "${tests[@]}"; do
    only_testing_args+=("-only-testing:$test_name")
  done

  run_xcodebuild test-without-building \
    -project "$project" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -parallel-testing-enabled NO \
    "${only_testing_args[@]}" \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO

  export_attachments "$result_bundle" "$device_slug"
}

if [[ "$run_iphone" != "1" && "$run_ipad" != "1" && "$run_mac" != "1" ]]; then
  echo "No screenshots selected. Enable at least one RUN_*_SCREENSHOTS flag." >&2
  exit 1
fi

if [[ "$run_iphone" == "1" || "$run_ipad" == "1" ]]; then
  screenshot_build_settings=(
    COMPILER_INDEX_STORE_ENABLE=NO
  )
  if [[ -n "$screenshot_archs" ]]; then
    screenshot_build_settings+=("ARCHS=$screenshot_archs")
  fi

  run_xcodebuild build-for-testing \
    -project "$project" \
    -scheme "$scheme" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived_data" \
    "${screenshot_build_settings[@]}" \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "$run_iphone" == "1" ]]; then
  run_screenshot_tests \
    "$iphone_selector" \
    iphone-max \
    ThumbnailMakerUITests/AppStoreScreenshotTests/testIPhoneEditorAndTemplateScreenshots \
    ThumbnailMakerUITests/AppStoreScreenshotTests/testIPhoneAIAndExportScreenshots
fi

if [[ "$run_ipad" == "1" ]]; then
  run_screenshot_tests \
    "$ipad_selector" \
    ipad-13 \
    ThumbnailMakerUITests/AppStoreScreenshotTests/testIPadRegularLayoutScreenshots
fi

if [[ "$run_mac" == "1" ]]; then
  if [[ "$run_iphone" == "1" || "$run_ipad" == "1" ]]; then
    reclaim_ios_screenshot_artifacts
  fi
  capture_mac_screenshot
fi

echo "App Store screenshot artifacts: $output_root"

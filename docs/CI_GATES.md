# CI Gates

Last updated: 2026-06-29

This file defines which CI runs count as beta-exit evidence. A green check is not enough unless the run covers the required gate scope and the evidence is current for the release branch or commit under review.

## Gate 4: Mac Mini CI

Gate 4 passes only when a current release-branch run on the self-hosted Mac mini proves all of these:

- unit tests pass and `unit.xcresult` is uploaded
- UI smoke tests pass and `ui-smoke.xcresult` is uploaded
- accessibility audits run inside the UI suite
- Mac Catalyst build passes
- the workflow log records the Mac mini hostname
- the run is for the commit or branch snapshot being claimed in `docs/BETA_EXIT_CHECKLIST.md`

## Preferred GitHub Actions Run

After the current workflow and scripts are committed and pushed, dispatch:

```sh
gh workflow run .github/workflows/ios-build.yml \
  --repo williamjiamin/ThumbnailMaker \
  --ref codex/publish-readiness-m1 \
  -f run_ui_smoke=true \
  -f run_ui_extended=true \
  -f capture_screenshots=false \
  -f capture_mac_screenshots=false
```

Then wait for completion and record:

```sh
gh run list --repo williamjiamin/ThumbnailMaker --workflow .github/workflows/ios-build.yml --limit 5
gh run view <run-id> --repo williamjiamin/ThumbnailMaker --log
gh run download <run-id> --repo williamjiamin/ThumbnailMaker --name xcode-results-<run-id>-1 --dir /tmp/thumbnailmaker-mac-mini-ci-<run-id>
```

The `Run CI gate` log must include:

```text
CI host: <mac-mini-hostname>
CI gate capabilities: UNIT=1 UI_SMOKE=1 UI_EXTENDED=1 CATALYST=1
CI gate summary: UNIT=1 UI_SMOKE=1 UI_EXTENDED=1 CATALYST=1
```

## What Does Not Count

- The older remote workflow named `iOS build (self-hosted mini)` does not satisfy Gate 4 because it only builds/builds-for-testing iOS Simulator.
- A push or pull request run with `RUN_UI_SMOKE=0` does not satisfy Gate 4.
- A successful local run on a MacBook does not satisfy Gate 4.
- A run against an older commit does not prove the current dirty working tree.

## Direct Mac Mini Fallback

If GitHub Actions dispatch is unavailable, run this on the Mac mini checkout for the current branch:

```sh
hostname
DERIVED_DATA="$RUNNER_TEMP/thumbnailmaker-gate4-dd" \
RESULT_DIR="$RUNNER_TEMP/thumbnailmaker-gate4-results" \
RUN_CATALYST=1 \
RUN_UI_SMOKE=1 \
RUN_UI_EXTENDED=1 \
scripts/ci-gate.sh
```

Save the terminal log plus the `unit.xcresult`, `ui-smoke.xcresult`, and `ui-extended.xcresult` bundles. Record the exact host, branch, commit, command, result-bundle paths, and Catalyst result in `docs/BETA_EXIT_CHECKLIST.md`.

#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_id="${GATE16_EVIDENCE_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
bundle_root="${GATE16_EVIDENCE_DIR:-artifacts/gate16-evidence/$run_id}"

mkdir -p \
  "$bundle_root/google-cloud" \
  "$bundle_root/app-store-connect/privacy" \
  "$bundle_root/app-store-connect/metadata" \
  "$bundle_root/app-store-connect/screenshots" \
  "$bundle_root/app-store-connect/build" \
  "$bundle_root/repo-checks"

cat > "$bundle_root/README.md" <<EOF
# Gate 16 Evidence Bundle

Created: $(date +%Y-%m-%d)

This folder is for reviewer-safe Gate 16 evidence only. Do not store secrets, full API keys, App Store Connect session URLs, cookies, tokens, or private account screenshots that expose credentials.

## Fill This Packet

1. Copy reviewer-safe Google Cloud screenshots or exports into \`google-cloud/\`.
2. Copy App Store Connect privacy, export compliance, metadata, age rating, screenshot upload, archive validation, or TestFlight evidence into \`app-store-connect/\`.
3. Save repo verification output into \`repo-checks/\`.
4. Fill \`docs/GATE16_EVIDENCE_PACKET.md\` with paths to files in this folder.
5. Run:

\`\`\`sh
scripts/verify-gate16.sh
scripts/verify-gate16-evidence-packet.sh
\`\`\`

## Suggested File Names

- \`google-cloud/old-youtube-key-rotated.png\`
- \`google-cloud/release-youtube-key-restricted.png\`
- \`app-store-connect/privacy/app-privacy-answers.png\`
- \`app-store-connect/metadata/support-url.png\`
- \`app-store-connect/metadata/age-rating.png\`
- \`app-store-connect/screenshots/uploaded-screenshots.png\`
- \`app-store-connect/build/archive-validation.png\`
- \`app-store-connect/build/testflight-upload.png\`
- \`repo-checks/verify-gate16.txt\`
- \`repo-checks/mac-mini-ci-run-28407849435.txt\`

## Packet Path Examples

Use paths like these in \`docs/GATE16_EVIDENCE_PACKET.md\`:

- \`$bundle_root/google-cloud/old-youtube-key-rotated.png\`
- \`$bundle_root/app-store-connect/privacy/app-privacy-answers.png\`
- \`$bundle_root/app-store-connect/build/testflight-upload.png\`

EOF

printf 'Prepared Gate 16 evidence bundle at %s\n' "$bundle_root"

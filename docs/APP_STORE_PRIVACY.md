# App Store Privacy And Metadata Checklist

Last updated: 2026-06-29

This file turns the remaining Gate 16 work into auditable release tasks. It does not replace App Store Connect answers; it records the intended repo-side and external decisions that must be verified before submission.

## Repo-Side Privacy Decisions

| Flow | Off device? | Repo artifact decision | App Store Connect decision to verify | Status |
| --- | --- | --- | --- | --- |
| Photo import for editing | No, user-selected local photo data stays on device | `NSPhotoLibraryUsageDescription` is present. No collected data in `PrivacyInfo.xcprivacy`. | Confirm Photos access is disclosed as local user-selected content and not collected by developer. | Repo ready; ASC pending |
| Save/export to Photos or Files | No, export writes to user-selected local destinations | `NSPhotoLibraryAddUsageDescription` is present. Catalyst has user-selected file read/write entitlement. | Confirm no developer collection for exported files. | Repo ready; ASC pending |
| On-device Vision background removal and face crop | No, Vision processing is local | No collected data in `PrivacyInfo.xcprivacy`. | Confirm no AI/cloud processing disclosure is needed for current on-device implementation. | Repo ready; ASC pending |
| Drafts, brand kit, quotas, purchase cache | No, stored locally in app container/UserDefaults | `PrivacyInfo.xcprivacy` declares UserDefaults required reason `CA92.1`. | Confirm local app functionality storage is not collected by developer. | Repo ready; ASC pending |
| Local file metadata access | No, used for app file handling | `PrivacyInfo.xcprivacy` declares File Timestamp required reason `C617.1`. | No separate App Store privacy label expected unless data is transmitted. | Repo ready; ASC pending |
| StoreKit purchases | Apple-mediated; no app backend in repo | No app privacy manifest collected-data entry. | Confirm App Store Connect privacy answers for purchases/account data based on Apple/StoreKit handling. | External pending |
| YouTube import | Yes, app sends a user-provided public video ID to Google YouTube Data API and fetches public metadata/thumbnail bytes | No API key literal in app source; `APIConfig` loads from environment or untracked `Secrets.plist`. No collected data in `PrivacyInfo.xcprivacy` because the app has no developer backend and does not store/transmit user identity. | Explicitly account for the Google/YouTube third-party request in App Store Connect App Privacy answers. Verify whether it remains "Data Not Collected" or requires disclosure under current Apple/Google terms. | External pending |

## Required External Release Tasks

Gate 16 cannot pass until each item below has evidence from the relevant external system.
Record that external evidence in `docs/GATE16_EVIDENCE_PACKET.md`; this file remains the repo-side privacy decision record.

- [ ] Prepare a reviewer-safe local evidence bundle with `scripts/prepare-gate16-evidence-bundle.sh`.
- [ ] Rotate or revoke the previously exposed YouTube Data API key in Google Cloud Console.
- [ ] Create a fresh restricted YouTube Data API key for release builds if YouTube import ships enabled.
- [ ] Verify App Store Connect App Privacy answers, including the Google/YouTube third-party API flow and StoreKit purchase flow.
- [ ] Verify App Store Connect export compliance answer matches `ITSAppUsesNonExemptEncryption = false`.
- [ ] Add and verify support URL.
- [ ] Add and verify marketing URL if required for submission.
- [ ] Complete age rating questionnaire.
- [ ] Upload final App Store screenshots after the last UI change.
- [ ] Run archive validation or TestFlight upload from the release branch.
- [ ] Record evidence links or screenshots for each completed App Store Connect/Google Cloud task.

## Repo Verification Commands

Run these before any release branch handoff:

```sh
scripts/verify-gate16.sh
scripts/prepare-gate16-evidence-bundle.sh
plutil -lint ThumbnailMaker/PrivacyInfo.xcprivacy ThumbnailMaker/ThumbnailMaker.entitlements ThumbnailMaker/Info.plist ThumbnailMaker.xcodeproj/project.pbxproj
find "$BUILT_PRODUCTS_DIR/ThumbnailMaker.app" -name PrivacyInfo.xcprivacy -print
rg -n "AIza|Secrets\\.plist|api[_ -]?key" ThumbnailMaker .github CONFIGURATION.md docs scripts --glob '!ThumbnailMaker/Config/Secrets.plist'
rg -n "Krea|krea" ThumbnailMaker .github CONFIGURATION.md
rg -n "volumeAvailableCapacity|systemUptime|mach_absolute_time|activeInputModes" ThumbnailMaker --glob '*.swift'
```

`scripts/verify-gate16.sh` is intentionally limited to repo-verifiable facts. It checks plist validity, privacy manifest values, required-reason declarations, Catalyst entitlements, display name/version/build settings, photo permission usage, absence of embedded Google API key literals across app/config/workflow/docs/scripts, absence of active Krea integration in app/config/workflow sources, app icon dimensions, and that the 1024 marketing icon has no alpha channel. It prints the App Store Connect and Google Cloud items as `EXTERNAL` rather than marking them complete.

`scripts/prepare-gate16-evidence-bundle.sh` creates a timestamped reviewer-safe folder under `artifacts/gate16-evidence/` with subfolders for Google Cloud, App Store Connect privacy/metadata/screenshots/build evidence, and repo-check logs. Use paths from that bundle when filling `docs/GATE16_EVIDENCE_PACKET.md`.

`scripts/verify-gate16-evidence-packet.sh` validates that `docs/GATE16_EVIDENCE_PACKET.md` is fully filled and internally consistent. It is deliberately not part of `scripts/ci-gate.sh` or the GitHub Actions build while external Google Cloud/App Store Connect evidence is pending, and it will fail until every required row has real evidence or an explicit `N/A`. Run it manually before flipping Gate 16 from Partial to Pass.

For a full release checkout with all font assets present, optionally run:

```sh
VERIFY_GATE16_STRICT_FONTS=1 scripts/verify-gate16.sh
```

## Current Gate 16 Decision

Repo-side privacy content is ready for beta evidence, and previous isolated builds bundled `PrivacyInfo.xcprivacy` for both iOS and Mac Catalyst. On 2026-06-29, the 1024 marketing icon was flattened to an opaque RGB PNG after the Gate 16 verifier caught its alpha channel, and `scripts/verify-gate16.sh` passed in compact-workspace mode. A follow-up repo-side hardening pass widened the Google key literal scan to docs and scripts, then proved it with a temporary docs fixture that failed the verifier as expected before the fixture was removed. GitHub Actions run `28380344405` passed the updated verifier step on `Rippas-Mac-mini.local` from commit `d8ac9bfd749ee1fa415c7c3944026eb2c974ac0b`, including `PASS: No Google API key literals in app/config/workflow/docs/script sources` and `Gate 16 repo verifier passed`. Mac mini run `28407849435` on commit `0811dee4` reran the updated verifier step on `Rippas-Mac-mini.local` while also passing unit, UI smoke, extended UI/accessibility, and Catalyst proof. Latest full Mac mini run `28410216254` on commit `af5d227` reran the verifier again and passed the complete CI plus iPhone/iPad/Mac screenshot path. `docs/GATE16_EVIDENCE_PACKET.md` now provides a fillable worksheet for the remaining external proof, and `scripts/prepare-gate16-evidence-bundle.sh` creates the local evidence folder that the packet should reference. Full Gate 16 remains Partial because App Store Connect answers, support metadata, screenshot upload, release archive validation, and YouTube API key rotation are external tasks that cannot be proven from the local repo alone.

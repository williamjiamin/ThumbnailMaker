# Gate 16 External Evidence Packet

Last updated: 2026-06-29

Status: PENDING - this worksheet records external proof only after it exists.

Prepare a local evidence folder with `scripts/prepare-gate16-evidence-bundle.sh`, then validate completeness with `scripts/verify-gate16-evidence-packet.sh` after the external rows are filled. This verifier is intentionally not wired into CI while the Google Cloud and App Store Connect work is pending.

This packet does not make Gate 16 pass by itself. Gate 16 can pass only when every row below has evidence from the named external system, a recorded decision/value, and a verified-by entry.

## Evidence Rules

- Do not paste secrets, full Google credentials, App Store Connect session URLs, or private account screenshots that expose tokens.
- Reference Google credentials by key ID, last four characters, or fingerprint only.
- Evidence fields must contain `N/A`, an `http(s)` URL, or a local path that exists from the repository root or as an absolute path.
- Keep all default verdicts as `PENDING` until the actual external system has been checked.
- App Store Connect answer text below is proposed language to verify, not a claim about what was selected.
- Use absolute dates, for example `2026-06-29`.

## Source References

- Apple App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Apple App Privacy Details: https://developer.apple.com/help/app-store-connect/reference/app-privacy-details
- Apple Export Compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- Apple Screenshot Specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Apple Age Ratings: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating
- Apple App Information: https://developer.apple.com/help/app-store-connect/manage-app-information/provide-app-information
- Google Cloud API Keys: https://cloud.google.com/docs/authentication/api-keys

## Evidence Ledger

| Task | Owner and account/system | Date completed | Evidence link or screenshot path | Decision/value recorded | Pass criteria | Verified by/date | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Revoke or rotate previously exposed YouTube Data API credential | PENDING | PENDING | PENDING | PENDING | Google Cloud shows old credential disabled, deleted, or rotated; no live release depends on it. | PENDING | PENDING |
| Create fresh restricted release YouTube credential if YouTube import ships enabled | PENDING | PENDING | PENDING | PENDING | Credential is restricted to YouTube Data API v3 and appropriate app restrictions; value is stored only in untracked local config or secure CI/App Store build secret. | PENDING | PENDING |
| Verify App Store Connect App Privacy answers | PENDING | PENDING | PENDING | PENDING | Answers match `docs/APP_STORE_PRIVACY.md`, current app behavior, YouTube third-party request, StoreKit, Photos, and local storage. | PENDING | PENDING |
| Verify export compliance | PENDING | PENDING | PENDING | PENDING | App Store Connect export compliance answer matches `ITSAppUsesNonExemptEncryption = false`. | PENDING | PENDING |
| Add and verify support URL | PENDING | PENDING | PENDING | PENDING | App Store Connect support URL is live, reachable without login, and matches app metadata. | PENDING | PENDING |
| Add and verify marketing URL if used | PENDING | PENDING | PENDING | PENDING | Marketing URL is either intentionally omitted if allowed or live/reachable if supplied. | PENDING | PENDING |
| Complete age rating questionnaire | PENDING | PENDING | PENDING | PENDING | Age rating questionnaire is complete and reflects app content, YouTube import, purchases, and user-generated/imported media behavior. | PENDING | PENDING |
| Upload final App Store screenshots | PENDING | PENDING | PENDING | PENDING | Final iPhone, iPad, and Mac screenshots are uploaded after the last UI change and match current shipped UI. | PENDING | PENDING |
| Run release archive validation or TestFlight upload | PENDING | PENDING | PENDING | PENDING | Archive validation or TestFlight upload succeeds from the release branch/commit. | PENDING | PENDING |
| Capture final evidence bundle | PENDING | PENDING | PENDING | PENDING | This packet has evidence links/paths and verification entries for every required external task. | PENDING | PENDING |

## Google Cloud Credential Evidence

| Field | Value |
| --- | --- |
| Google Cloud project name/id | PENDING |
| Old credential identifier, last four, or fingerprint | PENDING |
| Old credential action | PENDING - disabled, deleted, or rotated |
| Old credential action timestamp | PENDING |
| Evidence screenshot/path for old credential action | PENDING |
| New release credential identifier, last four, or fingerprint | PENDING |
| New credential API restriction | PENDING - expected: YouTube Data API v3 only |
| New credential app/referrer/bundle restriction | PENDING |
| YouTube import ships enabled in this release | PENDING - yes/no |
| Runtime storage location for release value | PENDING - secure build setting, CI secret, or untracked local config; never committed |
| Verified by/date | PENDING |

## Proposed App Store Connect Privacy Answers

These are proposed answers to verify in App Store Connect. They are not confirmed until the evidence ledger row is filled.

### Photos And Files

VERIFY IN ASC - proposed:

- Photo import uses user-selected local photos for editing.
- Export writes image files to user-selected local destinations or Photos.
- ThumbnailMaker does not upload imported/exported images to developer servers.
- Proposed developer data collection answer: no developer collection for imported/exported image content.

Evidence to attach: App Store Connect App Privacy screenshot or exported metadata showing the selected answer.

### On-Device Vision Cutout And Face Crop

VERIFY IN ASC - proposed:

- Background removal and face crop use on-device Vision/Core Image processing.
- No image is sent to a developer AI service for the current beta scope.
- Proposed developer data collection answer: no developer collection for on-device Vision processing.

Evidence to attach: App Store Connect App Privacy screenshot plus release notes confirming no cloud AI provider is enabled.

### Local Drafts, Brand Kit, Quotas, And Purchase Cache

VERIFY IN ASC - proposed:

- Drafts, brand kit settings, quota counters, and purchase cache are stored locally in the app container/UserDefaults.
- `PrivacyInfo.xcprivacy` declares UserDefaults required reason `CA92.1`.
- Proposed developer data collection answer: local app functionality storage is not collected by developer.

Evidence to attach: App Store Connect App Privacy screenshot or metadata export.

### StoreKit

VERIFY IN ASC - proposed:

- Purchases are Apple-mediated through StoreKit.
- The app has no custom account backend in this repo.
- Verify whether App Store Connect requires purchase/account disclosure based on the exact StoreKit selections and Apple guidance.

Evidence to attach: App Store Connect App Privacy screenshot and StoreKit/product metadata screenshot.

### YouTube Import

VERIFY IN ASC - proposed:

- The user explicitly enters or pastes a public YouTube video URL or ID.
- The app sends that public video ID to the Google YouTube Data API to fetch public metadata and thumbnail bytes.
- The app has no developer backend for this flow and does not store user identity or YouTube browsing history on developer servers.
- Verify whether App Store Connect remains "Data Not Collected" or requires disclosure for the third-party Google request under current Apple/Google terms.

Evidence to attach: App Store Connect App Privacy screenshot and Google Cloud API restriction screenshot.

## Export Compliance Evidence

| Field | Value |
| --- | --- |
| App Store Connect export compliance answer | PENDING |
| Matching repo value | `ITSAppUsesNonExemptEncryption = false` |
| Evidence screenshot/path | PENDING |
| Verified by/date | PENDING |

## Metadata Evidence

| Field | Value |
| --- | --- |
| Bundle identifier | `com.williamjiamin.ThumbnailMaker` |
| Display name | `Thumbnail Maker` |
| Marketing version/build | `1.0.8` / `9` |
| Support URL | PENDING |
| Marketing URL | PENDING |
| Privacy policy URL | PENDING |
| Age rating result | PENDING |
| App Review notes | PENDING |
| Verified by/date | PENDING |

## Screenshot And Build Evidence

| Field | Value |
| --- | --- |
| Final iPhone screenshots uploaded | PENDING |
| Final iPad screenshots uploaded | PENDING |
| Final Mac screenshots uploaded | PENDING |
| Screenshot source directory or App Store Connect evidence | PENDING |
| Release branch/commit used for archive | PENDING |
| Archive validation result | PENDING |
| TestFlight upload/build number | PENDING |
| Verified by/date | PENDING |

## Final Gate 16 Sign-Off

Gate 16 remains `Partial` until all fields below are complete.

| Field | Value |
| --- | --- |
| All evidence ledger rows are non-PENDING | PENDING |
| All evidence links/screenshots are reachable by reviewer | PENDING |
| Google Cloud credential rotation/restriction evidence complete | PENDING |
| App Store Connect privacy/metadata/export compliance evidence complete | PENDING |
| Final release branch/commit | PENDING |
| Final reviewer | PENDING |
| Final review date | PENDING |
| Gate 16 verdict | PENDING |

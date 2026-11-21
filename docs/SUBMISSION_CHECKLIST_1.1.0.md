# ThumbnailMaker 1.1.0 (build 10) — submission checklist

Prepared 2026-09-28. Everything under **Done** was verified by an independent re-run, not taken from
an agent's report. Everything under **Yours** needs your accounts, credentials or a product decision.

## Done

| Item | Evidence |
|---|---|
| 15 feature packages (FEATURE-01…15) integrated | see `APP_STORE_WHATS_NEW_1.1.0.md` feature map |
| Reliability fixes APP-01…06 | tests green (lossless PNG, entitlements, visible save state, import errors, stale-import guard, readiness) |
| Performance APP-09 | shared encoded image buffers; 256 MB undo cap across variants |
| Accessibility APP-07 + compact phone APP-08 | UI audits pass; AX3 Dynamic Type test passes |
| All 20 fonts bundled + licences | `FontRegistrationTests` |
| Undo disabled for 0.6 s after edits — fixed | `ImmediateUndoTests` (fails without the fix, verified) |
| **Unit suite** | 699 tests / 74 suites, 0 failures |
| **UI suite** (iPhone 16 Pro Max, erased simulator) | 52 tests, 0 failures, 1 skipped (needs iPad) |
| Release build, iOS | BUILD SUCCEEDED, 1.1.0 (10), 73 MB, min iOS 18.1, SDK iOS 27 |
| Release build, Mac Catalyst | BUILD SUCCEEDED |
| iPad multitasking orientations | all four added for iPad |
| Mac app category | `public.app-category.graphics-design` (change if you prefer Photo & Video) |
| Paywall | non-consumable lifetime purchase; price, Restore, Terms/Privacy present — subscription disclosure rules don't apply |
| Privacy | only network use is the YouTube Data API when a user pastes a link; no analytics/tracking |

## Yours — required before upload

1. **App display name.** Still "Thumbnail Maker", which is identical to several existing apps (Guideline 4.3(b) risk).
   You said you'd pick one. Set `INFOPLIST_KEY_CFBundleDisplayName` and the App Store Connect name.
2. **YouTube API key.** Create `ThumbnailMaker/Config/Secrets.plist` from `Secrets.example.plist` with the
   **rotated** key, and restrict the key to bundle ID `com.williamjiamin.ThumbnailMaker` in Google Cloud.
   Without it, YouTube import fails in the shipped build.
3. **Signing and archive.** Everything was built with `CODE_SIGNING_ALLOWED=NO`. Archive with your team in Xcode
   (Product → Archive) and upload through Organizer. I don't handle credentials or submit on your behalf.
4. **App Store Connect.** Paste the What's New text; App Privacy = no data collected (the YouTube request carries
   no user identifiers); screenshots — the existing set predates 15 new features, so regenerate
   (`AppStoreScreenshotTests` / `scripts/capture-screenshots.sh`).
5. **Gate 4 (your own rule, `docs/CI_GATES.md`).** Exact-revision unit + UI + Catalyst evidence from the Mac mini.
   These local runs don't count toward it. Commit the tree, then run the Mac mini workflow.

## Known limits (honest list — none block submission)

- New UI is covered by 9 smoke UI tests plus accessibility audits; not every flow has an end-to-end UI test.
- Not run on an iPhone SE-size or iPad simulator (the iPad layout test is skipped on iPhone).
- Deferred slices, recorded per feature: group snapping/workspace zoom (07), per-row variant columns in series (15),
  import downsampling (09), photo-save filenames for variants (02), stored template previews (05).
- The app is 73 MB, mostly fonts; the two CJK fallback fonts are ~30 MB if size ever matters.
- **Nothing is committed to git yet.** The work lives in your project folder (synced) and `~/ThumbnailMaker-work`.

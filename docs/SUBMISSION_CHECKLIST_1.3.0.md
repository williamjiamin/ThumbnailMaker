# Simple Thumbnail 1.3.0 (build 10) — submission checklist

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
| Release build, iOS | BUILD SUCCEEDED, 1.1.0 (10) — now **1.3.0**, must exceed live 1.2.0, 73 MB, min iOS 18.1, SDK iOS 27 |
| Release build, Mac Catalyst | BUILD SUCCEEDED |
| iPad multitasking orientations | all four added for iPad |
| Mac app category | `public.app-category.graphics-design` (change if you prefer Photo & Video) |
| Paywall | non-consumable lifetime purchase; price, Restore, Terms/Privacy present — subscription disclosure rules don't apply |
| Privacy | only network use is the YouTube Data API when a user pastes a link; no analytics/tracking |

## Yours — required before upload

0. **STOP — confirm the source.** The live listing is **1.2.0** (2026-03-25) with **Premium Weekly $0.99,
   Premium Monthly $2.99** and Lifetime $9.99. This repo (and GitHub `master`) is 1.0.8 with **only** the lifetime
   product `com.williamjiamin.ThumbnailMaker.premiumlifetime2024`. Shipping this tree as-is would stop recognising
   weekly/monthly subscribers. Locate the 1.2.0 source (Mac mini?) and either merge this work into it, or add the
   subscription product IDs here — before uploading anything.
1. **Name — decided.** Display name is now **Simple Thumbnail** (in-app strings, legal text and project-file type
   renamed). App Store Connect metadata to paste:
   - Name (16/30): `Simple Thumbnail`
   - Subtitle (24/30): `Cover Maker for Creators`
   - Keywords (97/100): `editor,design,template,text,font,photo,background,remover,banner,channel,art,poster,podcast,video`
   The home-screen label shows ~12 characters, so "Simple Thumbnail" displays as "Simple Thumb…". Say if you want a
   shorter display name there.
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


## Status 2026-09-30 (supersedes the lists above where they differ)
**Done:** 1.1.0/1.2.0 features rebuilt (tabs, Quick Create wizard, gradients, quick-add strip, Library, Actions; weekly/monthly/
lifetime subscriptions with the exact App Store Connect product IDs and a disclosure-compliant paywall); meme-maker ports; video frame
grabber; 33 templates; rating prompt; version **1.3.0 (15)**. Verified: 869 unit tests / 93 suites, 66 UI tests with 0 failures on an erased
simulator, Release iOS + Mac Catalyst builds. App Store Connect 1.3.0 draft: name, subtitle, keywords, description, What's New,
promo text, and 12 screenshots all set.

**Only you can do (in order):**
1. Add `ThumbnailMaker/Config/Secrets.plist` with the **rotated** YouTube API key (bundle-ID-restricted in Google Cloud).
2. Xcode → Product → Archive (Release, your team's signing) → Distribute → App Store Connect upload. Build number is 15.
3. In App Store Connect, 1.3.0 → Build → select build 15 once processing finishes, and answer the export-compliance prompt
   (`ITSAppUsesNonExemptEncryption = false` is already set).
4. Check App Review Information (contact, notes: no login needed; subscriptions can be tested in sandbox).
5. Press **Add for Review / Submit**. (Your Gate 4 rule: run the Mac mini CI on the exact commit first.)
6. Commit the work to git: nothing is committed yet. The complete tree is ~/ThumbnailMaker-work/proj, mirrored in this folder.

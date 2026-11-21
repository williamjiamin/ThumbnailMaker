# ThumbnailMaker Product and Engineering Orchestration

Date: 2026-06-14
Repo: https://github.com/williamjiamin/ThumbnailMaker.git

## Current-State Audit

### Product Surface

- Native SwiftUI iOS app with two tabs: Simple Maker and Premium Maker.
- Current editor supports photo import, text overlay, font/color/direct-transform status, first explicit layer-selection strip for current overlays with hide/show and lock/unlock controls, first on-canvas flip/rotate/resize handles, aspect-ratio switching, export presets/formats, first platform safe-zone guide overlays, save-to-Files/share/Photos export, encoded file-size checks, first creator-readiness scoring, small-size preview checks, local Simple/Premium draft autosave/restore, first document-backed undo/redo, a circular profile overlay, batch numbering, YouTube thumbnail import, local legal docs, and StoreKit lifetime unlock.
- The active 3x3 position picker controls have been removed from Simple and Premium editor flows. Text overlays now use normalized drag/rotate/flip/reset transforms plus visible manipulation handles; Premium profile overlays use the same normalized transform and handle pattern. Redundant inspector-side transform and size controls are no longer shown for active text/profile placement, so manipulation now happens on the canvas.
- No web app exists in the repo today.
- No professional layer renderer or full layer editing workflow exists yet. First persistent document layer records now exist for the current background/profile/text overlays, and text/profile layers can now be hidden/shown, locked/unlocked, and moved forward/backward from the Layers strip. There are still no reusable image/shape/sticker layers, arbitrary drag reordering, layer-aware command history, alignment guides, templates, brand kit, background removal, or AI ideation.

### Architecture

- Xcode project with one app target plus unit/UI test targets.
- SwiftUI views currently own a lot of workflow logic directly.
- Rendering still starts from SwiftUI views through `ImageRenderer`, but this pass introduces a shared `ThumbnailExporter` service and `ThumbnailExportOptions` model.
- Export writes encoded image data through a shared service to Photos, a temporary share-sheet file, or a document picker file export, with platform presets, PNG/JPEG/WebP format selection where supported, compression controls for lossy formats, custom dimensions, encoded file-size warnings for known upload limits, first preset safe-zone metadata, a first small-preview panel, and a first local creator-readiness analyzer for text density, mobile preview text size, and known-background contrast.
- Safe-zone guidance is visual-only for now: `ThumbnailSafeZone` metadata feeds `SafeZoneOverlayView` in the interactive preview and export settings copy, while export/share/save render paths intentionally omit the overlay.
- The readiness analyzer is intentionally not image-aware yet; face visibility, automated safe-zone checks, and contrast against photo regions remain future Vision/Core Image work.
- Direct manipulation uses `ThumbnailOverlayTransform`, a normalized x/y plus rotation/flip model so preview and export rendering stay aligned across phone preview, iPad preview, and final export sizes. First on-canvas manipulation handles adjust the existing text size and profile size fields so preview, draft persistence, undo/redo, and export rendering continue to share one state path.
- Simple Maker and Premium Maker now keep local overlay-selection state in the editor surface. A shared `ThumbnailEditorLayer` enum and `LayerSelectionStripView` let the current text/profile overlays be selected explicitly, hidden/shown, locked/unlocked, and moved forward/backward. Hidden layers remain available in the strip but are omitted from preview/export; locked layers remain visible but reject drag/rotate/resize/flip gestures.
- Only the selected overlay shows manipulation chrome; Premium no longer displays text and profile handles at the same time. Inspector panels now show a compact transform status row with reset instead of duplicate rotate/flip/size controls.
- Interactive editor preview dimensions are clamped during early `GeometryReader` layout passes to avoid negative/non-finite SwiftUI frame warnings.
- Legacy alignment/profile-position fields remain in the model for backward compatibility and draft migration, but the active preview/export path is transform-based.
- Simple and Premium Maker now persist through a first versioned `ThumbnailDocument` JSON bridge in Application Support. The document stores primitive/raw-value state plus image bytes, projects to/from the existing UI configuration structs, includes stable `background`/`profile`/`text` layer records for the current overlays, preserves text/profile visibility and lock state, and keeps a legacy decoder for the original Simple Maker draft format.
- `ThumbnailDocument.layers` is now a foundation for a future layer tree, and current text/profile visibility, lock state, and z-order drive preview/export and gesture behavior. Rendering/export still intentionally read the existing top-level image/text/profile payloads for actual content, with explicit SwiftUI stack depth applied so moved overlays repaint in persisted order. The next migration must make layers the source of truth before adding delete/duplicate/arbitrary reorder workflows.
- First undo/redo uses `ThumbnailDocumentHistory`, a bounded value-snapshot stack shared by Simple and Premium Maker. Snapshots normalize `updatedAt` so unchanged documents are coalesced instead of creating timestamp-only history entries.
- YouTube import depends on the YouTube Data API. No Krea.ai integration or other stale AI API was found in the current tree.

### Platform Support

- Before this pass, the app target was iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
- This pass changes the app target to iPhone+iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- This pass also enables portrait plus landscape-left/landscape-right orientations and adds first seeded iPhone/iPad landscape UI smoke coverage.
- The project still supports only `iphoneos` and `iphonesimulator`; macOS/Catalyst is not enabled yet.
- Deployment target is iOS 18.1, which is publishable but unnecessarily narrow for reach unless the app needs iOS 18-only APIs.

### Repo Hygiene

- Publish blockers found:
  - A real `ThumbnailMaker/Config/Secrets.plist` with a YouTube API key was tracked.
  - `.cursor/debug.log` was tracked and is about 55 MB.
  - Finder metadata and Xcode user state were tracked.
- This pass removes those tracked artifacts and adds `Secrets.example.plist`.
- Required manual follow-up: revoke or rotate the exposed YouTube API key in Google Cloud Console because it remains in Git history.

### Tests and CI

- Unit tests covered only one font fallback case.
- UI tests were stock launch/performance scaffolding.
- CI built the app on a self-hosted macOS runner but did not build test bundles.
- This pass adds YouTube URL extraction tests, export model/encoder/temp-file/render-size/file-export/file-size-warning/safe-zone metadata tests, creator-readiness analyzer tests, direct-transform and manipulation-handle geometry tests, shared document/draft store tests, document history undo/redo tests, Simple/Premium draft restore tests, Simple/Premium undo/redo view-model tests, export settings/export-size/small-preview/landscape/undo-redo toolbar/safe-zone guide/direct-manipulation-handle UI smoke tests, and a CI `build-for-testing` step.
- Local xcodebuild verification has been run repeatedly, including the same build and build-for-testing commands used by CI. The implementation checkpoints `74483ea` and `ba41c87` passed the self-hosted GitHub Actions / Mac mini workflow on branch `codex/publish-readiness-m1` in runs `27521285018` and `27521951546`.

### App Store Readiness

- Good: local photo processing, local quota counters, StoreKit 2 purchase flow, local privacy policy and terms.
- Needs work:
  - Rotate exposed API key.
  - Verify StoreKit product is configured, visible, restorable, and described in metadata.
  - Add support URL/contact path.
  - Ensure App Privacy labels disclose third-party YouTube API use and any future AI services.
  - Avoid hidden/beta/incomplete AI claims until implemented and reviewable.
  - Broaden device/simulator smoke tests for premium editor, settings/legal, YouTube error states, and save/share permissions.

## Competitor Research Matrix

| Product | Current strengths | ThumbnailMaker implication |
| --- | --- | --- |
| Canva | Massive template library, drag-and-drop editor, Magic Studio AI tools, brand/collaboration, JPEG/PNG export. Source: https://www.canva.com/create/youtube-thumbnails/ | Compete by being faster and narrower for creator thumbnails, with presets, small-preview validation, and less generic UI. |
| Adobe Express | All-in-one editor, one-click edits across devices, generative AI, templates, stock/upload/AI entry points. Source: https://www.adobe.com/express/create/thumbnail/youtube | Need polished guided workflows, not just raw controls. AI should assist layouts and variants while keeping manual editability. |
| CapCut | Video-native workflow, thumbnail templates, drag-and-drop, AI prompt-to-thumbnail and AI-generated layouts/palettes. Source: https://www.capcut.com/create/youtube-thumbnail | Differentiator should be dedicated cover export quality and platform-specific safe zones, especially for Shorts/TikTok/Reels. |
| Photoroom | Very strong cutouts/background removal, AI backgrounds, enhancement, batch workflows, PNG/JPEG/WebP export. Source: https://www.photoroom.com/tools/background-remover | Background removal and batch export need to become first-class, privacy-first features. |
| Picsart | AI thumbnail concepts through Picsart Aura, pro editing tools, templates, fonts, stickers, social formats. Source: https://picsart.com/design/youtube-thumbnails/ | Ideation should generate editable thumbnail briefs/layouts, not only flattened images. |
| Pixelcut | Fast background remover, free HD/no-watermark positioning, AI backgrounds, batch background removal, mobile apps. Source: https://www.pixelcut.ai/background-remover | On-device cutout quality and simple before/after refinement are table stakes. |
| VEED | Template-first plus prompt edits, multiple variants for A/B testing, YouTube/course/blog/podcast covers, PNG export. Source: https://www.veed.io/create/thumbnails | Best opportunity: template + prompt changes + variant generation, but with deterministic editable layers. |
| YouTube Studio | Custom thumbnail upload, Ask Studio suggestions, A/B testing, 3840x2160 guidance, and upload file-size limits that vary by mobile/desktop and video/podcast use. Source: https://support.google.com/youtube/answer/72431 | Export presets should include 3840x2160 recommendation, 16:9 checks, file-size warnings, small-preview readability, and A/B variant naming. |
| Instagram/Reels/TikTok workflows | Cover images are vertical-first with feed/grid crops and safe-zone issues. Instagram reports 420x654 cover guidance on current help pages. Source: https://help.instagram.com/1038071743007909 | Need per-platform safe-zone overlays, not just aspect ratios. |
| Figma/template workflows | Flexible manual design and community templates, but creators can export wrong sizes/aspects and must manage compression manually. | ThumbnailMaker can win by preventing invalid exports and giving creator-specific heuristics. |

## Better-Than-Competitor Roadmap

### Table Stakes

- Layered editor: image, text, shape, sticker, cutout, background, gradient, blur layers.
- Touch and pointer editing: drag, resize, rotate, snap, align, distribute, duplicate, lock, hide, z-order.
- Text tools: font browser, outlines, shadows, strokes, background pills, letter/line spacing, multiline fitting.
- Export presets: YouTube, Shorts/TikTok/Reels, Instagram feed/story, podcast/video cover, custom.
- Export formats: PNG, JPEG, WebP where platform APIs support it, with quality/compression controls and target file size warnings.
- Undo/redo and autosaved drafts.
- Template gallery and starter layouts.

### Differentiators

- Creator-readiness checks: small-preview readability, contrast score, face visibility, safe-zone warnings, "too much text" warnings.
- Variant generation: deterministic layout/color/text variants from the same editable document.
- Privacy-first AI: use on-device Vision/Core Image where feasible for cutouts, face detection, color suggestions, crop suggestions, and enhancement.
- Prompt-to-edit, not prompt-to-flatten: AI suggests layer changes that remain editable.
- Platform-safe export packs: generate YouTube 16:9, Shorts cover, Instagram grid-safe preview, and podcast square from one document.

## Technical Architecture Plan

### Shared Core

- Create a `ThumbnailDocument` model independent of SwiftUI views.
- Define stable layer types: `background`, `image`, `cutout`, `text`, `shape`, `sticker`, `group`.
- Store documents as versioned JSON so iOS, iPadOS, macOS, and web can share projects and templates.
- Add a renderer abstraction:
  - Apple platforms: Swift renderer backed by Core Graphics/Core Image/SwiftUI only at the final view boundary.
  - Web: Canvas/WebGL renderer with golden image tests against fixture documents.
- Add command-based editing (`EditorCommand`) for undo/redo and collaboration-safe future history.

### Apple Platforms

- Keep one SwiftUI codebase for iOS and iPadOS.
- Split platform services behind protocols: photo import/save, file export, share sheet, purchase, network, AI provider.
- Add iPad layout with `NavigationSplitView`, inspector panels, keyboard shortcuts, pointer hover, and drag/drop.
- Prepare macOS using Catalyst first if build risk is acceptable; move to native AppKit wrappers only for features Catalyst cannot handle well.

### Web

- Add web as a separate app once the document schema and renderer fixtures are stable.
- Recommended stack: TypeScript + React + canvas editor library or custom canvas renderer, with the same JSON document fixtures as Apple tests.
- Web should launch with editor/export parity before AI-heavy features.

### AI

- Tier 1 on-device: subject/person segmentation, face detection, crop suggestions, contrast/color checks, blur/background effects.
- Tier 2 optional cloud AI: title-to-thumbnail ideas, prompt-to-layout, style presets, variant copy. Require explicit user consent and privacy disclosure before sending images, titles, or personal data to third parties.
- Never generate style/face clones of identifiable creators without permission.

## App Store Review Readiness Checklist

- [x] Remove tracked API secret from source tree.
- [x] Add example secrets file and configuration note.
- [x] Remove automatic clipboard reads from YouTube import.
- [x] Add iPad target family support.
- [x] Add missing iPad app icon sizes flagged by Xcode asset validation: 76x76@2x and 83.5x83.5@2x.
- [x] Add first export settings smoke test.
- [x] Add share-sheet export support backed by temporary encoded files.
- [x] Add save-to-Files export support backed by exact encoded file data.
- [x] Verify export render size follows the selected export preset/custom size.
- [x] Add first encoded file-size checks and YouTube/podcast upload-limit warnings.
- [x] Add first small-preview UI and smoke coverage for thumbnail readability checks.
- [x] Add first local creator-readiness score for text density, mobile text size, and known-background contrast.
- [x] Add first visual platform safe-zone/crop guidance for export presets.
- [x] Remove active 3x3 position picker controls from Simple/Premium editor flows.
- [x] Add first WYSIWYG text/profile transform model with drag, rotate, flip, and reset controls.
- [x] Add first visible on-canvas flip/rotate/resize handles for text/profile overlays.
- [x] Remove redundant inspector-side transform/size controls from active text/profile placement flows.
- [x] Add first selected-overlay chrome so Premium text/profile handles are not shown simultaneously.
- [x] Add first explicit Layers strip for current text/profile overlay selection.
- [x] Clamp editor preview layout dimensions to avoid invalid-frame runtime warnings.
- [x] Add first persistent document layer records for current background/text/profile state.
- [x] Add first layer visibility/lock controls for current text/profile overlays, with draft/document/undo preservation.
- [x] Add first layer forward/backward controls for current Premium text/profile overlays, with persisted z-order and explicit preview stack depth.
- [x] Enable portrait plus landscape orientations for iPhone/iPad and add seeded landscape smoke coverage.
- [x] Add first local Simple Maker draft autosave/restore.
- [x] Add first shared `ThumbnailDocument` JSON bridge and Premium Maker draft autosave/restore.
- [x] Add first document-backed undo/redo toolbar and history.
- [ ] Rotate exposed YouTube API key.
- [ ] Verify clean full checkout no longer pulls `.cursor/debug.log`.
- [ ] Run full app build and tests with fonts included.
- [ ] Add App Store support URL and contact email/site.
- [ ] Confirm IAP product ID, display name, pricing, restore flow, and review notes.
- [ ] Confirm privacy policy and App Privacy labels match YouTube API, purchases, photo library, and any future AI providers.
- [ ] Add screenshots for iPhone, iPad, and later macOS.
- [ ] Add accessibility pass: Dynamic Type, VoiceOver labels, contrast, tap target sizes.
- [ ] Add crash-free smoke tests for simple editor, premium editor, YouTube import error state, save flow, and settings/legal screens.

## Prioritized Implementation Milestones

### M0: Stabilize and De-risk

- Remove secrets/dev artifacts.
- Rotate leaked API key.
- Build cleanly from a fresh full checkout.
- Add smoke tests and CI test-bundle build.
- Fix obvious App Store privacy issues.

### M1: Publishable Native MVP

- Replace Simple/Premium split with guided "Create" workflow plus upgrade gates inside features.
- Expand export panel with platform presets, PNG/JPEG/WebP where supported, share sheet, Photos save, save-to-Files, small-preview checks, broader platform upload-limit warnings, and automated readability scoring. First text-based readiness scoring and visual safe-zone overlay exist; image-aware contrast, automated safe-zone warnings, and face visibility remain open.
- Replace old position-pickers with WYSIWYG canvas manipulation. First normalized text/profile transforms, visible manipulation handles, selected-overlay chrome, explicit current-overlay Layers strip, persistent background/profile/text layer records, and first visibility/lock/order interactions exist; snapping, alignment guides, arbitrary layer reordering, and full document-layer interactions remain open.
- Add project/draft persistence. First shared `ThumbnailDocument` persistence now covers Simple and Premium drafts; the future layer document/asset store still needs a proper project-file migration.
- Add undo/redo. First document-backed value-snapshot undo/redo exists; layer-aware command history remains open.
- Add iPad inspector layout; first screenshot coverage exists but the layout is not yet tablet-native.

### M2: Professional Editor Foundation

- Migrate `ThumbnailDocument.layers` from stable current-overlay records into the renderer source of truth, with fixtures, selection model, and command-based undo/redo.
- Migrate current photo/text/profile features into layers.
- Add alignment guides, snapping, layer list, shapes, gradients, shadows, outlines, and stickers.

### M3: Creator Templates and Brand Kit

- Template library by niche: gaming, education, vlog, podcast, product, fitness, finance, reaction, tutorial.
- Brand colors/fonts/logos and reusable styles.
- Batch export packs and series templates.

### M4: AI Assistance

- On-device cutouts, crop/face/contrast/readability suggestions.
- Title-to-layout ideas and editable layer variants.
- Explicit consent and privacy labels for any cloud AI.

### M5: macOS and Web

- Catalyst/native macOS release with desktop layout, file export, keyboard shortcuts, drag/drop.
- Web editor with the shared document schema and export presets.

## Verification Log for This Pass

- `xcodebuild build -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After export changes, `xcodebuild build -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After export/share changes, `xcodebuild build -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After export/share changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 8 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsSheetOpens -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After small-preview changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 9 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After save-to-Files and export-size changes, `xcodebuild build -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After save-to-Files and export-size changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 11 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After orientation changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 11 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsSheetOpens -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSeededEditorLandscapeLayout -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=19DC26BF-9347-48D0-98AE-77A8843B7611' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSeededEditorLandscapeLayout -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded after correcting the iPad title landmark to the navigation bar.
- After Simple Maker draft autosave/restore changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 13 tests.
- After Simple Maker draft autosave/restore changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsSheetOpens -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSeededEditorLandscapeLayout -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After creator-readiness analyzer changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 16 tests.
- After creator-readiness analyzer changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded and verified the `creatorReadinessLabel`.
- After creator-readiness analyzer changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsSheetOpens -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSeededEditorLandscapeLayout -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded. Xcode logged one transient cloned-runner launch warning, but the suite completed green on the active iPhone 16 Pro clone.
- `claude -p 'Review the ThumbnailMaker SwiftUI codebase for a narrow implementation plan: remove all 3x3 position picker controls and move toward WYSIWYG direct manipulation for text/profile overlays...'` completed and recommended normalized transform state to preserve preview/export parity.
- After WYSIWYG transform changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 17 tests.
- After WYSIWYG transform changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSizeCheckShowsFileSize -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSeededEditorLandscapeLayout -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded. Xcode logged one transient cloned-runner launch warning after success, but all requested tests passed on the active iPhone 16 Pro clone.
- `claude -p 'In the ThumbnailMaker SwiftUI repo at /Users/williamjiamin/Documents/ThumbnailMaker 2, review the current architecture for the next narrow publish-readiness milestone...'` completed and recommended a shared `ThumbnailDocument` persistence bridge before a full layer/command rewrite.
- After shared document and Premium draft persistence changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 22 tests.
- After shared document and Premium draft persistence changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-BFT-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- Self-hosted GitHub Actions CI / Mac mini run `27493964974` passed on branch `codex/publish-readiness-m1` for commit `9854349` in 1m4s. It completed checkout, project/scheme discovery, iOS Simulator build, and iOS Simulator `build-for-testing`.
- Two earlier workflow-dispatch attempts for commit `9854349` were cancelled after runner-side checkout connectivity failures to `github.com:443`; the successful rerun indicates an intermittent runner/network issue, not a build failure.
- Self-hosted GitHub Actions CI / Mac mini run `27494039445` passed on branch `codex/publish-readiness-m1` for commit `45c0b92`. It covered the recorded document persistence checkpoint before the undo/redo milestone.
- `claude -p 'In /Users/williamjiamin/Documents/ThumbnailMaker 2, review the next narrow undo/redo milestone...'` completed and recommended value-snapshot history first, `updatedAt` normalization, reentrancy guards, and suppressing Premium batch-number history noise.
- After document-backed undo/redo changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 27 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testUndoRedoToolbarButtonsAppear -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded and captured `undo-redo-toolbar`.
- After document-backed undo/redo changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-BFT-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 Pro undo/redo toolbar screenshot reviewed: `/tmp/thumbnailmaker-undo-ui/5BB11CB8-5CC9-4EA4-8FA8-2FE3F2B3C4A4.png`.
- `claude -p 'In /Users/williamjiamin/Documents/ThumbnailMaker 2, review a narrow next milestone for export safe-zone guidance...'` completed and recommended preset metadata plus a shared visual overlay first, with automated analyzer warnings deferred until layer/bounds geometry exists.
- After safe-zone guide changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 29 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSafeZoneGuideAppearsInPreview -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded and captured `safe-zone-guide`.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testExportSettingsSheetOpens -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded after the export settings accessibility identifiers were restored.
- iPhone 16 Pro safe-zone guide screenshot reviewed: `/tmp/thumbnailmaker-safezone-ui-1839/E701D7C4-1AD6-408B-86BB-C206B98BA682.png`.
- Two follow-up `claude -p` attempts for the next WYSIWYG handle milestone returned no usable output and were stopped after hanging; implementation proceeded from repo evidence and existing tests.
- After direct manipulation handle changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 31 tests.
- `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testDirectManipulationHandlesAppearForTextOverlay -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded and captured `direct-manipulation-handles`.
- After direct manipulation handle changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-BFT-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 Pro direct manipulation handles screenshot reviewed: `/tmp/thumbnailmaker-direct-handles-ui-1912/D741D952-6A1B-4AB4-ADD6-CA47C8336DD5.png`.
- `claude -p 'In /Users/williamjiamin/Documents/ThumbnailMaker 2, review the SwiftUI editor code for a narrow WYSIWYG milestone...'` was attempted for the selected-overlay cleanup, but returned no usable output and was interrupted after hanging.
- After selected-overlay WYSIWYG cleanup, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded with 31 tests.
- After selected-overlay WYSIWYG cleanup, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testDirectManipulationHandlesAppearForTextOverlay -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumCanvasShowsSingleOverlayChromeByDefault -derivedDataPath /tmp/ThumbnailMaker-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- After selected-overlay WYSIWYG cleanup, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-BFT-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 Pro selected-overlay screenshots reviewed: `/tmp/thumbnailmaker-wysiwyg-selection-ui/direct-manipulation-handles.png`, `/tmp/thumbnailmaker-wysiwyg-selection-ui/premium-single-overlay-chrome.png`, and `/tmp/thumbnailmaker-wysiwyg-selection-ui/small-preview-panel.png`.
- `claude -p 'In /Users/williamjiamin/Documents/ThumbnailMaker 2, review the SwiftUI editor code for the next narrow professional-editor milestone: add an explicit layer-selection strip/list...'` was attempted for the layer-selection milestone, but returned no usable output and was interrupted after hanging.
- After layer-selection changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerTests -derivedDataPath /tmp/ThumbnailMaker-LayerSelection-DD CODE_SIGNING_ALLOWED=NO` succeeded with 31 tests.
- After layer-selection changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'platform=iOS Simulator,id=CBF3417F-2091-417D-BC07-BD7B27B0E70B' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testSmallPreviewAppearsAfterEnteringOverlayText -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumCanvasShowsSingleOverlayChromeByDefault -derivedDataPath /tmp/ThumbnailMaker-LayerSelection-DD CODE_SIGNING_ALLOWED=NO` succeeded. The final result bundle reported 2 tests, status `succeeded`, and no test warning summaries after clamping preview geometry.
- After layer-selection changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-LayerSelection-CI-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 Pro layer-selection screenshots reviewed: `/tmp/thumbnailmaker-layer-selection-ui/premium-layer-selection-final.png` and `/tmp/thumbnailmaker-layer-selection-ui/small-preview-panel-final.png`.
- `claude -p 'In /Users/williamjiamin/Documents/ThumbnailMaker 2, review ThumbnailMaker/Models/ThumbnailDocument.swift and tests for a narrow next milestone: add a first persistent document layer array...'` completed and recommended stable IDs, decoding old documents without layers, and keeping top-level fields as rendering source of truth for this milestone.
- After persistent document layer schema changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'id=DE7EAB9D-1C2B-44A6-874F-616361391B47' -only-testing:ThumbnailMakerTests CODE_SIGNING_ALLOWED=NO` succeeded with 33 tests.
- After persistent document layer schema changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-Layers-CI-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- Initial local layer-schema test run caught an over-permissive decoder that treated legacy `SimpleThumbnailDraft` JSON as a partial `ThumbnailDocument`; the decoder was tightened so only the new `layers` key is optional for document decoding.
- After layer visibility/lock changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'id=DE7EAB9D-1C2B-44A6-874F-616361391B47' -only-testing:ThumbnailMakerTests CODE_SIGNING_ALLOWED=NO` succeeded with 35 tests.
- After layer visibility/lock changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'id=DE7EAB9D-1C2B-44A6-874F-616361391B47' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testLayerVisibilityAndLockControlsAffectTextChrome CODE_SIGNING_ALLOWED=NO` succeeded.
- After layer visibility/lock changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-LayerControls-CI-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 layer visibility/lock screenshot reviewed: `/tmp/thumbnailmaker-layer-controls-ui/F20D6520-B0B0-41AE-A2C4-1BA855BECC8A.png`.
- `claude -p "Review the current git diff for ThumbnailMaker..."` was rerun for the layer-order milestone and allowed to complete. Claude found the important SwiftUI risk that identified `ForEach` children may not visually restack without explicit `.zIndex`, plus lower-risk background z-index normalization and test gaps; those findings were applied in this slice.
- A final `claude -p` re-review of the fixed layer-order diff found no publish-blocking correctness bugs.
- After layer-order changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'id=DE7EAB9D-1C2B-44A6-874F-616361391B47' -only-testing:ThumbnailMakerTests CODE_SIGNING_ALLOWED=NO` succeeded with 36 tests.
- After layer-order changes, `xcodebuild test -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'id=DE7EAB9D-1C2B-44A6-874F-616361391B47' -only-testing:ThumbnailMakerUITests/ThumbnailMakerUITests/testPremiumCanvasShowsSingleOverlayChromeByDefault CODE_SIGNING_ALLOWED=NO` succeeded.
- After layer-order changes, `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-LayerOrder-CI-DD CODE_SIGNING_ALLOWED=NO` succeeded.
- iPhone 16 Premium layer-order screenshot reviewed: `/tmp/thumbnailmaker-layer-order-ui-2111/610BB9D3-FED4-44F7-9301-5FE9CA8F1BF8.png`.
- `rg -n "Position Matrix|Profile Position|Text Position|Grid\\(horizontalSpacing: 8, verticalSpacing: 8|textPosition|profilePosition|verticalAlignment\\(|horizontalAlignment\\(|position\\(for row" ThumbnailMaker/Views ThumbnailMaker/Models ThumbnailMaker/ViewModels` returned no matches after removing the active 3x3 position UI.
- `rg -n "Position Matrix|Profile Position|Text Position|Grid\\(horizontalSpacing: 8, verticalSpacing: 8|textPosition|profilePosition|UnifiedPositionControlView|ProfilePositionControlView|TextPositionSelectorView|TextPositionSliderView" ThumbnailMaker/Views ThumbnailMaker/Models ThumbnailMaker/ViewModels` returned no matches after the undo/redo milestone.
- `rg -n "AIza|Krea|krea|Secrets\\.plist|api[_ -]?key" -S ThumbnailMaker .github CONFIGURATION.md docs --glob '!ThumbnailMaker/Config/Secrets.plist'` returned only documented configuration/audit references and `APIConfig` fallback handling.
- `gh run list --workflow ios-build.yml --limit 5` showed the latest self-hosted Mac mini workflow run on `origin/master` completed successfully on 2026-06-02. That run predates this pass and was used only as baseline runner evidence.
- Local CI-equivalent build initially failed inside the restricted sandbox because `actool` could not access CoreSimulator runtimes. Rerunning with CoreSimulator access succeeded: `xcodebuild build -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-Build-DD CODE_SIGNING_ALLOWED=NO`.
- Local CI-equivalent test-bundle build succeeded: `xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ThumbnailMaker-CI-BFT-DD CODE_SIGNING_ALLOWED=NO`.
- Self-hosted GitHub Actions CI / Mac mini run `27493265938` passed on branch `codex/publish-readiness-m1` for commit `440f810` in 1m51s. It completed checkout, project/scheme discovery, iOS Simulator build, and iOS Simulator `build-for-testing`.
- GitHub Actions emitted a Node.js 20 deprecation annotation for `actions/checkout@v4`; update the workflow/runner before GitHub forces Node.js 24 defaults.
- Earlier full UI test execution launched and passed the stock launch checks, but the first run was interrupted while Xcode finalized logs; the focused unit-test rerun above is the clean final test result.
- iPhone 16 Pro portrait smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-portrait.png`.
- iPad Pro 13-inch portrait smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/ipad-pro-13-portrait.png`.
- iPhone 16 Pro export-row smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-export-row.png`.
- iPad Pro 13-inch export-row smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/ipad-pro-13-export-row.png`.
- iPhone 16 Pro share-pass smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-share-pass.png`.
- iPad Pro 13-inch share-pass smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/ipad-pro-13-share-pass.png`.
- iPhone 16 Pro small-preview smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-small-preview.png`.
- iPhone 16 Pro export-size panel screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-export-size-panel.png`.
- iPhone 16 Pro creator-readiness panel screenshot reviewed: `/tmp/thumbnailmaker-readiness-ui/7FE8C464-46E8-49C2-B983-4791AC45F3C3.png`.
- iPhone 16 Pro WYSIWYG transform controls screenshot reviewed: `/tmp/thumbnailmaker-wysiwyg-ui/7CA7C750-A2E4-4D6D-9E55-50E0B4A05DA5.png`.
- iPhone 16 Pro WYSIWYG landscape raw XCTest screenshot reviewed: `/tmp/thumbnailmaker-wysiwyg-ui/9C245A7C-C76F-4D47-8367-F9B785C23590.png`.
- iPhone 16 Pro landscape smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/iphone-16-pro-landscape-normalized.png`.
- iPad Pro 13-inch landscape smoke screenshot reviewed: `/tmp/thumbnailmaker-screenshots/ipad-pro-13-landscape-normalized.png`.
- macOS and web screenshots are still open because macOS/web targets do not exist yet.

## Decisions and Risks

- Decision: keep this first pass small and reviewable; no rewrite of the editor yet.
- Decision: enable iPad target family now, defer macOS until platform services are abstracted.
- Decision: add a shared export model/service before a full document renderer so current users get platform-safe output sooner without blocking the later layer-model rewrite.
- Decision: add a narrow local JSON draft store for Simple Maker first, then move Simple and Premium drafts onto a shared versioned `ThumbnailDocument` bridge before attempting the layer editor.
- Decision: add a first local creator-readiness score now using deterministic text metrics and known-background contrast, then migrate it to the future document/layer analyzer.
- Decision: replace active 3x3 position pickers with normalized overlay transforms now, while leaving legacy alignment/profile-position fields in place only for compatibility until the future `ThumbnailDocument` migration.
- Decision: use `claude -p` for the WYSIWYG architecture review; Claude recommended normalized transforms and highlighted gesture/export parity risks.
- Decision: use `claude -p` again for the next architecture increment; Claude recommended a shared document/persistence bridge before command undo/layers because Premium draft data loss was a narrower, real user risk.
- Decision: keep `ThumbnailDocument` as a bridge schema for now, not the final layer model. It stores image bytes in JSON drafts to preserve current behavior while the future project asset store is designed.
- Decision: add document-backed value-snapshot undo/redo before command/layer history so users get a visible correction path while the layer model remains under design.
- Decision: add Layer 1 safe-zone guidance as preview-only visual metadata now; defer readiness scoring until text/image/profile layers have reliable bounds in the document model.
- Decision: add visible on-canvas flip/rotate/resize handles using the existing transform and size fields before introducing a full layer-selection model, preserving preview/export/draft parity.
- Decision: remove duplicate inspector transform/size controls now and make canvas manipulation the active placement system. The inspector remains useful for style and reset status until a full layer-properties panel exists.
- Decision: add an explicit Layers strip for the current text/profile overlays before migrating `ThumbnailDocument` to a real layer tree. This gives users a visible selection model while keeping export rendering and document persistence untouched.
- Decision: clamp editor preview dimensions during early layout passes because UI tests exposed an invalid-frame runtime warning; this is a publish-quality fix independent of the future layer model.
- Decision: add stable string layer IDs (`background`, `profile`, `text`) instead of random UUIDs because document snapshots are frequently rebuilt and undo/history dedupe depends on deterministic equality.
- Decision: keep top-level image/text/profile document fields as rendering source of truth for this milestone. The new `layers` array is persisted schema groundwork, not yet the editable renderer model.
- Decision: make hide/show and lock/unlock the first real layer behavior because it moves the editor toward professional layer workflows without destabilizing rendering. Hidden layers stay in the strip for recovery; locked layers stay visible but disable gestures and handles.
- Decision: make current text/profile ordering a z-index swap rather than a full drag-reorder list for this slice. Premium preview now applies explicit `.zIndex` from the sorted layer order because delegated review caught that stable SwiftUI `ForEach` identities may otherwise preserve old compositing depth.
- Risk: the leaked YouTube API key must be rotated outside this repo.
- Risk: current sparse checkout excludes bundled fonts for speed; full build verification still needs a full checkout.
- Risk: GitHub Actions warned that Node.js 20 actions are deprecated; the self-hosted workflow passed, but the runner/workflow should be checked for Node.js 24 compatibility before GitHub's forced default change.
- Risk: the self-hosted Mac mini runner showed intermittent outbound connectivity failures to `github.com:443` during checkout; reruns can pass, but CI reliability should be monitored.
- Risk: StoreKit gating currently grants premium access while free tries remain. This may be product-intentional, but review/UX copy should make the trial behavior explicit.
- Risk: export now uses one encoder/share/file path and has first manual small-preview plus known-limit file-size checks, but platform coverage is incomplete.
- Risk: safe-zone values are conservative creator guidance, not official platform guarantees. Keep the data in preset metadata and update it after authoritative platform docs/research.
- Risk: the safe-zone overlay is excluded from export by construction; future renderer refactors must keep visual guides out of exported image data.
- Risk: creator-readiness scoring is not image-region aware yet; contrast over imported photos, face visibility, automated safe-zone violations, and text occlusion need Vision/Core Image and layer-geometry checks.
- Risk: direct manipulation is still first-pass: visible handles, selected-overlay chrome, and the current-overlay Layers strip now exist, but there are no snap lines, alignment guides, arbitrary drag reordering, or command/layer-aware undo history. Handle gestures also need hands-on device testing for scroll conflicts, tap-to-select edge cases, and small-text occlusion.
- Risk: persistent layer records now drive visibility, lock, and first z-order behavior for current text/profile overlays, but the Layers strip and renderer still operate over existing text/profile fields. Deleting, duplicating, selecting background/image layers, and ordering arbitrary imported layers still require the `ThumbnailDocument` layer-tree migration.
- Risk: layer records can drift from top-level document fields until the renderer and editor commands make layers the source of truth; tests currently cover default/migration/order stability, not full layer editing behavior.
- Risk: document-backed undo/redo is debounced and snapshot-based, so drag gestures coalesce by timing rather than by intentional editor commands.
- Risk: undo/redo snapshots still carry embedded image data through the current JSON bridge; large projects need asset-file storage before templates and cross-platform documents scale.
- Risk: applying older snapshots may round-trip image encodings through the existing document projection; this is acceptable for the first correction path but should move to stable layer assets.
- Risk: draft autosave now covers Simple and Premium, but drafts still embed imported image data directly in JSON. That is acceptable for this first bridge, but large projects/templates need separate asset storage and document migration.
- Risk: `ThumbnailDocument` uses raw-value projections from the existing UI configuration structs rather than a true layer tree. Undo/redo command grouping, templates, arbitrary layer ordering, and web renderer fixtures still require the next model migration.
- Risk: iPhone/iPad landscape now works as a first smoke, but the editor remains a tall scrolling phone-style layout rather than a tablet-native inspector/canvas workspace.
- Risk: XCTest full-screen landscape screenshots are emitted rotated; normalized review copies are saved under `/tmp/thumbnailmaker-screenshots/*-landscape-normalized.png`.
- Risk: YouTube upload limits were verified against YouTube Help on 2026-06-13, but these limits can change and should be kept data-driven in a future preset catalog.

# ThumbnailMaker project review

Reviewed September 7, 2026; updated to prioritize app features after the user clarified the request. Scope: the available native Apple project in this workspace and its public GitHub Pages support website. Android source and other projects were not available in the identified scope.

## Verdict

I like the product direction. Layers, templates, direct manipulation, small-size previews, safe zones, brand kits, and export controls address concrete creator tasks. The small-size preview is especially well matched to thumbnails: a design can look good on the editing canvas and fail when displayed small.

The next investment should be trust and clarity. The readable source has meaningful persistence and entitlement issues. The June screenshots show a capable desktop editor and a phone interface with substantial scrolling and editing chrome. Those screenshots use test artwork and do not establish the appearance of the current store release. I would validate a more compact phone editing journey before expanding the feature set.

The biggest feature opportunity is a complete repeated-use workflow: save named projects, keep editable alternatives, reuse your own templates and brand styles, deliberately frame images, and export a series. The current source already has most basic editing primitives, so these should extend the existing model and renderer.

## Features I would build first

| Priority | Feature | Why it adds value beyond the current app |
|---|---|---|
| 1 | Named project library and portable editable files | Current readable draft APIs center on one draft per editor. Creators need to return to many designs, duplicate them safely, and move editable work between devices. |
| 2 | Saved variants and small-size comparison | Layout/style/color ideas already exist. The missing piece in the readable model is keeping multiple named editable versions and comparing/exporting them independently. |
| 3 | Nondestructive crop, fit/fill, and replacement | Object transforms, profile cropping, and face suggestions already exist. A background/image-layer crop recipe adds deliberate composition while retaining original pixels. |
| 4 | Configurable text effects | Existing text models store font/color/size/transform; configurable outlines, shadows, panels, spacing, and wrapping would give creators more control over readability. |
| 5 | Personal templates and brand collections | Built-in templates and a saved brand kit already exist. Extend them with saved layouts, replacement slots, multiple named kits, and reusable styles. |
| 6 | Multi-selection, groups, alignment, and workspace zoom | The readable layer model is flat and current snapping covers canvas center. Group editing and object alignment would reduce repetitive manual adjustment. |
| 7 | Multiple formats and export recipes | Presets, image formats, quality, destinations, and size checks already exist. Add editable format versions and a queue that reliably exports a variant/size matrix. |
| 8 | Cutout refinement and creator shapes | Automatic removal and imported stickers already exist. Add reversible mask edits and editable arrows/callouts rather than another one-click removal button. |
| 9 | Series production from title/image rows | Extend existing numbering macros into an input table with preview, validation, progress, and individual retry. |

These are proposed extensions, not an exhaustive claim that every related UI is absent. Main views and stores were partly unreadable. The loop must confirm each gap after source recovery. Source anchors include `ThumbnailDocument.swift:130` (document identity/state), `:326` (image-layer fields), `:368` (text-layer fields), and `:456` (flat layer records); `ThumbnailTemplate.swift:73` defines the image-preserving template overload.

The detailed plan contains **28 native tasks**, including **15 feature packages**, supporting reliability/accessibility/performance work, and release verification. SEO is excluded from the active loop.

## Findings, highest priority first

### P1 — Transparent images lose alpha when serialized

Evidence: [ThumbnailDocument.swift:1371](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Models/ThumbnailDocument.swift:1371>) prefers `jpegData` before PNG. The helper encodes selected images and profile images at lines 1262, 1288, and 1300. [SimpleMakerViewModel.swift:587](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/ViewModels/SimpleMakerViewModel.swift:587>) reconstructs editor state from document snapshots during history operations.

Impact: imported transparent cutouts and background-removal results can be flattened during persistence and history round trips. Repeated lossy encoding also risks fidelity degradation.

Fix: preserve immutable original asset bytes or choose an alpha-preserving encoding. Keep older documents readable. Test fully transparent and partially transparent pixels through both editors, draft save/load, templates, and repeated undo/redo. Current round-trip tests at [ThumbnailMakerTests.swift:2263](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMakerTests/ThumbnailMakerTests.swift:2263>) check image dimensions rather than alpha preservation.

Confidence: source-verified defect; native runtime reproduction was not performed. Backlog: APP-01.

### P1 — A stale premium cache survives an empty entitlement check

Evidence: startup loads cached purchase identifiers at [PurchaseManager.swift:60](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Models/PurchaseManager.swift:60>). Silent verification updates the set only when it finds at least one entitlement at [PurchaseManager.swift:493](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Models/PurchaseManager.swift:493>). Access checks refresh only when the set is already empty at [PurchaseManager.swift:255](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Models/PurchaseManager.swift:255>).

Impact: cached access can persist after startup verification finds no current purchases. The cache and authoritative purchase state can disagree.

Fix: reconcile the complete verified set, including an empty result, in memory and storage. Define loading/offline/error states explicitly, filter recognized product IDs, and test revocation, restore-empty, valid offline access, purchase cancellation/pending, and successful purchase. Do not equate an unavailable verification with a completed authoritative empty result without examining StoreKit behavior.

Confidence: source-verified defect; no live purchase or refund was attempted. Backlog: APP-02.

### P2 — Draft failures are invisible

Evidence: [SimpleMakerViewModel.swift:508](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/ViewModels/SimpleMakerViewModel.swift:508>) catches write failures and only prints them; restore failures are handled similarly at line 503.

Impact: when a write fails, users can continue editing without knowing their latest work is unsaved. This review did not observe an actual disk-write failure.

Fix: publish save state, present a recoverable error and retry, retain the last good draft, and exercise a persistence-enabled save/relaunch journey with injected failures. Read the actual store implementation before changing its storage guarantees. Backlog: APP-03.

### P2 — Readiness scoring ignores added content layers

Evidence: [ThumbnailReadinessAnalyzer.swift:63](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Models/ThumbnailReadinessAnalyzer.swift:63>) inspects only the original overlay text, and line 79 checks only the original selected image. Its protocol at lines 10–18 does not expose added image/text layers.

Impact: a complete design made with added content layers can receive missing-image and missing-title warnings and lose 30 points. The analyzer also skips contrast over background images at line 145; a high score therefore does not prove text is readable over a photograph.

Fix: analyze resolved visible layers and rendered text bounds. Distinguish checked properties from unmeasured ones and avoid implying that a heuristic score predicts clicks. Backlog: APP-06.

### P2 — Failed imports silently do nothing

Evidence: [SimpleMakerViewModel.swift:359](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/ViewModels/SimpleMakerViewModel.swift:359>) and the sticker-loading path through line 393 suppress transfer or decode errors with `try?` and nil returns.

Impact: failed photo retrieval or invalid image data can leave a user without an explanation or recovery path.

Fix: show importing and recoverable failure states, distinguish cancellation, preserve the current canvas, and test unavailable cloud photos and invalid data. Backlog: APP-04.

### P2 — Export preset selection lacks accessibility state

Evidence: [ExportSettingsView.swift:74](</Users/williamjiamin/Documents/ThumbnailMaker 2/ThumbnailMaker/Views/Components/ExportSettingsView.swift:74>) renders preset selection through a checkmark hidden from accessibility without adding a selected trait/value to the button. Format rows at lines 173–175 provide those semantics.

Impact: VoiceOver users cannot reliably identify the current preset from its selection state.

Fix: add the selected trait/value, verify announcements before and after changes, and test the full import-to-export task with VoiceOver and keyboard. Backlog: APP-07.

## Investigations and design opportunities

These are follow-up work, not additional runtime-confirmed defects:

- **Stale asynchronous results:** inspect background-processing cancellation and revision protection around SimpleMakerViewModel lines 786–795. Several controlling views were unreadable, so the review cannot determine whether UI blocking already prevents the race.
- **Image processing cost:** main-actor snapshots may repeatedly encode large images. Profile 12 MP assets, typing, transforms, save latency, and peak memory before selecting a refactor.
- **Phone editing density:** historical screenshots and layer-card sizing suggest unnecessary scrolling. Validate a compact layer list and selected-layer inspector on current devices, keeping accessibility actions intact.
- **Testing quality:** substantial unit/UI coverage exists, including manipulation, layers, export, undo, and accessibility audits. Existing tests often disable draft persistence, and some accessibility exclusions are broad. Tighten the evidence around the actual save/relaunch and creation-to-export journeys.
- **Creator differentiation:** guided first export, a small excellent template set, and editable variants with side-by-side small previews are stronger candidates than unrelated design features.

## Secondary website work already completed

Before the feature clarification, the existing support website received a small update: descriptions, canonical and text Open Graph metadata, a two-page sitemap, shared responsive styling, semantic landmarks, skip links, and return navigation. All original policy headings and paragraphs were preserved byte-for-byte.

The exact deployment and validation records are in `DEPLOYMENT.json` and `website-validation.json`. The active feature loop does not select any further website work. Future product demonstrations and verified download links can be added after the native features are ready; see `OPTIONAL_WEBSITE_PLAN.md`.

## What shipped and what did not

Shipped to the existing public GitHub Pages site: homepage metadata and readable support layout; privacy-page metadata, shared styling, and navigation; sitemap. All original privacy-policy headings and paragraphs were preserved byte-for-byte. No native application source was changed or shipped.

Prepared locally: a feature-first implementation plan, 28-task native dependency backlog, a structured iteration prompt/schema, and a resumable Python runner. The runner was validated with mocked workers and an actual dry run against this backlog. It has not started paid/model work or the improvement program.

## Verification and limits

- Static checks passed for unique titles/descriptions, canonical and Open Graph URLs, one H1/main per page, internal links/fragments, valid sitemap XML, and unchanged privacy text.
- An independent static review found no publication blocker.
- GitHub Pages built the exact release revision; production HTML, CSS, and sitemap were checked against the validated source.
- Live desktop and 390-pixel phone layouts were inspected. Both pages had no horizontal overflow at phone width; navigation worked, and Tab focused the skip link. This is a focused smoke check, not a complete WCAG conformance audit.
- The native review used readable services, models, the simple editor view model, and unit/UI test source. Several required files were marked `dataless`, including parts of configuration, stores, the premium view model, and main views. Bounded reads timed out.
- Xcode 26.2 is installed, but a complete native build/test run was not established. Historical June screenshots and result files are not fresh release evidence.
- Android implementation, current store listings, Search Console, actual conversion metrics, and live native purchase behavior were not verified.

The implementation plan records these limitations as prerequisites and acceptance checks so a later loop can resolve them instead of assuming them away.

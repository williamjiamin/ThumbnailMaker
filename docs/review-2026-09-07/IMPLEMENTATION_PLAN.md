# ThumbnailMaker: feature-first implementation plan

Updated September 7, 2026 after the user clarified that **app features are the main objective**. SEO is secondary. The active `backlog.json` now contains **28 native feature, reliability, and release-verification tasks**; it contains no SEO or marketing work. Website follow-up is separately documented in `OPTIONAL_WEBSITE_PLAN.md`.

## Product direction

Turn ThumbnailMaker from a capable single-design editor into a dependable workspace for repeated creator work: keep projects, reuse a visual identity, make several editable options, compare them at thumbnail size, and export the right versions reliably.

I like the focused creator workflow, particularly the small-size previews and direct manipulation. I would invest in the full repeated-use journey before broadening into a general design suite. The first compelling feature release should deliver **named projects, saved variants, reversible image composition, configurable text effects, personal templates, and editable project files**.

Unlimited implementation capacity should mean deeper polish, edge-case coverage, good migration, and useful iterations. It should not mean rebuilding capabilities already present or adding every conceivable feature.

## What already exists

Readable source and test definitions establish these foundations. Tests were inspected, not rerun, and source availability is incomplete.

| Existing foundation | Extend it with |
|---|---|
| Image, sticker, text, rectangle, and ellipse layers; duplicate/delete/reorder; visibility and locking | Multi-selection, grouping, stronger alignment, arrows and callouts |
| Drag, resize, rotate, horizontal flip, and canvas-center snapping | Object-edge snapping, nondestructive crop/fit/fill, workspace zoom/pan |
| Undo/redo and simple/premium drafts | Named project library, saved variants, recovery, portable projects |
| Five built-in templates and local layout/style/color/title ideas | Personal templates and persistent editable versions with comparison |
| Brand palette, fonts, logo data, saving and application | Multiple named kits, reusable text styles, selective application |
| Automatic background removal, suggested face crop, circular-profile zoom/pan | Editable masks, restore/erase refinement, background/image-layer crop recipes |
| Presets, custom dimensions, PNG/JPEG and conditional WebP, Photos/share/Files export, size checks | Variant/size queues, reusable recipes, bounded file-size fitting, structured series production |
| Small previews, safe zones, readiness suggestions | Composition-aware findings across all visible layers and honest unmeasured states |

Do not propose these existing foundations as new features. After restoring a complete source checkout, verify every proposed gap against the actual current UI before implementing it. Lack of a feature in the readable schema is evidence for investigation, not proof of an exhaustive UI audit.

## Source and release boundaries

The native project is `/Users/williamjiamin/Documents/ThumbnailMaker 2`. Its current local branch is `codex/publish-readiness-m1`, and some required source plus the Git index are iCloud placeholders. Xcode 26.2 is installed, but this review did not establish a fresh complete native build.

The GitHub remote `williamjiamin/ThumbnailMaker` currently exposes only `gh-pages`. Its default branch is the support website, **not a substitute for native source**. Preserve the existing native checkout and recover matching source before modifying its Git metadata or creating a release branch. Avoid overwriting local user changes.

The `website/` directory is an independent nested checkout serving `https://williamjiamin.github.io/ThumbnailMaker/`. A small SEO/readability update was already deployed before the user's clarification. Its evidence is in `DEPLOYMENT.json`. No further website work is scheduled by the feature loop.

The native loop may implement features and prepare validated native release candidates. App Store/Google Play submission is outside this website-deployment/review task. Android source was not located; the public support policy's Android reference does not establish feature parity or authorize inventing an Android implementation.

## Recommended delivery sequence

| Milestone | Scope | User-visible result |
|---|---|---|
| 0 — reliable baseline | SRC-01, APP-01/02/03/05, REL-01 | Source builds; images retain alpha; saves and purchases have trustworthy state |
| 1 — return to your work | FEATURE-01, FEATURE-06 | Named projects and portable editable files |
| 2 — create better options | FEATURE-03, FEATURE-04, FEATURE-02 | Reversible framing, editable text effects, saved versions and comparison |
| 3 — reuse a visual style | FEATURE-05, FEATURE-08 | Personal templates and reusable brand collections |
| 4 — precise composition | FEATURE-07, FEATURE-11, FEATURE-12 | Grouping/alignment, zoom/pan, cutout refinement, arrows and callouts |
| 5 — produce a series | FEATURE-09, FEATURE-10, FEATURE-15 | Multiple formats, export queues, title/image-driven batches |
| 6 — polish and extend | APP-04/06/07/08/09, FEATURE-13/14, REL-02/03 | Clear errors, accessible compact editing, guidance, reversible looks, integrated release evidence |

This table describes product milestones; `backlog.json` contains the exact dependency graph. Independent work may proceed in parallel, but source changes must have one owner per overlapping area. Reliability, accessibility, and performance checks accompany each feature rather than waiting for the final milestone.

## First resolve the issues that would undermine new features

**APP-01 — Preserve image alpha and fidelity.** `ThumbnailDocument.swift:1371` prefers JPEG when serializing selected/profile images. Preserve original bytes or use alpha-aware encoding. Verify transparent and partially transparent pixels through draft save/load, templates, both editors, and repeated history changes. New projects and variants must not multiply lossy copies of the same image.

**APP-02 — Reconcile verified entitlements.** Startup loads cached purchases, while silent verification at `PurchaseManager.swift:493` replaces them only for a nonempty result. Reconcile the full verified set, including empty results, and model loading/offline/revoked/error states explicitly. Test stale cache, restore-empty, pending/cancelled purchase, successful purchase, and valid offline behavior. Do not confuse inability to verify with an authoritative empty result.

**APP-03 — Visible, recoverable saves.** The simple view model currently prints save/restore errors only. Add saving/saved/failed state, retry, atomic/recoverable persistence after inspecting the actual store, and a real save/relaunch UI journey. Preserve the last good draft when storage fails.

**APP-05 — Reject stale asynchronous results.** Verify current UI protections, then use cancellation/revision checks where necessary. An old crop, cutout, import, or network result must not overwrite a newer image or undo state. Treat this as a risk to reproduce, not an already demonstrated race.

## Feature specifications

### 1. Named project library — FEATURE-01

Introduce stable project identity, a name, created/updated dates, a preview, and document/asset references. The library supports create, recent browsing, search, rename, duplicate, reopen, and recoverable trash. Migrate existing simple/premium drafts once. Keep automatic saving while making its state visible.

Project switching must finish or visibly fail the pending save. Duplicates must have new identities while safely sharing immutable assets; editing one must not change another. Generate preview thumbnails away from the main thread. A corrupt project should be isolated rather than preventing the library from opening.

Acceptance: ten independent projects survive restart; old drafts migrate once; rename/search/duplicate/switch work; deletion can be recovered; failed saving protects the previous version and prevents silent loss.

### 2. Editable project files — FEATURE-06

Export a versioned project package containing a manifest, document, assets, and preview. Import as an editable copy through the supported platform file flow. Keep this clearly separate from flattened PNG/JPEG export.

Inspect the existing file-document implementation first. Validate versions, paths, asset counts/sizes, malformed data, and missing assets. Never silently load an unsupported future document and overwrite it after dropping unknown fields. Handle ID/name collisions as a new copy.

Acceptance: a package imports into a fresh app data directory with equivalent editable layers and styling; no source-device path is required; invalid/future-version packages fail clearly without altering the current project.

### 3. Reversible image framing — FEATURE-03

Build fit/fill, pan/zoom within a frame, a crop rectangle, focal-point placement, reset, and image replacement that keeps the frame. Existing object transforms and circular-profile cropping remain useful, but they do not replace a persisted nondestructive recipe for the background and image layers.

Store original asset references plus normalized crop/placement values. Use exactly the same geometry for preview and export. One completed gesture is one undo action. Changing an aspect ratio should retain the intended focal point or show an explicit crop preview.

Acceptance: portrait, landscape, rotated, and transparent inputs survive crop/reset/save/load without losing original pixels; replacing an image preserves framing and unrelated styling; exported composition matches the preview.

### 4. Configurable text styles — FEATURE-04

Add a shared serializable style for outlines, shadows, background panels, padding, line/letter spacing, alignment, and text-box width. Offer a few useful presets with a clear reset. Apply the same model to original overlay text and added text layers.

Current models contain font/color/size/transform and some effects are hardcoded in rendering. Preserve the previous appearance when migrating old documents. Implement a shared renderer before adding multiple independent effect code paths.

Acceptance: effects and wrapping survive history/projects/templates; preview/export match at different scales and rotations; Latin, CJK, emoji, and supported fallback fonts avoid clipping; turning effects off restores plain text; controls work with large text and VoiceOver.

### 5. Saved variants and comparison — FEATURE-02

Extend existing local ideas with **Keep as variant**. Save named A/B/C versions, duplicate them, select a preferred version, and compare two or three at identical small-display sizes. Each version keeps its own document state and undo history while sharing immutable assets safely.

A preferred version is a user choice, not a measured winner. Do not imply the app has performed a viewer experiment. Export names must identify the selected version.

Acceptance: editing B leaves A/C untouched; names and selected version survive relaunch; comparisons use the right rendered revisions; history stays inside the edited variant; export produces the intended version.

### 6. Personal templates — FEATURE-05

Extend the existing template model/gallery with Save as Template, names, categories/favorites, previews, duplicate/update, and recoverable deletion. Define image/title replacement slots and intentionally retained brand assets. Preserve the five built-ins.

Make the distinction between replacing a composition and applying a style clear. Template application creates fresh layer identities and one undoable change. Later template edits must not mutate designs already created from it.

Acceptance: save a layout, reopen it, replace its image/title, and export without rebuilding the design; unrelated media is not copied into new projects; missing assets are explained; old templates and existing projects remain intact.

### 7. Precision workspace — FEATURE-07

Add a selection set and explicit groups to the flat layer model. Support group/ungroup, group transforms, align edges/centers, equal spacing, and snapping to other visible objects. Keep current center snapping and provide a toggle/modifier override. Exclude locked/hidden layers appropriately.

Add workspace zoom/pan with fit-canvas/reset, separate from object transforms. Zooming the workspace must never change document coordinates or export output. Provide numeric and accessible alternatives to gestures.

Acceptance: group changes preserve relative geometry and ordering; ungrouping preserves appearance; locked content remains fixed; undo treats one gesture as one action; keyboard/VoiceOver cover the controls; workspace navigation does not alter output pixels.

### 8. Brand collections — FEATURE-08

The app already stores palettes, fonts, and logo data. Extend that foundation to multiple named channel kits and reusable text/shape styles. Support duplicate/rename/switch and an obvious active kit.

Offer Apply to selection and an explicit whole-project action, ideally with a preview and one-step undo. Projects retain their own resolved styling so removing a kit cannot break an older design. Verify whether multiple kits already exist after hydration before adding another collection.

Acceptance: at least three named kits persist independently; selected-layer application changes only the intended content; later kit edits/deletion do not damage existing projects.

### 9. Multiple formats — FEATURE-09

Create editable landscape, square, and vertical versions within a project. Build on existing aspect ratios/presets. Preserve source content while allowing independent crop, text placement, and manual overrides per size. If text/image replacements are linked, make that relationship visible and reversible.

Start with deliberate reflow rules and a preview; do not claim perfect automatic layout. Preserve focal subjects and flag unresolved clipping. Check current platform requirements before naming branded presets.

Acceptance: one design produces three independently editable sizes; the original remains unchanged; manual adjustments are retained; each preview and export uses the correct geometry and safe areas.

### 10. Export queue and recipes — FEATURE-10

Reuse existing exporters and numbering macros after inspecting the premium executor. Let users choose variants, sizes, formats, destination, names, and overwrite behavior, then show the exact proposed output list. Add progress, cancellation, partial-failure recovery, and retry of failed items.

Provide a bounded fit-under-file-size option with a stated quality floor. If the target cannot be met, explain that without secretly changing dimensions or format. Persist useful export recipes.

Acceptance: a three-variant by three-size matrix yields correct pixels/count/names; cancellation preserves successful files; retries target only failures; impossible byte targets are explicit; memory and responsiveness stay within measured budgets.

### 11. Cutout refinement — FEATURE-11

Extend automatic removal with a separately stored editable mask, erase/restore brush, size/softness, before/after, zoom/pan, feathering, reset, and undo. Optional subject outlines/shadows must be persisted and rendered consistently.

Keep the original image and mask separate. Reusing a refined subject should not couple two projects' future edits. Profile high-resolution masks before deciding on tile/cache mechanics.

Acceptance: partially transparent edges survive reopen/export; restore recovers original pixels; mask edits undo cleanly; large-image editing remains responsive; an old processing result cannot replace a newer selection.

### 12. Creator shapes and callouts — FEATURE-12

Extend rectangle/ellipse shapes with a small set of editable arrows, badges, and callouts. Keep fill, stroke, geometry, and arrowhead parameters editable and crisp at export sizes. Reuse ordinary layer selection/history behavior.

Acceptance: shapes survive duplicate/transform/persistence/history; preview/export agree; existing shape documents remain compatible; insertion and editing remain usable on compact phones.

### 13. First-export guidance — FEATURE-13

Use actual features in a short goal → template → image → text → small preview → export journey. Guidance should be skippable, contextual, and recoverable; it must never reset an existing project.

Observe representative creators before expanding onboarding. Record task completion, elapsed time, and actual obstacles. Start with a local study rather than automatically adding a tracking service.

Acceptance: the guided and direct-editing journeys both work across supported device classes; progress survives interruption; the change addresses documented friction.

### 14. Reversible photo looks — FEATURE-14

Validate demand for essential brightness/contrast/saturation/blur/vignette controls. Store an adjustment recipe against original assets, with before/after, reset, and named looks. Avoid expanding into a full photo editor without evidence.

Acceptance: resets recover original pixels; preview/export color and alpha agree on fixtures; presets persist; processing meets the measured device budgets.

### 15. Series production — FEATURE-15

Extend existing numbering macros to a local table of titles, images, episode numbers, and template slots. Add a documented CSV import, per-row validation/preview, and reuse the export queue's progress/cancel/retry behavior. Keep the source template immutable during rendering.

Acceptance: a ten-row fixture yields deterministic expected content/files; malformed rows are isolated; valid rows remain usable; retry processes only unfinished/failed rows.

## Cross-cutting quality requirements

**Document and asset architecture:** centralize immutable asset storage, stable project/variant identity, and explicit version migration. Inspect the existing store before choosing files versus a database. Prefer the smallest architecture that meets recovery and performance needs. Never rewrite the whole editor simply because a new feature would be easier in a fresh framework.

**Preview/export parity:** all new crop, typography, group, mask, and adjustment behavior must share rendering semantics between canvas, small preview, and export. Use representative pixel/geometry fixtures; do not rely solely on screenshots of controls.

**History:** one completed user action should undo predictably. Variant/project selection must not apply history from a different document. Long asynchronous operations must validate their originating document revision.

**Accessibility and phone usability:** retain keyboard/VoiceOver equivalents for gestures, meaningful selected states, large text, contrast, and compact layouts. The current export-preset selection semantics and broad audit exclusions deserve correction. Design around a complete creation-to-export task, not just isolated buttons.

**Performance:** profile 12 MP images, multiple layers, variant switching, saving, and export queues. Record interaction/save latency and peak memory on named devices before setting budgets. Avoid encoding unchanged images on every text/transform edit. Keep expensive previews and processing off the main actor where practical.

**Honest assistance:** update readiness checks to consume all visible layers and expose unmeasured properties. A heuristic score is not a predicted click-through rate. Deliberate image-only compositions should not be treated as categorically invalid.

## How to run the long-running loop

The runner requires Python 3.10+ and an installed, authenticated Codex CLI. It inherits the user's configured model. `codex exec`, stdin prompts, and JSON result-schema flags were verified against the installed CLI. [Official non-interactive execution documentation](https://learn.chatgpt.com/docs/non-interactive-mode)

Read-only preflight:

```sh
python3 '/Users/williamjiamin/Documents/ThumbnailMaker 2/docs/review-2026-09-07/run-loop.py' \
  --project '/Users/williamjiamin/Documents/ThumbnailMaker 2' \
  --dry-run
```

Start a bounded run:

```sh
python3 '/Users/williamjiamin/Documents/ThumbnailMaker 2/docs/review-2026-09-07/run-loop.py' \
  --project '/Users/williamjiamin/Documents/ThumbnailMaker 2' \
  --max-iterations 20 \
  --max-hours 8 \
  --iteration-timeout 3600 \
  --max-attempts 3
```

Leave the terminal open. Ctrl-C stops the worker. Run the same command again to resume. Increase the limits deliberately if desired; they bound time/attempts, not token cost. A program with 28 substantive tasks will normally take more than one run. Split a large task into smaller dependency-linked slices if three attempts are insufficient, preserving its acceptance intent.

The runner selects the highest-priority ready task, one at a time. It uses atomic checkpoints, a lock against concurrent loops, per-task attempt limits, a no-progress cutoff, and a wall-clock limit. It continues independent tasks when a dependency blocks. Because all native work needs a complete source baseline, an unresolved SRC-01 may correctly leave the entire feature program blocked; do not use the website as a substitute task to hide that limitation.

Workers run with `workspace-write` and `-a never`, preserving sandbox protections. If source recovery, builds, Git operations, or platform tools are unavailable, they must checkpoint the exact limitation instead of bypassing restrictions or pretending success. The runner does not launch another unrestricted agent.

State lives in `backlog.json`, `loop-state/`, and each task's `loop` metadata. Exit 0 means all tasks complete or dry-run succeeded; 2 means unfinished; 1 means configuration failure; 130 means interruption. To retry a resolved blocked item, stop the loop, set that item's status to `todo`, and remove only its `loop` metadata. Preserve old result files.

The runner requires evidence for each acceptance criterion before recording `done`. This validates the worker's response, not the underlying truth: inspect linked logs, diffs, fixtures, and result bundles at milestones. Raw CLI stdout/stderr are discarded; workers should save focused test evidence without credentials. Mocked runner scenarios and the actual backlog dry run passed; **the feature loop has not been started**.

## Iteration and release contract

1. Read the assigned task, current source, project instructions, and prior checkpoint. Preserve user changes; use a `codex/` branch for new native work once the repository is readable.
2. Verify that the proposed feature is not already implemented. Reproduce any defect and establish the relevant baseline. Missing evidence is not a pass.
3. Implement one complete feature slice, including its persistent model, controls, renderer/export behavior, undo, and error handling where relevant.
4. Run focused meaningful tests and a real user journey. For persistent features, check save/relaunch and legacy migration. For visual features, compare actual preview/output geometry or pixels.
5. Review the final diff and save exact evidence. Do not weaken acceptance criteria to declare completion. Return `completed`, `continue`, or `blocked` with the next concrete action.
6. At REL-01/REL-02 and the end-of-backlog REL-03, run the established broader gates on the exact candidate, across supported Apple destinations. Record revision, toolchain, devices, test bundles, current screenshots, and limitations. Prepare release artifacts; do not submit an unrequested store release.
7. Stop when the scoped backlog is complete, a limit is reached, or external inputs prevent further work. Report that state honestly. Do not invent additional features to keep the loop busy.

REL-03 depends on every preceding task and reruns the integrated release matrix after the last feature change. Earlier successful checks do not certify a later shared-renderer, masking, or batch-export revision.

The first success criterion is a creator who can make a design, return to it later, produce alternatives, and export the chosen result without losing work. That is the foundation for every later feature.

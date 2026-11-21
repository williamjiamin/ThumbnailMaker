# App Store — "What's New" draft for 1.3.0

Draft only. Trim to taste; App Store Connect allows 4,000 characters. Every line below maps to a
feature that is implemented and unit-tested in this build (see the feature map at the bottom).
Nothing here claims predicted click-through; YouTube judges A/B tests on watch time.

---

**The biggest update yet: a real design workspace for creators.**

**Projects**
• A project library: name, search, duplicate, rename and restore designs from Trash. Your existing draft moves in automatically.
• Export and import editable .thumbproj project files to move work between devices.

**Test your packaging**
• Make up to three variants (A/B/C) of one design, each with its own undo history. Built for YouTube's Test & Compare.
• Compare variants side by side at real feed size, and mark your pick.
• Export every variant in every size in one queue, with predictable file names.

**Design tools**
• Non-destructive crop: Fit, Fill or Stretch, with drag-and-zoom framing. Your original photo is never cut.
• Text styles: outlines, shadows, background panels, spacing and alignment, with one-tap presets.
• Arrows, badges and callouts: pointers, curved arrows, "NEW" badges, bursts and speech bubbles, all fully editable.
• Multi-select, group, align and distribute layers.
• Refine cutouts with erase/restore brushes. Background removal no longer overwrites your photo.
• Reversible photo adjustments and reusable looks.

**Work faster**
• Save your own templates, with slots for the photo and title.
• Multiple brand kits with reusable layer styles.
• Alternate sizes (landscape, square, vertical) from one design.
• Make a series: fill a table (or import a CSV) of titles and photos and render them all from one template.
• A short, skippable guide to your first export.

**Fixes**
• All 20 fonts are now bundled. Several fonts, including every free font, previously fell back to the system font.
• Transparent cutouts keep their transparency through saving, undo and templates.
• Save failures are now shown with a Retry button instead of failing silently.
• Clearer photo-import errors; a slow import can no longer overwrite a newer one.
• Faster editing with large photos, and much lower memory use for undo history.
• Accessibility and larger-text improvements throughout.

---

## Feature map (for review, not for the store)

| Line | Backlog | Main files |
|---|---|---|
| Project library | FEATURE-01 | ThumbnailProjectLibrary, ProjectLibraryView |
| .thumbproj files | FEATURE-06 | ThumbnailProjectPackage{Reader,Writer}, ThumbnailProjectImporter |
| Variants A/B/C + compare | FEATURE-02 | ThumbnailVariantWorkspace, ThumbnailVariantCompareView |
| Export queue | FEATURE-10 | export queue + ThumbnailVariantExportPlan |
| Non-destructive crop | FEATURE-03 | ThumbnailImageFrameRecipe, ThumbnailImageGeometry |
| Text styles | FEATURE-04 | ThumbnailTextStyle, StyledThumbnailTextView |
| Arrows/badges/callouts | FEATURE-12 | ThumbnailShapeRecipe, ThumbnailCalloutPreset |
| Group/align/distribute | FEATURE-07 | ThumbnailLayerGroup, ArrangePanelView |
| Cutout refinement | FEATURE-11 | ThumbnailCutoutMask, CutoutRefinementView |
| Adjustments | FEATURE-14 | AdjustmentsPanelView |
| Personal templates | FEATURE-05 | PersonalTemplateLibrary |
| Brand kits | FEATURE-08 | BrandKitLibrary |
| Alternate sizes | FEATURE-09 | ThumbnailFormatSection |
| Series | FEATURE-15 | Series sheet |
| First-export guide | FEATURE-13 | FirstExportGuide* |
| Fonts | P0-1 | FontManager, FontRegistrationTests |
| Transparency / save / import | APP-01…06 | see SESSION_SUMMARY.md |
| Performance | APP-09 | shared encoded image buffers, 256 MB undo cap |
| Accessibility | APP-07/08 | wave 5 |

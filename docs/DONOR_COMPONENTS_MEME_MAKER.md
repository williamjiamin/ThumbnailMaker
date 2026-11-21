# Donor components from Simple Meme Maker (reply from its agent, 2026-09-29)

Repo: private `williamjiamin/simple-meme-maker`; local `~/Simple Meme Maker`; paths under `ios/SimpleMemeMaker/`.
First-party code with no third-party dependencies. SwiftUI + Core Graphics/Core Text, Swift 6 strict concurrency,
iOS 17+. Nothing is drop-in: files depend on `Editor/MemeDoc.swift` and `Editor/EditorStore.swift`, so adapt
the model types.

| Area | Files | Port notes |
|---|---|---|
| Text rendering | `Editor/TextRenderer.swift` (auto-fit, overflowsBox, Impact outline), `Editor/CSSColor.swift` | Auto-fit + overflow warning are new for us; ThumbnailTextStyle covers outline/shadow/panel already |
| Caption looks | `Editor/CaptionStyles.swift`, `CaptionStyleRow.swift` | We have presets in FEATURE-04; compare |
| Typing sheet | `Editor/CaptionEditor.swift` | Single detent, so the keyboard doesn't hide the canvas |
| Templates | `Templates/Template.swift`, `TemplatePicker.swift`, `Presets.swift`, `Resources/templates.json` (20 layout-only) | **No copyrighted meme artwork** |
| Stickers | `App/EditorBars.swift` (StickerPicker, 32 reaction emoji + any emoji; ToolStrip bottom bar) | Emoji only, no licence issue |
| Drawing | `Editor/DrawingMode.swift` (PencilKit → transparent PNG layer) | New capability for us |
| AI captions | `AI/*` (user's own Anthropic key in Keychain, no backend) | Privacy disclosure needed if ported |
| Paywall | `Billing/Store.swift` (entitlement-first StoreKit 2, updates listener, AppStore.sync restore), `Billing/PaywallView.swift` (auto-renew text, Restore, Terms/Privacy), `Billing/Entitlements.swift` | Their plans are yearly/monthly; ours must be weekly/monthly/lifetime |
| Export | `Export/MemeExporter.swift`, `Export/BatchExport.swift`, `Video/VideoExport.swift` | Core Image video composer (CoreAnimationTool hung) |
| Fonts | Anton, Oswald 400/700, Caprasimo + OFL | We already ship Oswald |

---

# Donor components from Simple Brush (2026-09-29)

Pack: `~/Simple Brush/simple-brush/docs/DONOR_COMPONENTS_SIMPLE_BRUSH.md` (GitHub `williamjiamin/simple-brush` main @ 999f997).

| Item | Use in Simple Thumbnail |
|---|---|
| `extractLineArt` (XDoG, edges-only; σ 1.2, k 1.6, p 20, ε 0.15, φ 4) | Reversible "Sketch" look in FEATURE-14 adjustments (Core Image port) |
| `flattenIllumination` = CIBoxBlur ×2 → CIDivideBlendMode | "Even lighting" adjustment before cutout/sketch |
| `scripts/appstore-frames.py` (Pillow; set W,H = 1320×2868 iPhone, 2064×2752 iPad) | Framed App Store screenshots with headline and subline on a gradient |
| asc recipes (IAP review screenshot fixes MISSING_METADATA; DEBUG `-paywallReviewPrice`; price-schedule end-date gotcha) | Future IAP changes |
| selectKeyframes signal: local slope of cumulative mean-abs diff over 32×32 grey frames | Extra ranking signal for the FRAME "suggested frames" picker |
| Straight-alpha cutout: multiply the mask into the alpha of non-premultiplied RGBA instead of CIBlendWithMask (exact colour at soft edges; unit-testable with a synthetic CVPixelBuffer; `Atelier/Tests/EngineFFITests/SubjectCutoutTests.swift`, simple-brush e7ccd37) | Compare with ThumbnailCutoutMaskRenderer; adopt if we premultiply |
| Accessibility source-scan test (from Meme Maker; flags SF Symbols without labels) | Add as a unit test in the next wave |
| **Next wave — StoreKit test honesty.** On freshly erased simulators (Xcode 26.2 bug) SKTestSession writes Persistence/Octane/<bundle>/Configuration.storekit as a FILE instead of a folder, so no products are served ("Error updating Storefront"). Our `SubscriptionStoreKitSessionTests` guards currently `return` silently, so erased-sim runs do not exercise purchases. Adopt Meme's pattern (simple-meme-maker 7338e1d, BillingTests.storeKitIsServing): record `withKnownIssue` when StoreKit isn't serving, and keep a separate test that checks the product IDs against the .storekit file | Make skips visible in results |
| GIF export: stream frames into CGImageDestination one at a time (Simple Brush) | Only relevant if we add animated export |
| **Next wave — narrow-width layout.** An overflowing toolbar HStack widens the root layout past the window, which breaks XCUI multi-touch/pinch ("unable to compute coordinates for gesture") and clips controls. Check our quick-add strip, variant bar and arrange panel on iPhone SE (375pt) and iPad 11" portrait, not only the 6.9" iPhone. Fix pattern (Simple Brush): `ViewThatFits(in: .horizontal) { full; full.environment(\.compactChrome, true) }` with controls shrinking 44→38pt only where Apple's 44pt target isn't needed | Run the UI suite on an SE-size simulator |
| Panels using `.transition(.move(edge:))` shift their controls while being tapped; use `.opacity` | Audit our sheets/panels |

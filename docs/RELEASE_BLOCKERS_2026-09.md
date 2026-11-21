# ThumbnailMaker — release blockers found 2026-09-09

Found while auditing publish-readiness against the 2026 App Store requirements in
`docs/COMPETITOR_RESEARCH_2026-09.md` §5. These are **not** in the 28-task backlog —
nobody had looked at the bundle contents before.

Severity key: **P0** = must fix before submitting · **P1** = should fix before submitting ·
**P2** = fix soon after.

---

## P0-1 — The font picker offers 20 fonts; only 5 are bundled

**This is the most serious defect currently in the app.**

`ThumbnailMaker/Models/FontManager.swift` defines 20 cases in `CustomFont`, and
`ThumbnailMaker/Info.plist` lists all 20 under `UIAppFonts`. But `ThumbnailMaker/Fonts/`
contains exactly **five** `.ttf` files:

| Bundled ✅ | Declared but **missing** ❌ |
|---|---|
| Borel-Regular | GoNotoCurrent-Regular, OpenSans-Regular, Roboto-Regular, Montserrat-Regular |
| CherryBombOne-Regular | HachiMaruPop-Regular, HennyPenny-Regular, Lato-Regular, LongCang-Regular |
| DeliciousHandrawn-Regular | LXGWWenKaiMonoTC-Regular, MysteryQuest-Regular, Oswald-Regular |
| EastSeaDokdo-Regular | PixelifySans-VariableFont_wght, Poppins-Regular, YujiBoku-Regular |
| MeowScript-Regular | ZhiMangXing-Regular |

**15 of 20 fonts do not exist in the bundle.** Three consequences, each independently bad:

### 1. Every free font is missing

`CustomFont.isPremium` returns `false` for exactly four fonts:

```swift
case .goNoto, .openSans, .roboto, .montserrat:
    return false
```

All four are in the missing column. `CustomFont.basicFonts` — the set a **non-paying user
can choose from** — is therefore entirely unbundled. A free user picking any font silently
gets a system fallback. The free tier's font feature does not work at all.

### 2. Paying users get 5 of 16 promised premium fonts

The 5 fonts that *are* bundled are all `isPremium == true`. So the premium font list
advertises 16 and delivers 5. This is a paid feature that mostly does not exist —
a consumer-fairness problem as much as a bug.

### 3. The universal CJK fallback is missing

`getAttributedText(...)` falls back to `.goNoto` for any character the selected font can't
render:

```swift
attributedString[attributedIndex..<nextIndex].font = .custom(CustomFont.goNoto.rawValue, size: size)
```

`GoNotoCurrent-Regular` is not bundled, so **all CJK fallback silently resolves to the
system font**. `.goNoto` is also the font whose `supportDescription` claims "Supports all
languages and scripts" and whose `supportedScripts` is `Set(UnicodeScript.allCases)`.
Every one of those promises is currently false.

### Why nobody noticed

`FontManager.registerFonts()` swallows the failure:

```swift
guard let fontURL = Bundle.main.url(forResource: font.rawValue, withExtension: "ttf") else {
    print("Failed to find font: \(font.rawValue)")
    return          // <-- silent; nothing surfaces to the UI or to tests
}
```

15 `print` lines at launch, no assertion, no test, no user-visible signal. `.custom(name:size:)`
falls back silently when a font isn't registered, so the UI looks plausible.

### Fix — two parts, and the second one is yours

**Part A (code, safe, no downloads).** Make the font list honest: derive the picker's
contents from fonts that actually registered, and stop swallowing registration failures.
A missing font should fail loudly in debug and be absent from the picker in release, never
silently substituted. Add a test asserting every `CustomFont` case resolves to a real
bundled file — that test would have caught this on day one.

**Part B (content + licensing — needs your decision).** The 15 missing `.ttf` files have to
either be added to the bundle or removed from `CustomFont` and `UIAppFonts`. I have not
downloaded anything: which fonts ship is a product decision, and each carries a licensing
obligation (see P1-1). Tell me which way you want it and I'll implement it.

Given the trend research — minimalism, 3–5 words, legibility at 120px — shipping ~8 excellent,
properly-licensed fonts is very likely better than claiming 20 and delivering 5.

---

## P1-1 — No font licensing evidence anywhere in the repo

There is no `LICENSE`, `OFL.txt`, or attribution file for any bundled font. The five
shipped faces (Borel, Cherry Bomb One, Delicious Handrawn, East Sea Dokdo, Meow Script)
are Google Fonts families, which are typically distributed under the **SIL Open Font
License 1.1**. The OFL *requires* the licence text to be distributed with the font.

Shipping them in a paid app with no licence file is a licensing violation regardless of
App Store review. `ECONOMICAL_HANDOFF.md` already lists "asset/font licensing evidence" as
a release prerequisite; it is still outstanding.

**Fix:** add each font's `OFL.txt` alongside the `.ttf`, plus an in-app attribution screen
(Settings → Acknowledgements). Verify each family's actual licence rather than assuming OFL.

---

## P1-2 — App display name is a Guideline 4.3(b) spam risk

`INFOPLIST_KEY_CFBundleDisplayName = "Thumbnail Maker"`.

Apple **tightened Guideline 4.3(b) on spam on 2026-06-09**, specifically targeting
low-quality apps in saturated categories. The App Store already contains, verbatim:

- *Thumbnail Maker, Banner Maker*
- *Thumbnail Maker – Social Media*
- *Thumbnail Maker – YT Templates*
- *Thumbnail Maker – TubeCut*
- *Thumbnail Maker For YT Studio!*

Submitting a generic-named app called "Thumbnail Maker" into that specific cluster, right
after Apple tightened the rule aimed at it, is an avoidable rejection risk.

**Fix:** a distinctive display name. This is a branding decision, so I'm flagging rather
than choosing. Note the related rule — you may not use another developer's brand in your
app name or icon — so avoid putting "YouTube"/"YT" in the name, which is what several
competitors above are doing.

---

## P1-3 — Paywall disclosure needs an audit against the 2026 IAP rules

2026 guidance requires subscriptions and IAP to show **full pricing, renewal terms, and
cancellation information before the user pays**. `ThumbnailMaker/Views/QuotaLimitView.swift`
and the purchase flow have not been checked against this.

Competitor pricing for anchoring (from the research doc): $39.99/yr and $47.99/yr are
typical, with one $79.99 lifetime option.

**Fix:** audit the paywall copy for price, period, auto-renewal statement, cancellation
path, and links to Terms and Privacy. `Resources/terms_of_service.txt` and
`privacy_policy.txt` exist and should be surfaced from the paywall.

---

## P2-1 — Data-disclosure review for the YouTube integration

2026 rules require clear disclosure of what data is collected and how it is used,
**especially before sharing with third parties**. `Services/YouTubeService.swift` and
`Models/APIConfig.swift` make network calls. `docs/GATE16_EVIDENCE_PACKET.md` already
records a pending **YouTube API key rotation** as an external prerequisite.

**Fix:** confirm what leaves the device, that it matches `docs/APP_STORE_PRIVACY.md` and
the App Privacy answers in App Store Connect, and complete the key rotation.

---

## Status of the §5 requirement table

| Requirement | Status |
|---|---|
| iOS 26 SDK / Xcode 26+ (as of 2026-04-28) | ✅ verified — Xcode 26.2, unpinned `SDKROOT`, iOS 26.2 only installed SDK |
| Dark Mode + Dynamic Type | ⚠️ APP-07 / APP-08, unverified |
| Data disclosure, incl. third parties | ⚠️ P2-1 |
| IAP pricing / renewal / cancellation shown pre-purchase | ⚠️ P1-3 |
| Guideline 4.3(b) spam | ⚠️ P1-2 |
| No other developer's brand in name/icon | ✅ own name; keep "YouTube"/"YT" out of it |
| Font/asset licensing | ❌ P1-1 |
| Bundle actually contains what the UI offers | ❌ **P0-1** |

---

## Recommended order

1. **P0-1 Part A** — make the font list honest (code only, no external decisions). Also add
   the regression test.
2. **P1-2** and **P0-1 Part B** — both need a decision from you (app name; which fonts ship).
3. **P1-1** — licence files, once the font set is settled.
4. **P1-3**, **P2-1** — paywall and privacy audits.
5. Then Gate 4 Mac mini CI evidence on the final revision, per `docs/CI_GATES.md`.

---

## Update 2026-09-27

### P0-1 — Fonts: FIXED
All 15 missing fonts restored (20/20 bundled, 57 MB) with licences for all 20 in
`ThumbnailMaker/Fonts/Licenses/`. PostScript-name verification found 4 further mismatches that
would have rendered as the system font even with the files present:
- `GoNotoCurrent-Regular` → real name `GoNotoCurrent-Regular-Regular`
- `MysteryQuest-Regular` → `MysteryQuest`
- `PixelifySans-VariableFont_wght` → `PixelifySans-Regular`
- Montserrat's variable build defaults to **Thin**, so a static Regular (from the designer's repo) is bundled instead.
`CustomFont.postScriptName` now separates the render name from the persisted `rawValue`, so saved
documents are unaffected. `FontRegistrationTests` asserts that every case is bundled, resolves, and
is declared in `UIAppFonts`. Suite: 132 tests / 8 suites passing.
Remaining: an in-app Acknowledgements screen listing the OFL fonts (the licence files themselves ship).

### P1-3 — Paywall: mostly CLEARED
The premium product is a **non-consumable lifetime purchase**
(`com.williamjiamin.ThumbnailMaker.premiumlifetime2024`), not a subscription, so the 2026
renewal/cancellation disclosure rules do not apply. Present: localized `displayPrice`, Restore
Purchases, Terms and Privacy links (Settings). Suggested polish: state "one-time purchase" next to
the buy button.

### P2-1 — Data disclosure: AUDITED
The only network traffic is `Services/YouTubeService.swift`: YouTube Data API v3 `videos` lookup and
the thumbnail image fetch, triggered only when the user pastes a video link. There are no analytics,
tracking or third-party SDKs. The App Privacy answer is effectively "no data collected".

### NEW P0-2 — Release build has no YouTube API key
`Models/APIConfig.swift` reads the key from `Config/Secrets.plist` (gitignored — correct) or an
environment variable. **Neither exists in this tree**, so an archive built from it ships with YouTube
import failing (`missingYouTubeAPIKey`). Before archiving: create `Config/Secrets.plist` from
`Secrets.example.plist` with the **rotated** key (Gate 16), and restrict the key to the app's bundle ID
in Google Cloud Console, since any bundled key is extractable.

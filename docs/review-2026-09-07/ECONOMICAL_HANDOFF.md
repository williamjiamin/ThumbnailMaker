# ThumbnailMaker: economical implementation handoff

## Copy-and-paste instruction for the next agent

You are finishing ThumbnailMaker, an existing native Apple thumbnail editor. Work in `/Users/williamjiamin/Documents/ThumbnailMaker 2`. Your goal is a refined, reliable, publishable product, with features as the priority. SEO is optional and outside the active scope. Implement the existing 28-task backlog without starting a redesign or inventing additional work.

Use a conservative token budget: one agent, one coherent feature slice at a time, small targeted reads, focused tests, and persistent checkpoints. Do not spawn agents, launch research projects, or repeatedly reread the repository. Do not start another nested implementation loop. Stop when prerequisites are unavailable or the bounded run ends. Preserve all existing user changes.

First read this handoff, `docs/review-2026-09-07/backlog.json`, and the relevant section of `docs/review-2026-09-07/IMPLEMENTATION_PLAN.md`. Read applicable AGENTS.md instructions if present. Use the cached evidence described below. Inspect actual source before changing it, but do not repeat completed discovery unless evidence has changed. The detailed task acceptance criteria are binding; this handoff does not weaken them.

The previous agent was explicitly stopped by the user to conserve tokens. Resume only the bounded work authorized by this new handoff. Do not assume that a prior active goal authorizes unlimited work, automated spending, or store submission.

### 1. Start from the actual checkpoint

Established facts at handoff:

- Native branch was `codex/publish-readiness-m1`, native HEAD `768665a13b66b7cee80ececab90528271e718311`. Preserve this checkout and its newer uncommitted source. Verify these facts once when source access permits.
- Xcode 26.2 is installed. The project targets iOS/iPadOS and Mac Catalyst; no Android source was found. Deployment target was iOS 18.1. New Swift files are automatically included by synchronized Xcode project groups.
- The source is incomplete locally: the last inventory found 70 dataless iCloud files across app, resources, UI tests, scripts, and workflow. Critical missing files include PremiumMakerViewModel, ThumbnailDraftStore, main views, app entry point, Info.plist, and entitlements. Native Git index and project.pbxproj became readable. A complete native build has NOT passed during this work.
- Public remote `https://github.com/williamjiamin/ThumbnailMaker.git` exposed only `gh-pages`; the remote default is the website, not native app source. Do not reset, clone over, or replace the native project with it.
- The independent `website/` checkout was deployed at `0ef8f0863b21ba5e3ca92ef7c6cf3a69f9834f1b`. HTTP and visual checks were recorded. Leave it alone while implementing native features.
- Existing functionality already includes multiple layer types, transforms, undo/redo, drafts, five built-in templates, local design ideas, brand styling, automatic background removal, face/profile cropping, export presets, numbering macros, and small-size previews. Extend these foundations rather than recreating them.

Unfinished implementation to review before adding more code:

1. `ThumbnailMaker/Models/ThumbnailDocument.swift`: its image serialization now uses PNG instead of JPEG and normalizes non-up image orientation. This is intended to preserve transparent cutouts and prevent repeated lossy saves. Original backup is in `docs/review-2026-09-07/source-backups/ThumbnailMaker/Models/ThumbnailDocument.swift`. New `ThumbnailMakerTests/ThumbnailImagePersistenceTests.swift` covers draft alpha, premium/profile round trips, templates/history, legacy JPEG, and orientation. Swift syntax parsing passed, but type checking and runtime tests have NOT run. Review renderer color/scale behavior and run the tests before accepting APP-01.
2. `ThumbnailMaker/Models/PurchaseManager.swift` has an interrupted refactor; new `ThumbnailMaker/Models/PurchaseEntitlement.swift` supplies testable entitlement and restore-state types. Original PurchaseManager is backed up beside the document backup. Intended changes: complete verified-set replacement including empty sets, known product IDs, truthful restore-empty messaging, cancellation/error states, and no paid unlock from unsigned preferences. Do not assume the interrupted edit is complete. No separate purchase test file existed at handoff. Review all callers, exhaustive PurchaseError switches, task lifetime/concurrency, offline behavior, and quota behavior; add tests and build before accepting APP-02.

Neither APP-01 nor APP-02 is marked done. Do not overwrite these changes by restoring backups. Compare against backups to understand them, complete or correct them, and preserve original user work.

Cached reference map:

| Artifact | Purpose |
|---|---|
| `IMPLEMENTATION_PLAN.md` | Full feature specifications, product direction, acceptance intent |
| `backlog.json` | 28 task IDs, priorities, dependencies, steps, acceptance criteria, status |
| `REVIEW.md` | Confirmed findings and limits of the initial audit |
| `SOURCE_BASELINE.json` | Original source residency, sizes, timestamps, available hashes |
| `source-backups/` | Originals of the two files changed during implementation |
| `ACTIVE_IMPLEMENTATION.json` | Checkpoint; implementation stopped at user request |
| `docs/CI_GATES.md` | Established exact-revision release evidence rules |
| `docs/BETA_EXIT_CHECKLIST.md`, `docs/BETA_EXIT_REPORT.md` | Existing release work; inspect relevant sections, do not assume historical passes certify new code |
| `DEPLOYMENT.json`, `website-validation.json` | Completed website evidence; no need to repeat it |
| `run-loop.py`, `result-schema.json`, `LOOP_PROMPT.md` | Existing bounded serial runner and result contract |

### 2. Resolve source availability once, then proceed or stop

Task SRC-01 is the first dependency. Check file flags before reading; macOS dataless files can hang a read. Use bounded commands. `rg` was unavailable; use bounded Python or grep searches if still unavailable.

Recovery already attempted:

- Foundation `FileManager.startDownloadingUbiquitousItem` requests were accepted for the 70 missing files.
- Finder's **Download Now** was selected on the native `ThumbnailMaker/` source folder. Finder changed the folder to Downloading, but files had not materialized at last check.
- Targeted archive/Git-object requests were also accepted. They remained NotDownloaded with no download error. Accepted requests are not completed downloads; elapsed time alone does not establish a terminal error.
- The sibling `Documents/ThumbnailMaker` is substantially older and is not a replacement. Resident historical Premium view models and the index's ContentView do not match current file sizes. Some readable files are newer than the Git index.

Do one bounded residency check. If files have arrived, hash and back them up, establish the current source baseline, and build. If not, request the user to make this project available locally or provide a matching native checkout/archive; checkpoint and stop. Do not repeatedly poll, restart iCloud services, reset Git, disable safeguards, or spend the run reconstructing missing app files from guesses.

Only if a candidate has already materialized, these cached recovery leads can be checked cheaply:

- `ci/apple-ci-source.tgz`, expected 1,649,496 bytes. Extract to a separate temporary staging directory; compare current resident hashes before using its files.
- PremiumVM object `.git/objects/57/035f41c184c9b74a5ad31cd93e4660410ffe7b`; a resident tree paired it with the exact current SimpleVM hash. It is a candidate, not verified current source.
- Latest snapshot object `.git/objects/7b/38f6a59b229663aab2cf6073804c0761e5833d`. Codex snapshot refs may point to trees, not commits; do not reset the branch to them.
- Indexed DraftStore object `.git/objects/6f/60717754d3f584c10c5d7b17f6a0fdbbdfef22`. Historical only until its version is verified.

If recovery remains blocked, the correct result is a precise source prerequisite, not another speculative feature implementation.

### 3. Delivery order and concrete feature requirements

Respect the exact dependencies in backlog.json. The phases below guide priority among ready tasks. Independent prerequisites such as APP-05 and APP-07 should be completed when needed by a feature, even if listed later in a broader polish phase.

**Phase A — trustworthy foundation**

- SRC-01: complete source, preserve local changes, identify current app behavior, produce a fresh build/test baseline.
- APP-01: finish lossless image persistence. Transparent and partial-alpha selected/profile images must survive both editors, drafts, templates, and repeated undo/history without deterioration. Older JPEG documents must still open.
- APP-02: finish entitlement reconciliation. Test stale cache, empty verified results, revocation, unknown products, unverified transactions, valid offline entitlements, restore with no purchases, purchase pending/cancelled/success, and concurrent updates. A failed verification must not be reported as an authoritative empty result.
- APP-03: expose saving/saved/failed states with retry and recovery. Inspect the existing store first. Atomic saving and corrupt-file handling must protect the last good document. Include real save/relaunch coverage.
- APP-05: reproduce or rule out stale asynchronous updates. Use originating project/variant/revision checks and cancellation where necessary for imports, crop, cutout, and network results. Old work must never overwrite newer edits.
- REL-01: run the required foundation checks on the actual candidate; report outstanding gate requirements honestly.

**Phase B — complete the repeated-use workflow**

- FEATURE-01, project library: stable IDs, names, dates, previews, create/recent/search/rename/duplicate/reopen, recoverable trash, and one-time migration of both existing drafts. Ten projects must survive restart independently. Switching must complete or visibly fail the pending save. Isolate corrupt projects.
- FEATURE-06, portable editable projects: versioned manifest/document/assets/preview package, editable-copy import, new IDs on collision, and standard file flows. Validate paths, counts, sizes, missing assets, malformed and unsupported future versions. Failed import must not change the open project. Round-trip in a fresh data directory.
- FEATURE-03, reversible framing: original image plus normalized crop/focal/fit/fill/pan/zoom recipe; reset and replace-image-keeping-frame. Preview and export share geometry. One completed gesture is one undo step. Cover portrait, landscape, oriented, and transparent inputs.
- FEATURE-04, text styles: shared persisted outline/shadow/panel/padding/line and letter spacing/alignment/width; sensible presets and reset. Apply to legacy text and added text layers with one renderer. Preserve legacy appearance and test CJK, Latin, emoji, fallback fonts, rotation, large text, and export parity.
- FEATURE-02, saved variants: named editable A/B/C documents, independent history, duplicate, preferred variant, two/three-way comparison at identical thumbnail sizes, and explicit export naming. Editing B must not alter A or C. Preference is a user choice, not a measured winner.
- FEATURE-05, personal templates: named reusable layouts, categories/favorites/previews, duplicate/update/recoverable deletion, explicit image/title slots and retained brand assets. Keep built-ins. Apply with fresh layer IDs and one undo action; template edits must not mutate existing projects.
- REL-02: integrated project → edit → variant → template → portable file → export journeys, including migration and accessibility. This milestone is not completion of the full roadmap.

**Phase C — productive precision and reuse**

- FEATURE-07: selection sets, groups, group transforms, align/distribute, visible-object snapping with override, and separate workspace zoom/pan/fit. Exclude locked/hidden objects appropriately. Ungroup preserves appearance; workspace navigation must not change export pixels. Provide keyboard and accessible numeric alternatives.
- FEATURE-08: verify current brand collection support, then add multiple named kits and reusable styles as needed. Duplicate/rename/switch, active-kit indication, selection-only and explicit project-wide application with undo. Three independent kits survive restart; deleting a kit cannot break resolved project styling.
- FEATURE-12: editable arrows, badges, callouts, fill/stroke/geometry/arrowheads using ordinary layers and shared rendering. Preserve existing shape compatibility and compact-phone usability.
- FEATURE-11: separate editable cutout mask, erase/restore brush with size/softness, before/after, zoom, feather/reset/undo. Keep originals; preserve partial alpha and independent copies. Profile large-image operations and reject stale processing.

**Phase D — production workflows**

- FEATURE-09: landscape/square/vertical editable formats with independent crop/layout overrides. Show proposed reflow, preserve focal intent, flag clipping, and clearly expose reversible content linking if used. Original design stays unchanged.
- FEATURE-10: variants × sizes export queue and saved recipes using existing exporters. Show exact names/destination/format/overwrite behavior before running. Progress/cancel/partial failure/retry only failed items. Bounded file-size fitting with quality floor; never silently change dimensions or format. Verify a 3 × 3 fixture's pixels, names, and count.
- FEATURE-15: local title/image/episode/slot table and documented CSV import, per-row validation/preview, deterministic rendering, immutable source template, queue cancellation/retry. Verify ten rows and isolate malformed rows while valid rows remain usable.
- FEATURE-14: essential reversible brightness/contrast/saturation/blur/vignette recipes, before/after/reset/named looks. Check existing demand evidence; do not claim validation from invented users. Original alpha/color must survive reset; preview and export must agree.

**Phase E — refinement throughout, final acceptance at the end**

- APP-04: explicit import transfer/decode/unsupported-format errors and useful recovery; preserve the current document when an import fails.
- APP-06: readiness checks consume all visible layers and distinguish unmeasured properties. Deliberate image-only work is allowed; no predicted click-through claims.
- APP-07: accessible names, values, selected states, focus order, keyboard actions, and real accessibility audits. Fix export-preset selection semantics; do not hide failures with broad audit exclusions.
- APP-08: complete small-phone journeys with large text, reachable controls, sensible sheets/panels, and usable canvas. Verify actual workflows rather than isolated screenshots.
- APP-09: measure 12 MP image editing, history, saves, variants, and exports on named devices. Record latency and peak memory, then set explicit budgets. Reuse immutable assets and avoid reencoding unchanged images on every text edit. Keep heavy work off the main actor where appropriate.
- FEATURE-13: short skippable/resumable first-export guidance using real features; never reset existing work. Guided and direct journeys must both pass. Representative-creator study evidence requires actual participants; record it as an external prerequisite if unavailable.
- REL-03: after every preceding task, rerun the integrated release matrix on the final exact candidate. Produce release evidence and remaining external actions; no unrequested store submission.

### 4. Architecture rules that prevent expensive rework

Extend the existing document, layer, renderer, history, and store abstractions. Inspect them before choosing storage. Use immutable original assets shared safely through references, explicit document migrations, and stable project/variant identities. Store crop, mask, adjustments, and styles as reversible recipes. Avoid a new framework or database unless existing persistence cannot meet demonstrated needs.

Every persistent feature includes model, migration, controls, save/reopen, undo, and error handling. Every visual feature includes canvas/small-preview/export parity. Do not declare a model-only scaffold or disconnected panel complete. Project and variant switching must isolate history and asynchronous results. Keep export flattening separate from editable project packaging.

### 5. Verification and publishable-product definition

After source recovery, inspect the existing scripts before choosing commands. A known baseline command is:

```sh
xcodebuild build-for-testing -project ThumbnailMaker.xcodeproj -scheme ThumbnailMaker -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/thumbnailmaker-handoff-dd COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO
```

Discover currently available simulator IDs once; do not reuse a stale ID blindly. Run focused unit tests for changed behavior, relevant UI journeys, then the broader milestone matrix. Save logs and fresh xcresult bundles. Syntax parsing is not type checking, and a successful build is not a passing user journey.

`docs/CI_GATES.md` requires exact-revision self-hosted Mac mini evidence: unit, UI smoke, extended UI/accessibility, and Catalyst, with host, revision, logs and result bundles. A local MacBook build does not satisfy that gate. The historical remote workflow/branch may currently be unavailable; verify access once, then record a concrete external prerequisite. Do not dispatch nonexistent workflows repeatedly.

For final release readiness, reconcile the existing beta checklist and privacy/configuration documents with the finished behavior. Verify purchase/restore, file import/export destinations, required platform permissions, legal/support links, asset/font licensing evidence, release configuration, signing/archive prerequisites, crash-free primary journeys, migrations, and recovery paths as applicable. Do not add tracking, cloud services, credentials, or paid dependencies to solve routine local features. Report unavailable real-device, human-study, signing, or CI evidence explicitly.

The product is publishable only when all required functionality works end-to-end, old work migrates safely, acceptance checks pass on the final revision, and existing release gates are satisfied. Prepare a release candidate and evidence; App Store submission remains a separate user action. Do not publish private native source to gh-pages.

### 6. Economical iteration contract

For each iteration:

1. Read the checkpoint and choose one ready task or its next small end-to-end slice. Read only relevant source and acceptance criteria.
2. Verify the gap, implement it, and run the smallest meaningful checks. If an earlier check already passed and code has not changed, reuse its evidence instead of rerunning it.
3. Review only the final diff for the slice. Preserve unrelated changes; do not blanket-format or refactor.
4. Record changed files, exact checks/results, open acceptance criteria, and one concrete next action. Use concise logs, never credentials or full environment dumps.
5. Mark done only with evidence for every acceptance criterion. Use continue for partial implementation and blocked for unavailable prerequisites. After two attempts with the same failure and no new evidence, stop that path; proceed only to genuinely independent ready work.
6. At milestones run broader checks once; failures justify focused fixes and reruns. End when the scoped backlog is complete or the run limit is reached. Never manufacture new work to sustain the loop.

Use a compact checkpoint per task: status; changed files; evidence paths; remaining criteria; next action; blocker and required external action. Retain historical results. Do not reread all previous logs on every iteration.

When running under `run-loop.py`, the runner owns backlog.json and loop-state; obey its schema and do not edit its state from workers. When working manually, update backlog/checkpoints atomically and ensure no runner is active. Do not run both modes concurrently.

### 7. Start small, then extend successful runs

The existing runner inherits the user's configured Codex CLI model; it does not choose a cheaper model automatically. Select your intended lower-cost model in your CLI configuration before launching. Do not silently change account or app model settings. Prefer ordinary reasoning for implementation and use stronger review only if the user later requests it.

Read-only preflight:

```sh
python3 '/Users/williamjiamin/Documents/ThumbnailMaker 2/docs/review-2026-09-07/run-loop.py' --project '/Users/williamjiamin/Documents/ThumbnailMaker 2' --dry-run
```

After source is available, start a small run:

```sh
python3 '/Users/williamjiamin/Documents/ThumbnailMaker 2/docs/review-2026-09-07/run-loop.py' --project '/Users/williamjiamin/Documents/ThumbnailMaker 2' --max-iterations 3 --max-hours 1 --iteration-timeout 1200 --max-attempts 2
```

Inspect the resulting evidence before increasing to an eight-iteration/four-hour run. These are time/attempt bounds, not token or spending caps. The runner was tested with mocks and dry-run, not a completed real feature program. Large tasks may need multiple successful slices; if attempt limits are reached, preserve results and split the task deliberately without weakening acceptance criteria.

Do not launch the runner while source remains missing just to rediscover the same blocker. If using this prompt directly in an agent, implement one bounded slice at a time under the same rules instead of starting the runner recursively.

Your first response should be a short source/checkpoint status and your chosen next slice. Your final response should state what actually changed, verification results, remaining work, and the precise resume instruction. Keep conversation output brief; save detailed evidence in files.

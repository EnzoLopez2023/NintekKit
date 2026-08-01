# Native Port Playbook + Cairn Retrospective

The process guide for porting one of Enzo's web apps to native SwiftUI (Cairn →
ShopKeep → Tare → Workshop → Puzzlebox). Written after the Cairn port, which
worked but had avoidable rework. **Read Part 2 before starting any port; read
Part 3 before ShopKeep specifically.**

The one-line lesson: **most of what we "missed" on Cairn was not a coding
problem — it was a planning problem.** We started building before we had
inventoried the web app's data, behavior, and design, and before we had decided
the architecture. Everything below front-loads those into an explicit discovery
phase so the build phase has no surprises.

---

## Part 1 — Cairn retrospective: what we missed and why

| # | Miss (symptom) | Root cause | Lesson |
|---|---|---|---|
| 1 | **UI looked nothing like the web app initially.** First native build was plain SwiftUI (two tabs, system styling); the cream/rust/ink + serif editorial look and the web-matching home layout came in a *later* "web-parity polish pass," and even then only after the user pushed ("looked nothing like the React app"). | The plan framed the port as "SwiftUI client of the REST API." It never inventoried the web app's **design system** (MUI theme tokens, Playfair/serif type, spacing) or did a screen-by-screen visual comparison. Visual parity was implicit, not an acceptance criterion. | Extract the design system **first** (colors, type, spacing, component patterns). Capture reference screenshots of every web screen. Make "matches web screen X" an explicit, per-screen done-criterion. |
| 2 | **API / persisted-data surface was discovered incrementally.** We kept finding data late: the content endpoints, the **10** synced `exam-prep-*` keys, drill-stats vs analytics vs completed, that `exam-prep-reading` is per-device (NO_SYNC), the insights endpoint — and worst, that **Practice/Sandbox had to *write* drill/analytics locally** (only caught during the CloudKit migration; without it the whole Details/Activity/Diagnostic surface reads empty). | No exhaustive up-front audit of (a) every backend route, (b) every persisted key with its **read and write** sites and sync semantics, (c) every client-side aggregation hook (`useDetailedStats`, etc.). We audited reads, not writes. | Do a complete **data-flow audit** before building (see Part 2 §0.2). Enumerate every route and every persisted key; for each key record who **writes** it and who reads it. Write paths are as important as read paths. |
| 3 | **Web behaviors surfaced as user corrections, not from the plan.** "Active exams sort to top," focus/Continue-exam ordering, active-first on level pages, SM-2 semantics, the sandbox scaled-score formula — all came up after the fact. | The plan captured **features** ("build Practice", "build the catalog") but not the **behavioral rules** inside each feature (sorting, defaults, empty states, formatting, edge cases). | For each screen, write a short **behavioral spec** pulled from the web source — sort order, empty/loading states, number/date formatting, edge cases — not just "build screen X." |
| 4 | **The auth/architecture decision was made mid-flight, then reversed.** We built the entire app on MSAL + Azure, shipped it to TestFlight, *then* ripped MSAL out for CloudKit + no-login. Real rework (a whole auth layer, entitlements, redirect plumbing) thrown away. | The plan **assumed** "keep the Azure backend, native = REST client + MSAL" (inherited from the portfolio strategy's "sync is non-negotiable → keep backend") without ever weighing the "fully native / CloudKit / no-login" option — which Cairn's actual constraints (separate user bases acceptable, no web↔native sync needed) made both viable *and simpler*. | Make identity + data-residency + backend fate an **explicit Phase 0 architecture decision** with written pros/cons, decided **before any UI code**. The deciding question is usually: *does native need to share data with web?* If no, CloudKit/no-login is often simplest. (See Part 2 §0.1.) |
| 5 | **The native platform features — the entire reason to port — were an afterthought.** Widgets, haptics, Live Activities, App Intents, notifications, macOS all landed in a separate "enhancement phase" *after* parity, and the widget wasn't even themed (shipped green). | The plan's goal was "reach parity with the web app," which framed native affordances as bonus polish. The motivation for porting (native platform value) never made it into the work breakdown. | Native-platform features are **core scope, not polish.** Name the app's **native thesis** (the capabilities that justify porting) in Phase 0 and put them in the todo list next to parity, each with its own done-criteria. Auxiliary surfaces (widgets, Live Activities) are only "done" when themed. |
| 6 | **Project/tooling churn.** xcodegen retired then un-retired; version/build kept resetting; a widget-scheme trap ("could not attach to pid"); MSAL keychain/signing (-50000), missing iPad icon (90713), dSYM warnings. | No settled project-generation strategy and no reusable target template; each config concern was solved reactively. | Settle project generation once (**xcodegen as source of truth, everything in `project.yml`**). Keep a reusable **app-target template** with signing, entitlements, App Group, capabilities, a single shared app scheme, the icon set + `CFBundleIconName`, and orientations pre-baked. |

---

## Part 2 — The playbook (apply to every native port)

### Phase 0 — Discovery & Architecture (NO app code yet)

This phase is the whole point of this document. Its output is a short written
plan that makes Phase 2+ mechanical.

**0.1 Architecture decision (write it down, with pros/cons).** Answer, in order:
- **Does the native app need to share user data with the web app?**
  - *No* → strong candidate for **CloudKit private DB + no login** (implicit
    iCloud identity, syncs across the user's Apple devices, no server, offline).
    This is what Cairn became.
  - *Yes* → **keep the shared backend**; native authenticates to it. Then decide
    the identity provider (below). This is ShopKeep and Workshop.
- **Identity:** none (iCloud-implicit) / Sign in with Apple / existing IdP
  (MSAL). Weigh App Store **Guideline 4.8** (a third-party/social login forces
  offering Sign in with Apple) and 5.1.1(v) (an account forces account
  deletion). No login avoids both.
- **Backend fate:** keep / decommission after migration / shrink to an AI proxy.
- **Content:** is any of it static? Static content should be **bundled** (ships
  offline, no auth) rather than fetched.
- **Monetization path** (even if later): StoreKit 2 is Apple-ID-scoped and needs
  no login or server — confirm the chosen architecture doesn't block it.
- **Security prerequisites:** fix any server auth holes *before* the port
  (ShopKeep's client-supplied `X-User-OID` was one). **When you deploy an auth
  change, verify the ACCEPTANCE path end-to-end, not just rejection.** ShopKeep's
  JWT-hardening deploy passed a "bad tokens → 401" check but nobody confirmed a
  *real* token → 200, and it took prod down twice: (1) runtime env vars the code
  requires weren't set in the App Service (`process.exit(1)` → 503); (2) the
  Entra app registration never actually Exposed the API scope the frontend asks
  for (`AADSTS500011` → no token → 401s + a login loop). Checklist before shipping
  an auth change: required runtime env/app-settings exist in the target env; the
  identity provider config (scopes/Expose-an-API, redirect URIs, audiences)
  actually exists; and a live end-to-end sign-in returns real data — "committed"
  ≠ "deployed" ≠ "works".

**0.2 Data-flow audit (exhaustive).** Produce a table:
- Every **backend route** → who calls it, is it per-user or static.
- Every **persisted key/table** (localStorage, SQLite, KV) → its shape, its
  **write** sites, its **read** sites, and its **sync semantics** (synced?
  per-device? derived?). Flag NO_SYNC / per-device keys — they can't be pulled
  cross-device.
- Every **client-side aggregation** (React hooks/selectors) → the native app
  must reproduce these; port the logic, don't reinvent it.
- For each item, assign a **native owner**: bundled resource / local (SwiftData)
  / remote API. **Explicitly list every write path** — the native app must write
  what the web used to write, or aggregations read empty (miss #2).

**0.3 Design-system extraction.**
- Color tokens (from the MUI/Tailwind theme), typography (families, the display
  face), spacing, corner radii, elevation.
- Screen-by-screen **component inventory** with reference **screenshots** of the
  live web app.
- Promote shared tokens into **NintekKit** (a `DesignTokens` module) so the app
  *and its widgets/extensions* share one source of truth (the green-widget bug
  in miss #5 happened because the widget target duplicated colors).

**0.4 Behavioral specs.** For each screen, one short paragraph from the web
source: sort order, default selection, empty/loading/error states, number/date
formatting, notable edge cases.

> **⚠️ Hard-won rule (cost me 3 reworks on ShopKeep): the `.tsx` is the spec, not
> the screenshot.** Before building a screen, open its React component and
> enumerate **every** field, section, and chart it renders — then port that list.
> ShopKeep Reports shipped 2 of ~25 charts, and ToolDetail shipped missing
> Product Page / Detail / Notes / barcode, each time because I matched a *picture*
> instead of reading the source. A screenshot/PDF is a visual cross-check; the
> component source is the source of truth. `grep -nE "Card title=|label:|<Field"`
> the component to get the full inventory fast.

**0.5 Native thesis.** List the platform capabilities that *justify* this port,
ranked. These become first-class Phase 3 todos. (Cairn: widgets, haptics, Live
Activity, App Intents, notifications, macOS. ShopKeep: **VisionKit barcode +
document/OCR scanning, camera capture** — the headline.)

**Phase 0 exit criteria:** architecture decided + written; data audit table
complete (reads *and* writes); design tokens + screenshots captured; per-screen
behavioral specs written; native thesis listed. Only then plan the todos.

### Phase 1 — Foundation
- Reuse **NintekKit** (design tokens, shared models, and either the REST client
  or a local `Store` facade depending on 0.1). Keep NintekKit dependency-free
  and headless-testable.
- Stand up the **app-target template**: xcodegen `project.yml` with signing,
  entitlements, App Group, the Phase-0 capabilities (CloudKit? camera? push?),
  a single shared **app** scheme, icon set + `CFBundleIconName`, orientations.
- Build the data layer chosen in 0.1 (CloudKit `@Model`s / REST client), with
  the write paths from 0.2 stubbed in.

### Phase 2 — Screen parity *with native feel interleaved*
- Build screens against the **design tokens** and **behavioral specs** from
  Phase 0 — parity is a checklist, not a discovery.
- Haptics, gestures, and transitions are part of each screen's **done**, not a
  later pass.
- A screen is done when it matches its reference screenshot *and* its behavioral
  spec (sort/empty/format/edge).

### Phase 3 — Native thesis features (first-class todos)
- One todo per capability from 0.5, each with its own acceptance criteria.
- Extensions/auxiliary surfaces (widgets, Live Activities) use the shared
  NintekKit tokens and are only "done" when themed.

### Phase 4 — Ship
- Icons + App Store validation (the 152px iPad icon / `CFBundleIconName` traps),
  privacy nutrition labels, 4.8/4.2 compliance per the 0.1 decision.
- CloudKit apps: **deploy the schema to Production** before TestFlight.
- TestFlight; retire the web wrapper only at parity.

---

## Part 3 — ShopKeep-specific notes

ShopKeep is **not** a Cairn clone — its architecture fork lands differently:

- **Sync is required and web must survive** → ShopKeep **keeps its Azure
  backend**; native is a client of it. So the Cairn answer (CloudKit + drop the
  server) does **not** apply here. In Phase 0.1, the real choice is the
  **identity provider** for that backend: Sign in with Apple + a backend session
  exchange (recommended for a public app; satisfies 4.8) vs keeping the existing
  scheme. Do **not** default to MSAL without weighing it (miss #4).
- **Server auth hole is a prerequisite:** ShopKeep trusted a client-supplied
  `X-User-OID` with no validation. The server-side JWT validation fix is done —
  confirm it's deployed and that the native client sends a real bearer token
  before building features on top.
- **Native thesis (0.5):** VisionKit `DataScannerViewController` for live
  barcode scanning, document/receipt OCR, and camera capture. This is the
  headline reason ShopKeep is the strongest native payoff — scope it as Phase 3
  todos from day one, not an afterthought.
- **Data audit (0.2):** inventory ShopKeep's inventory/item/image/AI endpoints
  and any localStorage the web relies on; identify image upload/serving and AI
  rate-limiting (both were flagged as hardening items).
- **Reuse:** promote Cairn's `Store`-facade pattern and the design-token module
  into NintekKit so ShopKeep starts from a foundation, not a blank slate.

---

## Part 4 — Tare retrospective: the source is necessary, and not sufficient

Tare is the fourth port and the first with irreplaceable data. Cairn's lesson
was *the `.tsx` is the spec, not the screenshot.* Tare adds the converse, and it
cost four bugs to learn: **the source tells you what should be drawn; only the
screenshot tells you what is.** Three of Tare's four component-level defects
were invisible to a line-by-line source review *and* to a green test suite, and
all three lived in components that three earlier screens had already shipped on.

Run both passes on every screen. They find disjoint sets of bugs.

### Verify against the captured reference, never against reasoning about CSS

The Glucose hero clipped a scale label. It was reasoned to be faithful, because
the web's `viewBox` really does cut the label in half. Wrong: the SVG also
carries `className="overflow-visible"`, so the label spills legibly into the
card's padding. One glance at the captured screenshot would have settled it; an
hour of reading the viewBox arithmetic did not.

**Capture a reference set in Phase 0 and actually open the images.** Reasoning
about stylesheets is not evidence.

### Pixel-sample rather than eyeball

Two fixes in a row looked right and were not. What settled both was scanning a
single row of pixels for the card's edge (`PIL`, first column where all channels
exceed 245) and comparing it with the expected point value times the scale. A
layout regression that "looked about right" was 5pt where 16pt was intended.

### SwiftUI traps that cost the most

1. **A modifier applied to a multi-child `@ViewBuilder` applies to *each*
   child.** `content.padding().background()` inside a card component silently
   renders one card per child once a caller passes two. Always wrap the builder
   output in a container first:
   ```swift
   VStack(alignment: .leading, spacing: 0) { content }
       .padding(16).background(...)
   ```

2. **`Canvas` always clips to its bounds.** SVG's `overflow: visible` has no
   equivalent. Draw into bounds widened by an explicit bleed and re-origin the
   drawing — and host the oversized canvas in an `.overlay`, because an overlay
   is laid out against its parent's size and can never widen it.

3. **`.fixedSize()` on a label inside an `HStack` steals the page's padding.**
   Given an incompressible row, SwiftUI resolves the overflow wherever it can,
   which may be the ancestor's padding rather than the row. Use
   `.lineLimit(1) + .minimumScaleFactor(...)` to keep text on one line while
   staying compressible.

4. **Toast/snackbar overlays must be hoisted out of the `ScrollView`.**
   Web toast libraries render a fixed-position portal. Attaching
   `.overlay(alignment: .bottom)` to a screen pins the toast to the *content*,
   so on a long page the confirmation lands thousands of points below the fold —
   present in the accessibility tree, invisible to the user. Host one toast
   surface in the shell, outside the scroll view, and publish to it through the
   environment.

5. **A `Canvas` cannot be animated by `withAnimation`, or by passing a changing
   `Double`.** The drawing closure captures its inputs when the body is
   evaluated, and SwiftUI compares `Canvas` values and reuses the cached
   drawing. Use `TimelineView(.animation(paused:))`, and hold the animation's
   start instant in a **reference type** — `TimelineView` refreshes its closure
   parameter every frame but keeps the captured `self`.

6. **Chart components that clip will eat marker labels.** Charting libraries
   draw reference-line labels in the reserved top margin and do not clip them.
   If the port's chart frame clips its plot content, stacked labels vanish
   without a trace. Draw captions in an unclipped overlay.

### UI-testing lessons

- **A tab bar keeps every route mounted.** Hiding inactive tabs with
  `.opacity(0)` and `.accessibilityHidden(true)` does *not* remove them from the
  accessibility tree, so a text query can match a row on a screen that is not
  displayed. Assert against a control the screen owns, e.g. a count of buttons
  with a screen-specific identifier.
- **When an assertion fails, dump `app.debugDescription` and read it.** Never
  guess at labels. On Tare the dump proved the write had landed and located the
  toast at y = 5172.7, which is what identified bug 4 above.
- **A query can match a combined accessibility container *and* its child.** Use
  `.firstMatch`.
- **Give test-only timings generous margins.** A single accessibility snapshot
  of a long page can itself outlast a 2-second toast, so the element the test is
  looking for expires while the query runs. Scale such dwells up under test.
- **`xcodebuild -quiet` suppresses "BUILD SUCCEEDED".** Read the result bundle
  (`xcresulttool get test-results summary`) rather than trusting console output,
  and `rm -rf` the bundle path first — `-resultBundlePath` fails if it exists.

### Data migration deserves its own gated phase

With irreplaceable data, promote migration ahead of screen parity and gate on
`export(import(real fixture)) == real fixture`, field-by-field and key-by-key.
Two things that mattered: the export path must not derive its column list from
`Object.keys(rows[0])` (a null in the first row silently drops a column for
every row), and the round trip must be run **on the physical device**, not only
in the simulator.

Doing it first also pays for itself immediately — the real fixture is what makes
screen verification meaningful. Half of Tare's Glucose screen sits behind render
guards a hand-seeded fixture cannot satisfy, so those cards would have shipped
having never been drawn. Restoring the real export at launch through the app's
own restore path exercises the importer end to end on every UI test as a side
effect.

### Port bugs, then fix them — but write them down

Tare's weight history chart drops the most recent weigh-in: it steps a fixed
86,400,000 ms rather than a calendar day, and the series crosses a DST boundary.
The port reproduces it deliberately, with a test pinning the defect, so parity
can be proven before behaviour changes. That is the right order — but it only
works if every such decision is recorded where the sign-off can see it.

---

*Maintainer note: keep this current after each port — it's the compounding
value of doing five of these.*

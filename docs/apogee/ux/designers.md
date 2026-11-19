# Designer onboarding (squad UX designers)

Owner: **ux** (UX lead). For the squad UX designers who join with the squads charter (11-19). Read this first, then
the files it points to. You design your squad's console flows and words. ux owns the design system and the wording
rules you work to, and reviews UI that crosses squads.

## 1. Read first, in this order

1. [`design-language.md`](design-language.md): the build spec. §1 Principles, §4 Vocabulary, time and numbers,
   §8 Content rules and §10 Do / Don't are the minimum; §7 lists the kit components (use them, don't draw new ones).
2. [`tokens.css`](tokens.css): every color, type and space value. No raw hex, no default Tailwind colors.
3. [`information-architecture.md`](information-architecture.md): routes, the rail, where a new page goes.
4. [`screens/README.md`](screens/README.md), then your squad's screen specs (your squad's owned paths are in the
   owned-paths table in `TEAM.md`; for Mission Model & Spacecraft: Setup, AddSpacecraft, Catalog and Profile, with
   Changes shared with Commanding & Approvals).
5. [`a11y-checklist.md`](a11y-checklist.md): sections A (every sheet) and B (every screen) apply to everything you
   design.
6. [`decisions.md`](decisions.md): the rulings log, U1 onward, newest at the bottom. Don't read it end to end; search
   it by screen, error code or U-number before you write words for anything that already exists.

## 2. The design system in six lines

- **An instrument panel, not a web page.** Grayscale interface; white marks what you can act on and what is live;
  the only hue is operational state.
- **State is mark + color + word**, and must read in grayscale.
- **Truth before calm:** no data is a state (never a zero, an empty chart or green).
- **The console holds still:** ops screens fit the viewport and panes scroll; the commit action sits beside the state
  that justifies it.
- **Speak flight:** AOS, LOS, pass, uplink, GO / NO-GO. Never "items", "records", "entities", and never "legacy" on
  screen.
- **One format everywhere:** UTC with `Z`, `T−` / `T+`, U+2212 minus, thousands separators, correct plurals, name +
  SCID on every target row.

## 3. Wording rules (the ones reviews catch most)

- **Claim only what's known (U20).** Success words come from the server's answer, never from "the request didn't
  fail": "Approved. Booking 40 passes." shows only when the answer says approved; anything else gets a "Cadence
  didn't record…" / "didn't confirm…" line. Failure words state an outcome only when the code says it.
- **Never invent identifiers (U25).** No id where a name belongs. A missing name reads "Unknown spacecraft" ("on an
  unknown spacecraft" in a sentence); "Deleted spacecraft" only where the server says so. Raw ids go only in
  **Technical details**.
- **A missing value reads as a plain noun phrase** ("a catalog revision", U65), never null, a blank or an invented
  value. A count that can't be computed is `—` with its reason (design-language §1).
- **Who and when are one event (U29):** "by Mira K. at 03:40Z" together, or neither. A service identity is marked
  so it doesn't read as a person: "by Nightly planner (a service identity) at 05:40Z", in a sentence or in a "by …"
  cell. The `Service` tag is only for a cell that holds the name alone (as the audit does). A service without a name
  is never shown as an id (U25).
- **Refusals open with what didn't happen, by the person's act:** "Not saved:", "Not sent:", "Not approved:",
  "Not applied:". Then why, in one sentence, then what to do. An approval refused before it was recorded says
  "Your approval wasn't recorded." after the why, and before what the reader does, so the line ends on their act
  (U95).
- **A code the console doesn't know** gets a plain refusal ("Not approved: Cadence refused this approval.") with the
  code in Technical details. Never map an unknown code onto a known code's sentence.
- **Lists of names:** up to 3, then "and N more" (with `Show all` where the full list matters).
- **Headlines state the situation, buttons say the act and its scope:** "3 spacecraft need you",
  `Approve and book 40 passes`, `Stage v15 for Block 2`. A confirm sheet's title names the act.
- **Option words, never enum values:** "Needs a second person's approval", not `independent`.
- **Words for the console go on console routes only.** Don't change server copy that the legacy host still renders;
  ask ux when a page is shared.
- When you're unsure, find the nearest U-entry and match it. Write to ux with the new case; don't improvise a third
  pattern.

## 4. Console patterns to reuse

- **Disabled with its reason (A6/A7):** a disabled action keeps a reason that's reachable without hover (focusable,
  `aria-describedby`), muted `text-3` under the control and as its description. Disable up front when the read can
  say why; the server's refusal stays the backstop.
- **Refusals** show in the place of the act (sheet or panel), announced (`role="alert"`); outcomes of actions are
  announced too (a11y B6).
- **Sheets:** focus goes to the first field, or to the safe button on a danger sheet; Esc closes; focus returns to the
  opener. Below 768px every sheet is full-height (design-language §9).
- **Four-eyes:** the person who staged or submitted something never sees an Approve they can't use; the record names
  who decided and when (U89, U95, U97).
- **What the console can't read (U86):** say so, never hide it; if it's part of what someone approves, Approve is
  disabled until it can be shown.
- **Technical details** is the one place for codes, raw ids, keys and JSON.
- In code, words are typed: `known([...])` and `Record` word maps for closed sets, `knownErrorCode` for error codes,
  `// free-text:` for open vocabularies. No new `as` casts.

## 5. How we work

- **Who sets what:** your squad lead sets what you work on next, inside the milestones; ux sets the rules you work
  to.
- **Your squad's flows and words:** write them as U-entries in `decisions.md` (heading
  `### U<n> · <topic> (<issue>) (<owners>)`, newest at the bottom), in a docs-only PR from your own branch off develop.
  Take the next free number when you open the PR; if a rebase shows it taken, renumber. Screen-level layout goes in
  your squad's `screens/` spec.
- **Reviews:** squad-internal words and flows are reviewed inside your squad. Send to **ux** anything that:
  - adds or changes a kit component, token or a rule in `design-language.md` or `a11y-checklist.md`;
  - changes a pattern another squad uses (refusals, approvals, sheets, Technical details, time and number formats);
  - touches another squad's screens, the shell, the rail, the palette or Now.
  ux records its review in the PR, like any other reviewer. Words and flows about who may approve, four-eyes, or a
  mission's approval setting also go to your squad's security engineer (the charter makes them a required
  reviewer on approvals and permissions).
- **Before engineers build:** words first. Engineers ask for words with the error codes and the response shape; you
  answer with the exact lines and the U-number. A shape change (a new code, a new null) comes to you before it ships.
- **Looking at screens:** e2e suites run in CI only. On laptop 1 (the shared dev stack) there's no local browser
  either: review from the code, the spec and the screenshots the builder attaches. On a worker laptop your squad lead
  decides; a local console there runs through that laptop's own heavy gate and never points at laptop 1's :4011, its
  simulator, its Postgres or its QuestDB (qa's stack).
- **Public repo:** nothing secret in branches, PRs or comments; never a person's email, a password, a token or the
  node cookie.
- **Merging:** the release lead or the director merges after green CI and a different agent's review. Never push to
  develop or main.

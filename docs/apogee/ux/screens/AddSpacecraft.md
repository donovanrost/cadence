# Add spacecraft (S2 · 1 or 50, same flow)

Route `M/setup/spacecraft/new[/:step]` with `step ∈ source | identity | orbit | review` ·
**takeover layout** (no rail, U5) · Board `AddSpacecraft.dc.html` (draws step 04 Review).
Owner: fe-setup. Data and gaps: `docs/apogee/plans/setup.md` §S2.

**Question:** "Add this launch batch without configuring each spacecraft by hand."
**Journey:** pick a profile + count + naming pattern, or drop a manifest CSV → Cadence proposes
SCIDs, planes and routes and checks clashes → review the batch as a table → create (or stage, under
option A).

## Takeover frame
The flow header **replaces** the shell top bar (U19): one 52px row (`chrome` bg, hairline
bottom), with org / mission in its context line: left `×` close button (`aria-label="Close and keep draft"`,
→ back to where the flow was opened) + mono lbl `REFLECT ORBITAL / EARENDIL · SETUP · SPACECRAFT` over title
`Add spacecraft` (display 20px); center **ApStepBar** `01 Source · 02 Identity · 03 Orbit &
routing · 04 Review` (done = `✓`, current = `●` + `aria-current="step"`; done steps are links back);
right mono meta (`CONFIG r5 → r6 draft` only under option A; otherwise omitted).
Main: max 1400px centered, `20px 24px 28px`, two columns: steps content (flex 999 1 640) + **A4
summary aside** (flex 1 1 340, sticky top) on every step.
The draft is kept client-side per mission (session storage) so `×` and reload don't lose work.

## Step 01 · Source
Panel A1 `Source`. `choice` segmented radiogroup: `From a profile │ From a manifest`.
- **From a profile:** profile picker as ApOption cards (name + version, `catalog rev 14`, `uplink
  CCSDS TC · downlink CCSDS TM`, `N spacecraft use it`). Selected = white border. Link `New profile`
  → Setup › Profiles (opens in place of the flow, draft kept).
- **From a manifest:** drop zone (`Drop a manifest CSV, or choose a file`) + `Download manifest
  template (.csv)`. After upload: file name (mono), `50 rows · 6 columns mapped · uploaded by
  Donovan R.`, and column-mapping chips `name→Name`, `scid→SCID`, `norad→NORAD id`, `plane→Plane`,
  `slot→Slot`, `profile→Profile`. Unmapped columns show as dashed chips with a select to map or
  ignore. Required: name, scid (or generate), profile (or a default picked here).
- Next: `Continue to identity` (primary, commit size). Disabled with reason until a profile or a
  parsed manifest exists.

## Step 02 · Identity
Profile path only. Manifest rows already carry identity: the step shows the parsed rows' identity checks, and a
row with a problem reads "fix them in the file and choose it again" (ux, audit S9). Inline cell editing is later.
Fields (ApField, two columns): **Count** (number, 1–500), **Naming pattern** (mono, default
`EARENDIL-{scid}`; tokens `{scid}`, `{n}`, `{n:03}`; live preview of first and last name),
**SCID range** (start, prefilled with the next free SCID from the server; end computed and
read-only), **NORAD ids** (optional, "add later" default).
Inline clash check under each field (caution: "SCID 512 is already EARENDIL-512"). Next:
`Continue to orbit & routing`.

## Step 03 · Orbit & routing
- **Orbit (optional):** plane assignment `choice`: `Fill planes 11–12, 25 per plane` (from count)
  / `From manifest` / `Not now`. Plane and slot are metadata today (plan gap); the step says "Planes
  show on the constellation view and the fleet matrix" so the value is clear.
- **Routing** (as built; profile rules exist now, Profile.md P2): the step summarises what the profile's rules
  generate for the batch ("Rule `Block 2 · all stations` generates 6 routes per spacecraft"). There's no
  per-batch transport list. Two callouts:
  - The profile's spacecraft set their own routing (info): "This profile's spacecraft set their own routing, so
    these get none from it. Add their routes in Comms & routing after creating them."
  - The profile has no rules (caution): "This profile has no routing rules, so these spacecraft get no routes.
    Add a rule first if they need contacts." (`Add a rule` links to the profile's Routing section.)
Next: `Review batch`.

## Step 04 · Review (the board)
- **A1 Source** (collapsed summary + `CHANGE` link in header meta → step 01).
- **A2 Checks** (check rows `poll`: `[lbl] [sentence] [tag]`): Identity (unique names and SCIDs
  in this mission), Profile (all rows map to profile X, catalog rev N, framing and limits inherited),
  Routing (rules/routes generated), Orbit (new planes appear on the constellation), NORAD id (Note:
  optional now, needed for pass prediction). Tags `Pass` (nominal), `Note` (caution, row wash),
  `NO-GO` (crit, row wash). Header meta `4 PASSED · 1 NOTE`. Any NO-GO disables the commit with
  "Fix N NO-GO checks first".
- **Where checks come from** (as built): A2 runs against this mission's spacecraft in the browser, with the line
  "Checked against this mission's spacecraft in the browser; the server's dry run is below." **A5 Server checks**
  shows the server's dry run of the staged batch. The server's checks are the ones that count. The next free SCID
  for step 02 comes from the server (ux, audit S9: a browser guess can collide), which is a console item.
- An Orbit note (as built): "No planes set. The fleet matrix orders these by SCID until you add them." 
- **A3 Batch preview** (ApTable, 8 rows + `Show all 50`): Name (600) · SCID (mono) · NORAD (mono;
  `not set` caution) · Plane · slot (mono) · Profile · Routes (mono) · First state (`off` mark +
  `Awaiting first AOS`). Rows with notes get a caution wash. Footer "42 more rows · EARENDIL-509 to
  EARENDIL-550".

## A4 · What happens (aside, every step)
Tile grid ×3: `New SC 50` · `Routes 300` · `Fleet 550` (values update as steps change; `—` until
known). Numbered list (mono numbers): 01 what the commit does now, 02 what applying does, 03
"Each one shows as 'awaiting first AOS' on the console until it's heard, never as nominal."
- Option B wording **[U2]**: 01 "Creates 50 spacecraft and 300 routing rules in one step." 02 "They
  pin profile Block 2 v3." 03 as above. Commit: `Create 50 spacecraft` (primary, 46px). Plural rules:
  `Create 1 spacecraft`.
- Option A wording (board): `Stage 50 spacecraft`; "The batch joins the staged changes. Nothing is
  live yet."
- **Option A is live** (change sets are on), so the commit is `Stage 50 spacecraft`; option B's `Create …` is
  history.
- Secondary: `Back to <previous step>`; link `Download manifest template (.csv)`.

## After commit
Change sets are live (option A), so the commit **stages** the batch: `Stage 50 spacecraft` (`Staging…` while it
sends) → Setup › Changes, whose outcome reads "50 spacecraft staged. They're created when this change set is applied
as r6." (Changes.md). They're created when the set is applied, never at the commit. Partial failure is not allowed
(atomic batch). A refusal stays on Review, with its failure callout plus "Your draft is kept."
- **Not an organization admin:** a line under the header, "Only an organization admin can add spacecraft. You can
  prepare a batch here, but not create it." The commit is disabled with "Only an organization admin can add
  spacecraft." 

## Acceptance (for qa)
- The same four steps serve 1 and 50; a single spacecraft says "1 spacecraft".
- Clashes are caught before Review (inline) and again by the server at Review.
- `×` returns to the origin and the draft is restored on reopening.
- New spacecraft never appear as nominal anywhere in Ops before first contact.

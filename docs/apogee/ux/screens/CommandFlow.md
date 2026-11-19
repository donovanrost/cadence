# Commanding flow: Compose → Approve → Uplink & verify (phase 3)

Boards `CommandFlow`, `Compose`, `Approve`, `Uplink`. Owner: fe-ops. Data: `docs/apogee/plans/ops.md`
(M15–M26). Scope: DECISIONS #7 (two-person is policy-driven), #8 (**no waves or gates in the first
flow**), #6 (alarm lifecycle). J3 "Command a group" (`Command.md`) is the contingency entry into the
same request model.

**Principle: sent is not done.** A request passes seven stations: Compose (operator) → Check
(Cadence) → Approve (second operator) → Release (Cadence) → Radiate (station) → Acknowledge
(spacecraft) → Verify (telemetry). Only Verify turns it green. All three screens share a
**takeover header**: back/close · mono request line (`DRAFT · SAVED 02:44:31Z` while composing: no number, because a draft isn't a request yet (U25); after submit, the group's own identity as the server gives it) over a title ·
**ApStepBar of the stations** (current `●`, done `✓`, future `○`; `05 · 06 · 07` collapsed until
release) · clocks. Progress states are gray; outcomes carry status (ApStateTrail, CommandFlow M1).

Rules on every commanding screen (CommandFlow R01–R06): identity on every line (name + SCID +
profile; never `SCID —`); target by query; the catalog writes the form (types, ranges, units,
enums, and out-of-range can't be staged); show what will radiate; two people for anything the policy
marks; waves later (R06 deferred by #8).

---

## C1 · Compose (`M/commands/new`, routine entry)
Console takeover, three columns + a footer action bar:
```
┌ A Catalog (300, pane) ┐ ┌ B Command form ──────────────┐ ┌ D Targets (360, pane) ────┐
│ search · list ↑↓ ↵    │ │ B2 Per-target values (pane)  │ │ query · presets · matrix  │
└───────────────────────┘ └──────────────────────────────┘ └───────────────────────────┘
footer: Stack · N chips │ Release (choice) │ check summary GO/HOLD │ "NOTHING RADIATES WITHOUT A GO" [Send for GO]
```
- **A Catalog:** header meta `rev 15 · 61 CMDS`; search (name, subsystem, verb); `listbox` rows:
  mnemonic (mono 13/600), subsystem (mono `text-4`), classification tag (`HAZ`/`CRIT` short),
  one-line description (ellipsis). ↑↓ selects, ↵ adds to the stack with the current form values.
  No hits: `No commands match "x".`
- **B Command form:** header meta `SUBSYSTEM · OPCODE 0x4A1 · VERIFY WITHIN 60 s`; mnemonic +
  classification + description; one `arg` row per argument: name (mono 600) + type (`f32 · °C`),
  input by type (enum → `opt` buttons as a radiogroup; number → ApNumberField with unit + a range bar
  showing min…max and the value tick; out of range → caution border + message, Add disabled), and
  for numbers a `Same for all │ Per target` micro switch. Verifier line (`THERM.batt_setpoint =
  value ±0.1 within 60 s`) when the catalog defines one, else `No verifier: this command can't turn
  green` in stale text **[decision]**. Primary `Add to stack ↵`.
- **When targets differ** (U51, director's backlog, 11-14). Group by what's actually different: the verifiers,
  not just the revision number.
  - **Same verifiers on every target:** the line above, unchanged. When targets span catalog revisions, the meta
    reads `rev 14 · 15`, and nothing else changes.
  - **Verifiers differ:** a caution tag `VERIFIERS DIFFER` sits in B's header meta. In place of the single line,
    one row per distinct verifier set, largest group first:
    - Lead sentence: "Not every target checks this command the same way."
    - Rows: `THERM.batt_setpoint = value ±0.1 within 60 s` · `94 targets · rev 15`.
      `MODE.current = LOW within 30 s` · `EARENDIL-001, EARENDIL-003 · rev 14`.
      `No verifier: can't turn green` (stale text) · `EARENDIL-117 · rev 12`.
    - Up to 3 targets are named; above that, a count with `Show`. The text comes from the same verifier words as
      the single line.
  - **The command isn't in a target's revision:** that's C3's existing Catalog NO-GO, with names. It isn't shown
    here.
  - **D Targets:** when targets span revisions, each resolved target line adds `rev 14` (mono `text-4`) after the
    profile.
  - **Stack chip:** a command whose verifiers differ gets a caution `VERIFIERS DIFFER` at the chip's end, so the
    footer shows it after the form closes.
  - **Approve (C2)** shows the same grouped block for each command, because the reviewer must see it. **Uplink &
    verify:** U2 draws one plot per verifier point, each captioned with its targets.
  - Not a GO/HOLD check: it informs and doesn't gate (no HOLD, lead 11-14).
- **B2 Per-target values:** only when an arg is Per target. Fill buttons (`All from form · 8.0`,
  `Current + 2.0`, `Paste CSV`, `Clear`), table rows: mark + name (mono) · value cell(s) with unit
  (inherited = `text-4`, out of range = caution) · Now (current telemetry value) · context (mono
  ellipsis). CSV format hint `SCID OR NAME, THEN ONE COLUMN PER ARGUMENT`. Otherwise an info block
  explaining Per target.
- **D Targets:** search (`name, SCID, plane 07, stale…`) with hits list (`Add` / `Added` toggles) and
  `Add all N`; preset query buttons (`Planes 03–04`, `Block 1`, `All nominal`…) as `tp` tiles;
  picked chips (removable) when custom; clickable 500-cell matrix (selected `text-2` fill,
  stale hatched, caution amber, in contact white ring). Footer counts: `96 READY · ◇ 1 STALE · ▲ 1
  SAFE MODE · 2 EXCLUDED`, where excluded targets are listed with the reason in the Check results.
- **Footer action bar:** stack chips (`01 HEATER_SET zone=BATT setpoint=8.0 ✕`, empty hint), Release
  `choice` (`Next AOS · At time · Manual`; `At time` opens ApTimePicker), live check summary
  (`IDENTITY GO · CATALOG GO · CONFLICTS GO · TWO-PERSON HOLD`, from the server preflight), next-step
  caption (`NEXT: SECOND GO FROM AN OPERATOR` when policy requires it, else `NEXT: RELEASE AT AOS`),
  primary `Send for GO · 96 targets` or `Release · 1 target` when no approval is needed. Plus a
  required **reason** (one line, prefilled from context) in a popover before sending.

## C2 · Approve (`M/commands/:requestId/review`)
Console takeover:
```
┌ Q Waiting on you (280) ┐ ┌ main (scrolls): request header · A1 What changes · A2 Re-checked ┐ ┌ D Your call (340) ┐
│ queue of requests      │ │ A3 What will radiate · (A4 Release plan)                          │ │ decision · note   │
└────────────────────────┘ └───────────────────────────────────────────────────────────────────┘ └───────────────────┘
```
- **Q Waiting on you:** requests where *you* can give the GO, oldest first: mono `DONOVAN R.` + age (there are
  no request numbers; never invent one, U25), mnemonic (mono 600, `HAZ` tag), scope sentence. Your own requests appear at
  the end as a non-clickable note: "You can't approve your own request. Waiting on Ana or Owen."
  Also reachable from Now (P2 "awaits your GO").
- **Request header:** title = the author's reason as a headline, classification tag, the author's
  justification quoted with mono byline.
- **A1 What changes:** for set-value commands: `5.0 → 8.0 °C · ON 98 SPACECRAFT` (readout 34px),
  histogram of current values across targets, and callouts for targets whose value was hand-set
  before ("EARENDIL-117 and -144 were hand-set to 6.0 °C on 14 Sep (“Thermal trim”, Ana R.). This overwrites
  that."). For non-value commands: the stack as mono lines.
- **Targets with their own values** (lead, safety; api f1bed1880: `commands[].per_target` gives a target a
  **complete** value set that **replaces** the command's shared values; it isn't merged). An approver sees exactly
  what each target gets (U20).
  - **Readout:** `5.0 → 8.0 °C · ON 95 SPACECRAFT` for the shared value, then a second line `3 WITH THEIR OWN VALUES ·
    8.5–9.5 °C`. When every target has its own values, there's no shared line: `5.0–6.2 → 8.0–9.5 °C · EACH OF 98
    WITH ITS OWN VALUES`.
  - **Stack line:** the shared values as today, then a neutral tag `3 OWN VALUES` (no tag when there are none).
  - **Own-values table** under the command: Target (mono) · one column per argument, with the unit. A value that
    differs from the shared one is in `text` weight 600; one that equals it is `text-4`; an argument the override
    leaves out reads `default` in `text-4` (never a dash). The first 8 rows show in target order, then `Show all
    50`. Out-of-range values keep B2's caution.
  - **1 target:** no shared line and no table, only its values in the readout (`5.0 → 8.5 °C · EARENDIL-312`).
    With **50 targets** and 3 overrides: the shared line, `3 WITH THEIR OWN VALUES`, and a 3-row table. With 50
    overrides: the table's first 8 rows and `Show all 50`.
  - A3's header meta names the difference: `SAME FOR ALL 98 EXCEPT SEQ AND CRC; 3 TARGETS ENCODE THEIR OWN VALUES`.
- **Uplink & verify:** a target row with its own values shows them on its command line (mono, as on Approve), with
  the tag `OWN VALUES`. The others need nothing extra.
- **A2 Re-checked at review:** the preflight re-run at open time (`ck` rows, GO/HOLD/NO-GO), incl.
  `Excluded · 163 stale · 188 safe mode · GO −2`. Header meta `6 GO` in nominal text.
- **A3 What will radiate:** the encoded packet as byte boxes (`by`: hex 15px mono, field name,
  decoded value), header meta `19 BYTES · CCSDS TC · SAME FOR ALL 98 EXCEPT SEQ AND CRC`.
  **Depends on encode preview (M24):** until then show the decoded stack only and the header meta
  `ENCODED PREVIEW NOT AVAILABLE` (CommandFlow R04 is then unmet; flag in qa).
- **A4 Release plan:** **omitted in v1** (#8, waves). Show instead a one-line release summary
  ("Each target at its next AOS · first 03:10Z FBK").
- **D Your call:** ApOption radios: `GO as requested` · `GO, excluding 117 and 144` (only when the
  checks flagged targets) · `Send back` (returns to Compose with your note) · `NO-GO` (closes and
  logs why). Note to author (required for send back / NO-GO / exclusions). Request log (event rows).
  Primary `Sign GO · 96 targets` (commit size); caption `RE-AUTHENTICATES · ABORT STAYS OPEN TO BOTH
  OF YOU` (re-auth only if the backend requires it).

## C3 · Uplink & verify (`M/commands/:requestId/uplink`, live)
Console takeover. Header right adds `Abort remaining` (danger, M20). There's no Pause: there's no group
hold server-side, and none is planned (lead, api-ops).
```
lbl "BATTERY HEATER SETPOINT · 5.0 → 8.0 °C"   h1 "34 of 96 verified · 2 need you"
pipeline tiles ×6: Queued for AOS · Radiating · Executed · Verified · No ACK · retry · Verify failed
┌ U1 Targets matrix ┐ ┌ N Needs you (aside, pane) ┐
├ U2 Verifier plot  ┤ │                           │
├ U3 Event stream   ┤ │                           │
└───────────────────┘ └───────────────────────────┘
```
- **h1:** `<verified> of <targets> verified`, then ` · N need you` in caution when > 0. All verified:
  `96 of 96 verified` + nominal tag `■ VERIFIED`. Commands without a verifier: `96 executed · not
  verifiable` (stale tint); never green.
- **Pipeline:** ApStatTiles with a 3px bar under each value (share of targets); Verified gets the
  nominal fill, No ACK caution, Verify failed crit; the rest gray (progress is gray). Captions are
  specific: `Next 4 at FBK 04:39Z`, `EARENDIL-171 · AWA`, `Verifier window open`,
  `THERM.batt_setpoint = 8.0`, `Retry 1 of 3 queued`.
- **U1 Targets:** one cell per target in plane rows (`um` grid): verified `nominal-dim`, executed
  `text-3` fill, radiating white + ring, queued `text-3` outline, no ACK caution fill, failed crit +
  ring, excluded dashed. Legend with every state word. (Wave states return with #8.)
- **U2 Verifier:** the verifier point over the request window, one faint line per target, commanded
  value as a dashed white line, the tolerance band; header meta `34 STEPPED TO 8.0 · 1 DID NOT`.
- **U3 Event stream:** mono log rows `time · target · event` newest first (RADIATING, EXECUTED with
  command counter, VERIFIED with latency in nominal text, VERIFY FAILED with read vs expected in crit,
  NO ACK with the retry plan).
- **N Needs you:** one card per target that needs a human: mark, name link, state tag, a plain
  explanation of what happened ("The command arrived and executed (counter +1), but the setpoint still
  reads 5.0 °C a minute later."), actions (`Re-send at 04:47Z AWA`, `Open 152`). Automatic recoveries
  are listed with "Nothing to do unless it fails again." Empty: nominal callout "Nothing needs you."
- **Gate panel G:** omitted until waves (#8).

## States
Draft autosave (Compose), preflight `CHECKING…`, approval pending (Uplink reachable read-only:
"Waiting for a second GO"), rejected/sent back (callout with the note, `Edit and resend`), expired,
aborted (per-target trail ends in gray `ABORTED`). Live screens follow the connection-lost rule (stale
callout, stale tint on live values).

## Acceptance (for qa)
- Out-of-range values can't reach the stack; enums only offer catalog values.
- You can never approve your own request; the policy decides when a GO is needed and the UI says so.
- Nothing turns green without a verifier reading; unverifiable stays stale-tinted.
- Approver sees the encoded packet once M24 exists; until then the header says it's unavailable.

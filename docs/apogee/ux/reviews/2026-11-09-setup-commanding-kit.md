# Review: fe-setup round (ce8d83f6, c504641c, dabd101b, 995ba6d0) + lead's commanding kit (2026-11-09)

## fe-setup
- **Profile detail:** good. Schema-only fields, the #19 info callout, `INHERITED BY 500`, sections
  as tabs (fine instead of a left local nav), `Not set · default 0 bytes` reads honestly.
  Small: when change sets are live (`CONFIG r1` now shows), the subline's last change should say
  `last changed in r1` rather than `v1 · 11-08 21:54Z`.
- **Catalog index + import run:** good. Verdict caution callout, `48 ITEMS → 1 LINE` grouping,
  `× 48`, an honest info callout for the diff.
  **Fix:** the breadcrumb uppercases the file name (`DEMO_SPACECRAFT.YAML`). File names are literal
  ids (U17): mono, original case (`demo_spacecraft.yaml`).
- **Pass-1:** #5 verified on Readiness at 390 (tile links answer taps outside their 26px box), and #6,
  #10 and Install accepted per commit. #8 strings wait on api.
- **Wizard staging (dabd101b):** not exercised: staging writes to the shared dev DB. I'll review it
  on a throwaway mission or with intercepted calls next.

## lead: commanding kit (/console/kit K3)
Faithful: station bar with ✓/●/○ and `05 · 06 · 07` folded; Uplink variant with `01–04` folded
and 05–07 current; check summary line (`CONFLICTS CHECKING…`); pipeline tiles with gray progress
bars, nominal bar for Verified, caution top bar + value for No ACK; ApNumberField with unit and range
tick; hollow-radio ApDecision.
- Small: event rows should tint the **outcome word** (`VERIFIED` nominal-text, `NO ACK` /
  `VERIFY FAILED` caution / crit text), not just the mark (CommandFlow C3, U3).
- Takeover question → **U19: takeover routes replace the shell top bar**; org/mission move into the
  takeover header's context line.

## Wizard staging (dabd101b), exercised with an intercepted `POST …/config/stage`
Walked Source → Identity (3 × SCID 601) → Orbit (Not now) → Review → `Stage 3 spacecraft`. The
review is honest ("Checked against this mission's spacecraft in the browser. Cadence checks again
when the batch is created."), the A4 copy reads as staging, and the payload is one change with 3
create ops. Success routes to Staged changes: good, the batch is seen in context.
- **Fix:** a malformed or unexpected server reply shows the raw decoder text as the error
  (`data.change_id: expected string`). Use the console's standard wording, and say what happened to
  the data: "The server's reply wasn't understood. Nothing was staged; your draft is kept." + Retry.
  Generally, every stage/apply failure must say whether anything changed.
- **Add:** on arrival at Staged changes after a stage, a one-time nominal callout: "3 spacecraft
  staged. They're created when this change set is applied as r2."
- fe-setup's note on the profile subline is right: `last_change.revision` is null until profile
  edits go through change sets, so `v1 · date` is the honest text. Accepted.

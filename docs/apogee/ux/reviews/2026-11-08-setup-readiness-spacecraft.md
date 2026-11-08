# Review: Setup › Readiness + Spacecraft list (fe-setup, 46f6c31c), rendered 1440×900

Readiness was checked twice: on the live server (honest "Readiness not available" state) and with
the requested shape injected via request interception (board-like fixture: 3 ready, caution, stale,
not set up; 4 findings; 3 recent changes).

**Verdict: Readiness matches Setup.md and the board closely.** Verdict h1 + `■ 0 BLOCKERS` tag,
tile grid with hairline gaps and state top bars, U3 marks and order, nominal "No blockers" callout,
optional row with dash mark, R2 in `ev` rows, `AUDIT LOG →`. The not-available state is honest and
offers `Check again`. The Spacecraft list is clean: filter in the panel header, `500 OF 500`,
right-aligned tabular SCID, profile + `v1` in `text-4`, `off` mark + "Awaiting first AOS".

## Fixes
1. **R2 first column overflows:** `station` runs into the time (`station10-09 11:47Z`) and `rev 14`
   wraps. → show `version_label` when present, else a short kind chip in the Catalog `kind` style
   (mono 10px boxed: `PRF`, `CAT`, `STN`, `APP`, `SC`); widen the column to 56px.
2. **Subline is missing the latest change:** Setup.md appends ` · <latest change> by <actor>`
   when `recent_changes` exists (`· Block 1 framing … · 10-19 02:29Z by Donovan R.`).
3. **Action verb for `not_set_up` apps:** `Install`, not `Open app` (Setup.md R1).
4. Spec corrections from domain: drop any "default protocol behavior" finding copy (a retired
   concept). My fixture used it as a placeholder and Setup.md now notes it.
5. Spacecraft list (later, when /spacecraft lands): add `Routes` and `Configuration` (`active v3 ·
   draft pending review`) columns from the S shape; keep `Last heard`.

## Resolved (re-checked 2026-11-08 22:12Z)
Items 1-3 fixed in d53a554e. Directory now on /spacecraft with Routing rules + Setup columns. "Ready" as a quiet nominal mark + word (not 500 tags) accepted: it reads as earned setup state without shouting. Item 5 done.

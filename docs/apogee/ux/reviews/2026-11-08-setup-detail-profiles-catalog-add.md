# Review: Spacecraft detail, Profiles list, Catalog index, Add spacecraft (fe-setup), 1440×900 live

**Verdict: all four follow the specs and are honest about missing backends.** Detail uses the
Profile-style panels (U6) with `Open in Ops →`, D5 says configuration arrives with change sets,
Profiles shows "Catalog · Set per spacecraft" instead of inventing a profile catalog, and Catalog
has a clean not-available state. Add spacecraft's takeover header + step bar + A4 aside match S2.

## Spacecraft detail (9b2c09c9)
1. **D4 header:** the `COMMS & ROUTING` button sits jammed after the title. Panel-header actions are
   the right **meta link** (`COMMS & ROUTING →`, readout), next to/instead of `2 ACTIVE`.
2. **D1 Readiness rows** read redundantly ("SCID 1 / The spacecraft has a SCID."). → use the check
   row (`poll`) from AddSpacecraft A2: `[IDENTITY] SCID 1, unique in this mission [PASS]`, `[PROFILE]
   Earendil Block 1 — Demo, latest version [PASS]`, `[ROUTING] 2 active rules [PASS]`,
   `[TELEMETRY] Last heard 22:30Z [PASS]` / `Awaiting first AOS [NOTE]`.
3. **Format consistency:** orbit reads `Plane 1 · slot 1` here but `P01 · 01` in the list. One format
   everywhere, mono: `P01 · slot 01` (Investigate uses the same). Last heard needs its distance from
   now (design-language §4): `11-08 22:30Z · T+1m`.

## Profiles list (7e8a864c)
4. Fine for v1. When profile detail lands, the Name cell is the link (readout, hover bright).
   Add `Overrides` once the model has them (Profile.md list).

## Catalog index (fa15d241)
5. **Dead-end primary:** `Import a new revision` (primary, white) leads to a "Not built yet"
   placeholder. A primary must do its job. → hide it until the import screen ships, or make it
   secondary with `disabledReason` "Catalog import isn't available in the console yet."

## Add spacecraft (6d51ca92)
6. **Mode switch loses its state in the takeover:** neither OPS nor SETUP is active. Takeover is
   still Setup mode → keep SETUP active (lead's shell, `meta.mode`).
7. **Step bar:** the current step drops its number (`● SOURCE` vs `02 IDENTITY`). Board: `● 04
   Review` → `● 01 SOURCE`.
8. **Profile radio** renders as a solid white disc while unselected (native radio, light scheme),
   which reads as selected. → `accent-color: var(--color-readout)` + `color-scheme: dark` on the
   input (ApOption), so unchecked is hollow.
9. **One profile:** preselect it (still visible, still changeable) so the first step isn't a
   formality.
10. **Disabled `Continue to identity`** needs its reason visible, not only in `title`: a caption under
    the button (mono 11, `text-4`): `PICK A PROFILE OR A MANIFEST`.

## Closed (2026-11-08 22:37Z, 2a8685b3 + lead)
All 10 items verified on screen: D1 check rows with PASS tags, D4 meta link, `P01 · slot 01`, last heard `· T+19s`, catalog import hidden, sole profile preselected, visible reasons under disabled Continue/Create ("the batch create endpoint is being built"), SETUP lit, numbered current step, hollow radio. Review closed.

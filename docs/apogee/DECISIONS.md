# Scope decisions

Decided by the user (U) or the director (D). Newest last. Ask the director before reversing one.

| # | Decision | By | Owner |
| --- | --- | --- | --- |
| 1 | **Mission change sets: build them.** One mission-wide config revision (`rN`), staged changes, diff, atomic apply as `rN+1`, audit (who/when/why), rollback. Setup ships v1 on per-entity versions (option B), behind a seam so it switches to change sets when the model lands. Don't fake `rN` or the staged bar before then. | U | domain (model), api (endpoints), fe-setup (UI) |
| 2 | **Roles: keep `organization_admin` / `member` for now.** A Cedar-based role system is planned for later. Don't build a roles model. UI shows real roles, and permission checks go through capabilities from the session bootstrap so Cedar can replace them later. | U | api, fe-setup |
| 3 | **Routing rules move to the Spacecraft Profile** and are materialized per spacecraft, with per-spacecraft overrides. Model change in `apps/cadence`, including migrating existing per-spacecraft rules. | U | domain, api, fe-setup |
| 4 | **Propagation (ops D1): defer.** Ground track, umbra, eclipse and AOS-prediction panels show an honest "not available" state for now. Later: server-side propagation (the user's `ex-orbital-dynamics` project is the candidate). No flight dynamics in the browser. | D | fe-ops |
| 5 | **Procedures (ops D2): defer.** Omit the recommended-procedure panel. | D | fe-ops |
| 6 | **Alarm lifecycle (ops D3): build a minimal one** (ack, assign, hand-off note, auto-clear when back in limits), because J2 and J6 depend on it. Ships after the Now/Investigate read endpoints. | D | domain (model), api, fe-ops |
| 7 | **Two-person rule (ops D4): policy-driven.** Default: second GO required for hazardous/critical commands and for fleet-wide (multi-target over a threshold) requests; non-hazardous single-target commands don't need one. Mission-configurable later (it will become a Cedar policy). | D | api, fe-ops |
| 8 | **Command waves/gates (ops D5): phase 3+.** Not in the first commanding flow. | D | fe-ops |
| 9 | **Catalog impact/used-by: phase 2.** v1 diff shows added/changed/removed/breaking from the catalog revisions alone. Cross-references to queued commands/limits/dashboards come later. | D | api, fe-setup |
| 10 | **Hook policy:** css-frozen guard removed repo-wide; pre-commit `stash = "none"`; team commits with `HK=0 … -- <paths>` after their own checks (see TEAM.md section Git). | U/D | everyone |
| 11 | **Dashboards come last.** No dashboard work until everything else ships. Until then the console just links to the existing dashboard pages under Ops > Telemetry > Dashboards. Revisit at the end (rebuild in the console vs. keep the existing engine). | U | ux, fe-ops |
| 12 | **Platform admin (`/admin`) stays on the existing host**, linked from the account menu for users with the `platform_admin` capability. | D | ux, lead |
| 13 | **Change sets: freeze while in review**; one shared set per mission. | U | domain |
| 14 | **Change-set reviewer must be distinct from every author** in the set. | U | domain, api |
| 15 | **Profile limits and VC/FEC/randomizer framing fields are out** of this phase. Limits are read-only with a note; framing fields only appear if the pipeline uses them. | U | domain, fe-setup |
| 16 | **domain designs approved; build change-sets P1.** Review notes: `docs/apogee/domain/review-director-1.md`. | U | domain |
| 17 | **Alarm episodes come from both sources, labeled by source:** catalog monitoring (live) and ground limits (batch). Ground-limit episodes show when they were last evaluated ("evaluated 3m ago"), and the UI never implies they're live. Escalation clears the ack (ISA-18.2). Assign to any mission member. Live ground-limit evaluation is a later item. | D | domain, api, fe-ops |
| 18 | **Lift the 500-SC / 4 MiB activation snapshot cap** before P2 generation kinds. It's an existing bug: a 550-spacecraft fleet can't be activated even through the old review. | D | domain |
| 19 | **The profile feeds ingress framing in P2.** Profile `frame_parameters` become what decode actually uses (today transport config sets `frame_size`). Until then, Framing on the Profile page is read-only with an honest note. | D | domain, fe-setup |
| 20 | **domain order after change-sets P1:** (1) minimal alarm lifecycle (unblocks Investigate Ack/Assign, the Now queue, Mobile), (2) snapshot-cap restructure, (3) profile routing + overrides (P2). Meanwhile fe-setup builds the Changes screen (staged bar, review, revisions) on P1. | D | domain, fe-setup, fe-ops |
| 21 | **Hired api-ops** to own Ops/contacts/commanding endpoints (queue: M6 → M17 → M7+M21 → M16/M18/M20 → events, M23). api keeps session, Setup, change sets, readiness. fe-ops builds Timeline + Telemetry explore on existing data meanwhile. | D | api-ops, api, fe-ops |
| 22 | **Alarm lifecycle endpoints move to api-ops** (from api), right after M17 and before M7/M21: ack/assign/hand-off/notes + episode reads + channel pushes, per `docs/apogee/api/alarms.md`. Point units come from catalog declarations (join them in the read; don't return nil). | D | api-ops, api |
| 23 | **Fleet snapshot: interim cap lift accepted** (740bc19c: 2,000 SC / 16 MiB; review batches of 500). **The proper restructure** (`docs/apogee/domain/fleet-snapshot.md`) goes first in profile-routing P2, before change sets produce generations. | D | domain |
| 24 | **Scheduling (K0–K3) goes to lead**, who has capacity now. Plan first (`docs/apogee/plans/scheduling.md`), using the existing contact-workspace API and `frontend/modules/planning-and-contacts` as domain reference. Pass prediction stays deferred per #4, so K0 explains where passes come from (provider/booking data), not orbit propagation. Endpoints via api-ops, after its current queue. | D | lead, api-ops, ux |

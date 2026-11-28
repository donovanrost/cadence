# Setup mode: per-screen data plan

Owner: **fe-setup**. Status: draft 1 (2026-11-08). Boards: `Setup` (S1), `AddSpacecraft` (S2),
`Catalog` (S3), `Profile` (S4), `People` (S5), `SetupJourneys`.

`L` = `apps/cadence/lib/cadence`. "Bridge" = the application-host query bridge
(deleted in #672, DECISIONS #116). Bridge payloads are presentation DTOs (CSS classes,
breadcrumbs, tone strings), so the plan asks **api** for purpose-built `/api/v1` JSON,
reusing the underlying `L/reads/*` and stores. "Missing" means no backend data exists today.

## Build status (2026-11-09, late)

| Screen | Route | State | Data |
| --- | --- | --- | --- |
| S1 Readiness | `setup` | **live** (unknown fix kinds tolerated) | R |
| Spacecraft list / detail | `setup/spacecraft[/:id]` | **live** | S, SD |
| S2 Add spacecraft | `setup/spacecraft/new/:step` | **live**: server dry run at review, stages the batch | K preview + stage |
| Profiles / S4 Profile | `setup/profiles[/:id/:section]` | **live**; framing read-only (#19); routing rule editor + override reset stage live (domain P2) | P, PD, K |
| S3 Catalog index / import run / upload | `setup/catalog[/import[/:id]]` | **live** (qa ran a real upload) | C1, C2, C3 |
| Changes + Revisions | `setup/changes`, `setup/revisions[/:n]` | **live**; rollback (#49) on the revision page: preview → stage as a new change set | K, rollback |
| Ground stations | `setup/stations[/:id\|new]` | **live**: edit and add through change sets; U25 suggested codes with Confirm (stages a code change) | G1 + kind schema |
| Comms & routing | `setup/comms[/transports[/:id]]` | **live**: transports editable; routing rules as groups (pass-2 #10) with a group's rules below (`?group=`), read-only (#3) | T1, T2, groups, transport detail |
| Data sources | `setup/data-sources` | **live** | D1 |
| Apps | `setup/apps` | **live**; platform apps always on; install/disable/uninstall direct (change seam kept) | A1 |
| S5 People & access | `org/people` | **live** (members, invitations, invite, service identities) | O1, O2, O3; O4 with api-ops |
| Org missions | `org/missions` | **live**: session rows + fleet size and worst state (pass-2 #11) | session, org missions |
| Contact planning (#27) | `setup/contact-planning[/policy]` | requirements built; policy/templates wait for CP2/CP3 | CP1-3 |
| Mission / org settings | `setup/settings`, `org/settings` | **live**: sections editable (direct save, per-section version), source per field, Reset to inherited, locked read-only | ST1 |
| Audit log | `org/audit` | **live**: range, kind and mission filters, Load older, grouped repeats | AU1 |
| Provider accounts | `org/provider-accounts[/:id\|new]` | **live**: list, detail, Test reference, add, rename, replace reference, remove (blocked while used). Settings edit waits for an account detail read | PA1 |
| K2 Re-plan (#43) | `contacts/replan[/:stationId]` | **live**: propose around lost bookings/outage; Apply held for qa (after 004's 18:26Z pass) | S5, S7, S8 |
| K3 Close the books (#43) | `contacts/review` | **live** on S9: h1 + freshness, strip, R1–R4. R4 shows the first 100 (cursor is in `meta`); downlink tile waits for summary volume totals | S9 |

Shapes requested from api: `setup-shapes.md`. Contracts: `docs/apogee/api/setup.md`.

---

## 0. The cross-cutting gap: one mission revision and staged changes

The canvas assumes **one mission-wide configuration revision** (`CONFIG r5` in the top bar), a
**staged changes bar** on every Setup page ("2 changes: 50 new spacecraft, catalog v15 import ·
Review & apply as r6"), and history with who/when/why and rollback.

What exists instead is **per-entity versioning**:
- Spacecraft Profile (`SpacecraftType`) is versioned and spacecraft pin `{type_id, version}`.
- Transports are versioned.
- Each spacecraft has a configuration document (catalog revision, telemetry/commanding enabled,
  protocol) with draft → review → activate and an approval policy (`L/governance/activation_policy.ex`).
- Catalog has revisions (`revision_number`, label, notes).
- Routing rules have a per-rule event log.

**There is no mission change set, no mission revision number, and no cross-entity apply.**

**Decided (DECISIONS.md #1):** change sets will be built (domain owns the model, api the
endpoints). Setup v1 ships on per-entity versions (option B, ux U2) **behind a seam**, with no fake
`rN` or staged bar before then.

**The seam (frontend).** Every Setup write goes through one feature module, `setup/changes`, with
typed operations (`createSpacecraftBatch`, `saveProfileVersion`, `requestActivation`,
`setCatalogRevision`, …). Each returns a discriminated outcome:
- v1: `{ kind: "applied", entity, version }` or `{ kind: "pending_review", entity, draftVersion }`.
- Change sets add `{ kind: "staged", changeSetId, opCount }`.

A `useMissionRevision()` composable returns `{ status: "unavailable" }` in v1, so the top bar and
staged bar render nothing. When change sets land it returns `{ status: "available", revision,
staged }`, and the bar and `rN` appear without touching screen code. Commit labels follow the
outcome: v1 "Create 50 spacecraft" / "Request activation for 50 spacecraft", then "Stage 50
spacecraft".

**Other decisions that shape Setup:**
- **#2 Roles:** stay `organization_admin` / `member`. UI gating uses session capabilities only,
  never role names, so Cedar can replace it.
- **#3 Routing rules move to the profile**, materialized per spacecraft, with overrides. This
  unlocks S4 P2 and P3 once domain lands it.
- **#9 Catalog impact:** phase 2. The v1 diff covers added, changed, removed and breaking.

---

## S1 · Readiness (`/console/:org/:mission/setup`)

**Components:** page header (mission label, verdict h1, blocker tag, subline); area tile grid
(6 tiles: name, status tag, big number + unit, one-line detail); Findings panel R1 (grouped rows:
shape, title, body, action button/link); Revisions panel R2; header buttons (Add spacecraft,
Import catalog).

| Area / element | Data | Source today | Gap |
| --- | --- | --- | --- |
| Fleet tile | total spacecraft, # profiles, missing SCID, missing profile, missing route | `SpacecraftStore.fleet_summary/2` (total, missing_scid, missing_profile, profile_version_counts) | missing-route count is not in the summary. Comms validation has it per spacecraft. |
| Catalog tile | current revision label/number, declaration count, staged/unapplied import, # profiles using it | `Catalog.latest_revision`, `imported_definition_count`; spacecraft configuration docs reference `catalog_revision_id` | "profiles using it" is wrong in the model: **spacecraft configurations** use a catalog, not profiles. Count spacecraft per catalog revision instead. |
| Comms & routing tile | # rules, # routes, verdict | `RoutingRuleStore.list_*`; comms validation findings (`L/reads/comms/pages.ex` `validation_findings`, owner/severity/title/body) | There is no rules→routes distinction, because a rule is per-spacecraft. Show "N routing rules · M spacecraft without a route". |
| Ground stations tile | # stations, # antennas, degraded state | `GroundStationStore.list` | **Missing:** antennas and station health/degraded. Show the count only, with health shown as unknown. |
| Data sources tile | # sources, stale ones (last received vs expected) | `L/management/data_sources.ex` inventory, health and watermark events | Need a decoded per-source `{status, last_received_at, expected_interval}`. "Expected every 5m" may not exist. |
| Apps tile | installed of available, missing ones with consequence text | `Reads.Applications.Inventory`, `ApplicationInstallations.list_for_mission` | The consequence text ("ground limit checks are off") needs a per-app description field. |
| Findings R1 | mission findings grouped by cause: severity (blocker / caution / stale / not set up / optional), title, body, count, fix target (route) | Comms validation findings + spacecraft readiness checks (`L/reads/spacecraft/readiness.ex`, per spacecraft only) | **Missing:** one mission-level readiness endpoint that aggregates and **groups by cause** with counts, and a typed `fix` link target (profile / rule / station / source / app). Today readiness is per spacecraft. |
| Revisions R2 | last N revisions: number, at, summary, actor | — | **Missing** (see §0). Under option B, show a "recent changes" feed from `OperationalEvents` + routing-rule events + app install events if api can unify them, or drop the panel. |
| Verdict | "Ready for operations" / "N blockers" | derived from findings | Derive in the client from the decoded findings (blocker count). |

**Proposed endpoint:** `GET /api/v1/missions/:mission_id/readiness` (api conventions: `docs/apogee/api/README.md`; contracts in `docs/apogee/api/setup.md`) →
`{areas: [{key, status, count, unit, detail}], findings: [{id, severity, cause, title, body,
affected_count, fix: {kind, id} | null}], verdict: {blockers, cautions, suggestions}}`.

---

## Spacecraft list (`/setup/spacecraft`, rail 02; implied by the canvas)

**Components:** table (Name link, SCID, Profile + version, Routes, Config state, Readiness),
filter box, empty state, "Add spacecraft" action.
**Data:** `SpacecraftStore.list_spacecraft_page` + `Reads.Spacecraft.Directory` (the ready flag at
`directory.ex:172`). **Gap:** a clean JSON list with paging, sorting and `q`, plus a per-row route count.

## Spacecraft detail (`/setup/spacecraft/:id`)

Reuse the profile page layout: identity (name, SCID, NORAD?), pinned profile/version, configuration
(active vs draft, catalog revision, review status, approvals), routing rules, overrides.
**Data:** `Reads.Spacecraft.Configuration` (document, active version, review, approval permissions),
`list_routing_rules_for_spacecraft`, readiness. Actions: save draft, request activation, approve
(existing `Cadence.Control.SpacecraftConfiguration.submit/decide`). **Gap:** JSON + action endpoints.

---

## S2 · Add spacecraft (`/setup/spacecraft/new`, full-page wizard)

**Components:** wizard header (close ×, step list `<ol>` with aria-current, config draft meta);
A1 source (segmented radio: From a profile | From a manifest; CSV drop zone with column mapping
chips); A2 checks (label · sentence · Pass/Note tag); A3 batch preview table (first 8, "show all");
A4 summary aside (counts, what-happens steps, primary "Stage N spacecraft", template download).
Steps: 01 Source, 02 Identity (count + naming pattern + SCID range), 03 Orbit & routing, 04 Review.

| Need | Source today | Gap |
| --- | --- | --- |
| Profiles to pick from (name, version, catalog, protocols) | `SpacecraftTypeStore.list_spacecraft_types`, `Reads.Spacecraft.Profiles.directory` | JSON endpoint |
| Create one spacecraft | `Spacecraft.Identity.action/5` via bridge `cadence.spacecraft.new` validate/save | JSON endpoint |
| **Batch create** (N from pattern, or CSV manifest) with server-side validation | — | **Missing:** `POST .../spacecraft/batch:validate` (unique names/SCIDs in mission, profile exists, per-row errors) and `POST .../spacecraft/batch` (atomic create). |
| Proposed SCIDs (next free range) | — | **Missing:** next-free-SCID suggestion, or have validate return clashes and let the client propose. |
| NORAD id, plane, slot | — | **Missing fields.** The spacecraft has `metadata` only. Ask api whether `norad_id` / orbit plane / slot should be first-class or stay metadata. |
| Routes generated per spacecraft | Routing rules are per spacecraft | **Missing:** profile-level routing (see S4). Under v1, the Routing step lets the user pick transports/stations and the batch creates per-spacecraft rules. |
| "Awaiting first AOS" first state | — | Ops concept. fe-ops owns how the console shows "never heard". |

---

## S3 · Catalog import + diff (`/setup/catalog`, `/setup/catalog/import`)

**Components:** breadcrumb; h1 "Catalog vN → vN+1" + file line (name, format, size, validation);
stat strip (Commands a→b, Telemetry a→b, Unchanged, Breaking); C1 diff panel (tablist filters
All/Breaking/Added/Changed/Removed; rows op · kind · name · change · used-by; sorted by risk);
C2 impact panel; C3 rollout radio + stage button. Plus a catalog index (databases → revisions →
import runs) for rail 04.

| Need | Source today | Gap |
| --- | --- | --- |
| Catalog databases, revisions, import runs | `Catalog.list_*`, `Reads.Catalog.*`, REST `catalog_artifacts` / `catalog_import_runs` (bearer only) | Session JSON endpoints |
| Upload file → import run | LiveView `allow_upload` → `Catalog.Upload.import_revision` (50 MiB, auto-detect importer) | **Missing:** a multipart `POST` for the SPA, and import-run status via a Channel (`catalog:mission:<m>:import_runs` PubSub already exists). |
| Validation result | import run: status, diagnostics (error/warning/info; code, message, path), failure_reason | JSON shape |
| Commands vs telemetry counts | only the total `imported_definition_count` | **Missing:** a per-kind count. |
| **Diff** between revisions (added/changed/removed per declaration, with field-level change text) | — | **Missing entirely.** A server-side diff of two mission-model revisions. |
| "Breaking" classification | — | **Missing:** a rule set (arg type/unit change, new required arg, removed in-use item). |
| Impact / used-by (queued uplinks, procedures, limits, dashboards) | — | **Missing:** cross-references from declarations to queued commands, procedures, limits and dashboards. Likely a phase-2 item. |
| Rollout to a subset | spacecraft configuration `catalog_revision_id` per spacecraft, via draft/review/activate | **Missing:** a bulk "set catalog revision for these spacecraft" action. Profiles don't carry a catalog today. |

**v1 proposal:** import + validation + diagnostics + revision list now. Diff when api can supply it
(diff v1 = added/removed/changed by name and kind, with no impact). Hide the impact panel until
cross-refs exist rather than show it empty.

---

## S4 · Profile (`/setup/profiles`, `/setup/profiles/:id`)

**Components:** breadcrumb; h1 + "N spacecraft inherit · M override · catalog · last changed";
header actions (Duplicate as new profile, History); local section nav (Framing, Routing, Limits,
Commanding, Catalog, Overrides · N); P1 key/value form panel with "edited" field state (old value
struck, new value input); P2 routing rule (FOR EACH / AND EACH / ROUTE / NAME template + generated
samples); P3 overrides list (spacecraft link, what differs, since, Reset); P4 staged-edit aside
(field path, − old / + new, changes N / keeps M, caution callout, Stage / Discard).

| Need | Source today | Gap |
| --- | --- | --- |
| Profile list + detail (name, version, lifecycle, protocols, frame_parameters, applications) | `SpacecraftTypeStore`, `Reads.Spacecraft.Profiles.directory/detail` | JSON endpoints |
| Inherit count (spacecraft per profile/version) | `fleet_summary.profile_version_counts` | per-profile filter |
| Versions/history | `list_spacecraft_type_versions` | JSON |
| Edit a profile → new version | `ProfileCreation.action/4` (create). Edit-as-new-version unclear | **Ask api:** can a profile be edited into v+1, and how do pinned spacecraft move to it (they pin a version)? |
| Framing fields (TM frame length, VCs, FEC, COP-1, randomizer) | `downlink_protocol`, `uplink_protocol`, `frame_parameters` map | Need the typed schema of `frame_parameters` for the form. |
| Limits / Commanding sections | Limits is an app (`applications` map, app defaults) | Probably render the per-app defaults from `applications`. Needs a typed schema. |
| **Profile-level routing rule generator** | Routing rules are per spacecraft (`spacecraft_id`, `transport_id`) | **Missing / model change:** this is the core fix for "1,000 rules all named the same". Ask api + director whether rules move to the profile with per-spacecraft materialization. |
| **Overrides** (spacecraft differs from its profile) | — | **Missing:** no override model. The spacecraft config doc and profile defaults overlap only partly. |
| Staged edit effect ("changes 499, keeps 1") | — | depends on §0 and overrides |

**v1:** profile list, detail with read-only sections from real fields, inherit counts, version
history, create profile (existing flow). Editing, routing generator and overrides wait for the
model decisions.

---

## S5 · People & access (`/setup/people`, org-level)

**Components:** tablist (People, Invitations, Service identities, Roles, Command policies) with
counts; U1 people table (name link + email, role, missions, Command yes/no, Second GO yes/no,
status tag, last active) with filter box; U2 invite form (email, role select, missions checkboxes,
Send); U3 service identities list (name, last used, scope, key age caution); U4 command policies.

| Need | Source today | Gap |
| --- | --- | --- |
| Members (name, email, role, lifecycle) | `Accounts.page_organization_members/…` | JSON endpoint for org admins (today only via the platform-admin path?) |
| Pending invitations | `page_pending_organization_invitations` | JSON |
| Send invite | `Administration.OrganizationInvitations` (platform-admin path) | **Ask api:** an org-admin invite action. |
| **Console roles** (Operator, Flight director, Engineer, Viewer, Org admin) | membership role is only `:organization_admin \| :member` | **Decided #2:** no roles model. Show the real role; derive Command / Second GO from session capabilities (`operate_mission`, `approve_activation`). |
| Can command / can give second GO | derivable from policy actions if roles exist | depends on roles |
| Status "On console" / last active | — | **Missing:** presence and last-seen. Could come from Phoenix Presence on the console socket. |
| Service identities (name, scope, last used, key age) | REST `/api/organizations/:org/service_identities` (bearer) | session JSON; last-used and key-created timestamps? |
| Command policies | `L/governance/activation_policy.ex` (config activation only) | **Missing:** two-person / fleet-reach command policies. Coordinate with fe-ops (Approve board). |

**v1:** People (real role values, no presence), Invitations list + invite with the existing two
roles, Service identities list. Roles and command-policy tabs are hidden until the model exists.

---

## Remaining rail items (same patterns)

| Rail | Page pattern | Data source |
| --- | --- | --- |
| 05 Comms & routing | list + detail (transports, routing rules), validation findings | `TransportStore`, `RoutingRuleStore`, comms validation; bridge `cadence.comms.*` today |
| 06 Ground stations | list + detail + edit | `GroundStationStore` (no coordinates/antennas/health) |
| 07 Data sources | list + health detail | `Management.DataSources` |
| 08 Apps | install inventory, install/disable/uninstall | `Reads.Applications.Inventory`, `ApplicationInstallations` |
| Missions | org mission list + create | `Missions.list_missions`, `Missions.Creation` |
| Settings | mission settings overview | `Missions.settings_overview` |
| Audit log | event table with filters | **Missing unified log.** `OperationalEvents.list_events`, provider audit, routing-rule events, app events |
| Ground-network providers | list/new/show (exists in LiveView) | `MissionProviders`. Not on the canvas rail; ask ux where it lives (probably under Comms). |

## Shared components I need from lead

Panel (indexed header), stat/area tile, status tag (shape + color + word), segmented control /
tablist, table with name-link column, filter input, form field (label + input/select/checkbox),
callout, buttons (default/primary), wizard step header, empty state, breadcrumb, local section nav,
diff row (op glyph). TimePicker isn't needed by Setup v1.

## Open questions

**For api:** see the "Missing" rows above. The shortlist, in priority order, is in the message sent
to api.

**For ux:** answered in `docs/apogee/ux/decisions.md` U1–U6:
- URLs are `/console/:org/:mission/...`, and org pages are `/console/:org/org/...`.
- Option B for now: no `CONFIG rN`, no staged bar, and a per-entity version in each page header.
  R2 = Recent changes if api unifies events, else omitted.
- A blocker is a crit diamond + "Blocker". Optional is a gray dash.
- Transports are a tab in 05. Providers are a tab in 06. Provider accounts sit under Org.
- Takeover is only for multi-step create wizards. The catalog diff stays in-shell.
- Spacecraft detail uses the Profile layout with "Open in Ops →".

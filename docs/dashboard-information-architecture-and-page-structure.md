# Dashboard information architecture and page structure

Status: product and interaction architecture proposal, not an accepted architecture decision

Observed: 2026-08-01

Companion to: [Grafana and Cadence dashboard feature audit](dashboard-grafana-cadence-feature-audit.md)

## 1. Decision

Following through on the Grafana audit must not reverse the earlier
telemetry-first dashboard simplification.

The dashboard viewer has one primary job:

> Show what is happening in mission telemetry for the selected operational
> context and time.

Everything else should have one of five homes:

1. a compact, exceptional-state indicator on the viewer;
2. the Ops context rail when it is operational context that should follow the
   operator across pages;
3. an on-demand, page-local inspector for one selected thing;
4. a dedicated page for a collection, workflow, or body of history; or
5. a separate authoring surface for changing the dashboard document.

This means “more like Grafana” should produce a better workshop around the
dashboard, not a denser dashboard page.

## 2. Preserve the decisions from earlier iterations

The previous decluttering work established good product boundaries that should
be treated as constraints:

- telemetry remains the visual center of the page;
- scope and time are compact controls rather than permanently expanded forms;
- dashboard-wide warnings collapse into one conditional data-issues entry
  point;
- widget source, lifecycle, evidence, and warning detail stays behind one
  widget-details action;
- healthy and nominal states are silent by default;
- blocking and empty states may interrupt the widget because they change the
  meaning of the visualization;
- source inventory and source selection do not occupy the Ops context
  rail;
- the context rail does not start expanded; and
- shared overlays own focus, dismissal, and stacking behavior.

The feature audit adds substantial capability. The rule is that new capability
must strengthen these boundaries rather than leak back into the viewer.

## 3. Current architecture: strengths and pressure points

### 3.1 What is already correctly separated

Cadence already has durable, dedicated homes for several concerns:

- Telemetry Explore for sample-level investigation;
- Data Sources for physical sources, logical bindings, health, and watermarks;
- Contacts for opportunities, reservations, and provider/Cadence lifecycle;
- Catalog for point meaning, definitions, revisions, imports, and activation;
- Spacecraft for identity, SCID, profile, and readiness;
- Comms for transports, ground stations, routing, providers, and validation;
- Applications for typed product and extension surfaces; and
- Admin Runtime for cross-dashboard invalidation decisions and process-local
  diagnostics.

Dashboard links should make those pages easier to reach with context. They
should not recreate their contents on the dashboard.

### 3.2 Where the current boundaries are under pressure

| Current pressure | Why it matters |
| --- | --- |
| The Ops rail labels dashboards, sources, approvals, planning, requirements, and contacts as peer “Modes.” | These are different kinds of work: observe, act, plan, and administer. The label does not help an operator predict page ownership. |
| Telemetry Explore sets the Dashboards navigation item active. | Explore is a first-class investigation workspace, not a hidden dashboard sub-mode. |
| The rail lists every active dashboard. | It does not scale and duplicates the dashboard directory. The rail should show only favorites or recent dashboards. |
| The dashboard viewer action menu owns editing, adding widgets, versions, historical-data requests, diagnostics, runtime defaults, publishing, renaming, and archiving. | Viewer, editor, governance, data repair, and administration are separate workflows with different state and authorization boundaries. |
| Versions & activity is a sheet containing publish readiness, comparison review, lifecycle activity, publish impact, and runtime defaults. | A collection of history and review actions has become a page-sized workflow inside an overlay. |
| Historical-data workflows and recovery controls live under dashboard-show modules. | Backfill, correction, revision, and job recovery are mission data operations that can affect many dashboards. A dashboard is a launch context, not their owner. |
| Dashboard diagnostics includes engine, runtime, invalidation, and recent invalidation collections in a sheet. | The content is valuable, but filtering and historical inspection deserve a stable, linkable page. |
| Data Sources combines inventory, registration, credentials, bindings, readiness, deployment actions, health, watermarks, and recent activity. | Operator status and administrator mutation are interleaved on one long page. |
| The Ops context rail has not yet been developed in earnest, leaving comparison content as its clearest current use. | Without a shell-level contract, page-local inspection can capture a region intended to carry operational awareness across every Ops page. |
| Fleet health can be repeated in the global status bar and Ops context rail. | The two surfaces need complementary contracts: the status bar carries the smallest urgent signal, while the rail carries richer glanceable operational context without restoring nominal noise. |

## 4. Product hierarchy

The product should retain three nested levels: organization, mission, and
operations. The Operations shell is a focused workspace inside a mission, not a
replacement for mission configuration.

```text
Organization
├── Home
├── Missions
└── Provider accounts

Mission
├── Overview
├── Operations
│   ├── Observe
│   │   ├── Dashboards
│   │   ├── Explore
│   │   ├── Alarms
│   │   └── Timeline
│   ├── Act
│   │   ├── Contacts
│   │   └── Commands
│   ├── Plan
│   │   ├── Planning
│   │   └── Requirements
│   └── System
│       ├── Data sources
│       ├── Data operations
│       └── Approvals
├── Spacecraft
├── Catalog
├── Comms
└── Applications
```

This hierarchy deliberately separates:

- **Observe:** understand current or historical mission state;
- **Act:** operate durable mission workflows;
- **Plan:** decide future contacts and requirements;
- **System:** understand or administer the data plane; and
- **Mission configuration:** define the resources and semantics the Ops
  surfaces consume.

The Ops context rail cuts across Observe, Act, Plan, and System. It is not a
fifth destination group; it is the shared operational-awareness layer that
remains available while the operator works in any of them.

There should not be a new, dense `/ops` overview page. Entering Operations
should open the last-used dashboard when that preference is available and valid,
otherwise the dashboard directory. Mission Overview already owns readiness and
orientation.

## 5. Shell structure

### 5.1 Mission navigation

The mission sidebar should expose one **Operations** entry, not an expandable
Ops group containing only Dashboards. It enters the full-screen Ops shell.

Spacecraft, Catalog, Comms, and Applications remain mission-level configuration
areas. They should not be duplicated in the Ops rail.

### 5.2 Operations status bar

The persistent top bar should contain only global identity and availability:

- back to mission and mission identity;
- an exceptional alarm/limit indicator only when action is needed;
- UTC clock;
- connection state;
- notifications; and
- user/admin-mode controls.

It should not permanently show green/blue/yellow/red fleet counts or a
“violating points” summary. Alarms owns the full fleet condition. Mission
Overview owns readiness. Nominal state remains silent.

### 5.3 Operations rail

The rail should use the Observe, Act, Plan, and System groups above. It should
add Explore as a first-class item and stop marking Explore as Dashboards.

Below the primary navigation it may show:

- up to five starred dashboards;
- up to five recent dashboards; and
- New dashboard.

The full dashboard collection, archived dashboards, library, playlists, sort,
tags, and search belong to the dashboard directory.

### 5.4 Ops context rail

The right-side Ops context rail is part of the Ops shell, not part of the
Dashboard Viewer and not a page-local inspector. It makes important operational
context available to operators regardless of which Ops page currently has their
focus.

The intended experience is context at a glance without breaking the current
task. Initial modules may include:

- active alarm posture, highest severity, and recent transitions;
- queued, releasing, in-flight, and recently completed command posture;
- the state of a command the operator is actively following;
- the current or next contact and material link-state changes; and
- exceptional source or mission conditions that affect operations broadly.

These are compact projections of facts owned by Alarms, Commands, Contacts,
Timeline, and Data Sources. Each module summarizes state and links to its
canonical page for investigation or workflow. The rail does not become the
canonical record or reproduce the full page.

The shell contract should:

- mount the same rail on every Ops page;
- retain a visible rail affordance even when collapsed;
- expose highest urgency and in-flight counts in that collapsed affordance;
- preserve expanded/collapsed state and module continuity while navigating
  between Ops pages;
- keep urgent and in-flight operational state easy to scan while making
  nominal state quiet;
- let operators expand, collapse, and arrange modules without changing the
  document or workflow on the page beneath it; and
- dock beside the workspace on wide displays and use the shared Sheet
  presentation on narrow displays.

By default, the rail represents the current mission-wide operational state. It
does not silently inherit a page's historical time range, replay run, dashboard
scope, search filter, or selected record. Otherwise an operator investigating
history could unknowingly lose sight of a live alarm or command in flight. A
future explicitly pinned operational focus may narrow the rail, but that scope
must be visibly labeled and must persist intentionally across page navigation.

The rail should not contain full source inventory, source-selection controls,
configuration forms, audit collections, historical recovery workflows, or
page-specific query results. It may summarize an exceptional source condition,
but Data Sources remains the owner of source detail and administration.

Compare and selected-widget/sample/event inspection are separate, page-local
interactions. They use an inspector sheet or purpose-built docked pane and must
not replace, clear, or commandeer the Ops context rail.

### 5.5 Page toolbar

Every page owns a narrow page toolbar below the status bar. It contains the
identity and controls unique to that page. Global mission status does not repeat
there.

Examples:

- Dashboard Viewer owns dashboard name, scope, time, investigation, data issues,
  and viewer actions.
- Explore owns investigation identity, scope, time, data view, and saved/promotion
  actions.
- Contacts owns schedule range, resource filters, and opportunity/reservation
  actions.
- Data Sources owns source/binding filters and status posture.

## 6. Dashboard page family

“Dashboard” should be a small family of pages rather than one LiveView with an
ever-growing set of sheets and modes.

| Page | Proposed route | Primary question | Owns | Explicitly does not own |
| --- | --- | --- | --- | --- |
| Directory | `/missions/:mission_id/ops/dashboards` | Which dashboard do I need? | Search, tags, stars, sort, recent, lifecycle filter, archived list, create/clone/import entry points. | Canvas rendering, source diagnostics, version history. |
| Viewer | `/missions/:mission_id/ops/dashboards/:dashboard_id` | What is happening for this scope and time? | Published canvas, runtime context, shared selection, annotations, exceptional data health, and fast drilldowns. | Editing forms, version collections, source configuration, backfill recovery, runtime tables, or ownership of the Ops context rail. |
| Editor | `/missions/:mission_id/ops/dashboards/:dashboard_id/edit` | How should this dashboard be composed? | Staged document transaction, widget gallery, WYSIWYG preview, layout, sections, binding/options, Save and Discard. | Live operational monitoring, publish review history, data repair. |
| Settings | `/missions/:mission_id/ops/dashboards/:dashboard_id/settings` | What are this dashboard's durable defaults and policies? | Name/description, default runtime context, links, access posture, deployment/export settings, archive. | Widget composition and operational inspection. |
| Activity | `/missions/:mission_id/ops/dashboards/:dashboard_id/activity` | What changed, who changed it, and is it publishable? | Versions, semantic diffs, review requests, publish readiness, publish impact, restore/revert, lifecycle audit. | Source/job recovery and low-level engine diagnostics. |
| Diagnostics | `/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics` | Why did this dashboard resolve or refresh this way? | Plans, requests, frames, cache, source execution, invalidation decisions, affected placements, copyable diagnostic identity. | Normal monitoring and source mutation. |
| Library | `/missions/:mission_id/ops/dashboards/library` | Which reusable widget/template should I use? | Search, compatibility, versions, binding placeholders, usage/update posture. | Dashboard-specific layout. |
| Playlists | `/missions/:mission_id/ops/dashboards/playlists` | What should an operations display rotate through? | Playlist order, dwell, wallboard mode, scope/default posture. | Editing dashboard documents. |

Read-only snapshots and imports can be managed from the Directory as tabs until
their collections are large enough to deserve routes. Share is initiated from
the Viewer because it captures the current runtime context.

## 7. Page anatomy

Every page below sits inside the Ops shell and therefore has access to the same
right context rail. The wireframes do not repeat the expanded rail everywhere;
its contents and continuity belong to the shell, not to an individual page.

### 7.1 Dashboard directory

```text
┌──────────────────────────── Operations status bar ────────────────────────────┐
├─ rail ─┬─ Dashboards ─────────────── [search] [filters] [+ New] ─────────────┤
│ Observe│  Dashboards | Library | Playlists | Archived                         │
│ Act    │                                                                           │
│ Plan   │  Starred / Recent                                                        │
│ System │  ┌ dashboard row/card ───────────────────────────────────────────────┐    │
│        │  │ name · tags · owner · lifecycle · updated · widget count          │    │
│        │  └────────────────────────────────────────────────────────────────────┘    │
└────────┴─────────────────────────────────────────────────────────────────────────────┘
```

The default presentation should favor a sortable table once the mission has
more than a small number of dashboards. Cards remain useful for Starred/Recent
and the empty/onboarding state.

### 7.2 Dashboard viewer

```text
┌──────────────────────── Operations status bar ────────────────┬─ Ops context ─┐
├─ rail ─┬─ Dashboard · scope/time · Explore · issues · Share ──┤ Alarms        │
│ Observe│  [active range · Return live when historical]         │ Command queue │
│ Act    │                                                       │ Command state │
│ Plan   │  Section title                                        │ Contact/link  │
│ System │  ┌──────── widget ──────┐ ┌──────── widget ──────┐    │               │
│        │  │ telemetry visual     │ │ telemetry visual     │    │               │
│        │  └──────────────────────┘ └──────────────────────┘    │               │
│        │  Inspect/Compare overlays only when requested         │               │
└────────┴───────────────────────────────────────────────────────┴───────────────┘
```

Persistent viewer regions are limited to the Ops shell—including its shared
context-rail affordance—compact dashboard toolbar, active historical-range hint
when needed, section headers, and canvas.

Viewer action menu:

- Star/unstar;
- Share current view;
- Edit dashboard;
- Settings;
- Activity;
- Diagnostics, when authorized or when troubleshooting requires it; and
- presentation/wallboard actions.

Publish, archive, historical workflow recovery, source mutation, and widget
forms are not viewer actions.

The Ops context rail continues to show cross-page operational awareness on the
Viewer just as it does elsewhere. Compare is an explicit toolbar mode that
opens a page-local docked pane or sheet. Selecting a widget, sample, event,
warning, annotation, or evidence chain may open the same local inspector. These
interactions do not mutate or replace the Ops context rail.

### 7.3 Dashboard editor

```text
┌─ Back to viewer ─ Dashboard draft v8 ─ preview context ─ [Discard] [Save] ──┐
├─ Add / Outline ─┬──────────── WYSIWYG draft canvas ───────────┬─ Inspector ─┤
│ Widget gallery  │ section / grid / real rendered widgets       │ Binding     │
│ Search          │ move · resize · select                        │ Scope/repeat│
│ Sections        │                                              │ Presentation│
│ Structure       │                                              │ Evidence test│
├─────────────────┴──────────────────────────────────────────────┴─────────────┤
│ Validation summary · unsaved state · source/contract issues                  │
└───────────────────────────────────────────────────────────────────────────────┘
```

Editor rules:

- entering the route creates a local staged edit transaction;
- no move, resize, section change, or form change writes a durable version;
- candidate widgets resolve through the production engine and render in place;
- Test binding remains available as the textual request/frame/evidence detail;
- Save creates one coherent draft version with a semantic summary;
- Discard restores the starting version;
- leaving with changes warns without writing;
- Review & publish navigates to Activity with the saved draft selected; and
- live ticks are paused, clearly and quietly, while editing.

The editor is optimized for a wide display. Narrow displays may view and inspect
dashboards, but should not offer a compromised drag/resize authoring experience.

### 7.4 Telemetry Explore

The canonical route should become `/missions/:mission_id/ops/explore`. The
existing `/ops/telemetry/explore` route can redirect for bookmark compatibility.

```text
┌──────────────────────────── Operations status bar ────────────────────────────┐
├─ rail ─┬─ Explore ─ [question/preset] [scope] [time] [data view] [Save/Add] ─┤
│ Observe│ ┌─ Observable / filters ─┬─ visualization and result table ─┬ Inspect┐│
│ Act    │ │ point/catalog search   │ shared selection and comparison  │ sample ││
│ Plan   │ │ validity/revisions     │                                   │ packet ││
│ System │ │ source/binding         │                                   │ evidence││
│        │ └────────────────────────┴───────────────────────────────────┴────────┘│
└────────┴────────────────────────────────────────────────────────────────────────┘
```

Explore owns ad hoc investigation, sample identity, validity/revision views,
packet-to-pixel provenance, and side-by-side comparison. It begins with
queryless mission questions or context carried from a dashboard, not a blank
storage query.

**Add to dashboard** opens the Editor with a staged candidate widget. It does
not mutate a dashboard directly from Explore.

### 7.5 Dashboard activity

Activity is a dedicated history/review workspace with these sections:

- Versions and semantic diffs;
- Review requests and decisions;
- Publish readiness and blocking issues;
- Publish impact and target version;
- Restore/revert into a new draft; and
- Dashboard lifecycle audit.

Runtime defaults move to Settings. Historical-data job recovery moves to Data
Operations. Engine and invalidation detail moves to Diagnostics.

### 7.6 Dashboard diagnostics

Diagnostics uses a two-column master/detail page:

- left: filterable executions, invalidations, placements, warning types, and
  timestamps;
- right: selected plan/request/frame/cache/invalidation explanation and links
  to Sources, Explore, Catalog, or Admin Runtime.

The Viewer retains only a one-screen issue summary. “Open diagnostics” carries
dashboard, placement, warning, source, scope, time, realm, and replay context.

## 8. Dedicated operational pages

### 8.1 Data Sources: status and topology

The operator-facing page owns:

- physical source inventory;
- logical bindings and binding priority;
- capabilities and supported products/sampling;
- health, readiness, retention, and watermarks;
- recent source/binding/health activity; and
- focused remediation links.

Split source detail from mutation:

| Route | Purpose | Access |
| --- | --- | --- |
| `/missions/:mission_id/ops/data-sources` | Inventory and mission-wide posture. | Operations readers. |
| `/missions/:mission_id/ops/data-sources/:data_source_id` | Source detail, bindings, capability, health, watermark, and activity. | Operations readers. |
| `/missions/:mission_id/ops/data-sources/:data_source_id/settings` | Credentials reference, adapter configuration, enable/disable, provision/deprovision, rotation, and destructive actions. | Organization/source administrators. |

Register Source is also an administrator route rather than an inline form on the
inventory page.

### 8.2 Data Operations: history, correction, and repair

Add `/missions/:mission_id/ops/data-operations` as the owner for:

- historical-data requests;
- backfill/import groups and jobs;
- correction requests;
- revision decisions and comparison review;
- retry, requeue, stale/missing replacement recovery;
- closure/readiness posture; and
- the audit trail from request through changed canonical data.

A dashboard or Explore selection may launch a prefilled request. The workflow
then belongs to Data Operations and may list all affected dashboards. This
prevents job-recovery machinery from remaining coupled to
`OpsDashboardShowLive`.

### 8.3 Alarms

Add `/missions/:mission_id/ops/alarms` as the owner for:

- active limit/alarm conditions;
- severity and acknowledgment posture;
- spacecraft, subsystem, point, and time filtering;
- governing limit definition and activation interval;
- exact violating samples and evidence; and
- related contacts, commands, and operational events.

The dashboard shows limit coloring, bands, annotations, and an exceptional
count. It links to Alarms for the collection and lifecycle.

### 8.4 Timeline

Add `/missions/:mission_id/ops/timeline` as the owner for the unified mission
event stream:

- contacts and pass phases;
- limits;
- commands and verifier outcomes;
- source health and watermarks;
- catalog/binding activation;
- backfills, imports, and revision decisions; and
- transport/runtime operational events.

Dashboard annotations are projections of these facts. Selecting one navigates
to the canonical event in Timeline with the dashboard range preserved.

### 8.5 Commands

Add `/missions/:mission_id/ops/commands` as the owner for request, validation,
queue, release, transport, and verification workflows.

A dashboard may launch a typed command intent when its widget contract permits
it. Authorization, confirmation, release, and outcome remain on Commands. A
visualization must never become an arbitrary action runner.

## 9. Canonical ownership of information

| Information or workflow | Canonical page | What the dashboard may show |
| --- | --- | --- |
| Telemetry values and trends | Dashboard Viewer / Explore | Full visualization. |
| One selected sample, point, packet, or evidence chain | Explore or a contextual inspector | Selected mark and a compact inspector entry point. |
| Scope and time | Runtime URL context | Compact control and current state. |
| Active limits/alarms | Alarms | Color/band/annotation and exceptional count. |
| Mission events | Timeline | Relevant annotations and selected event. |
| Source health/capability/watermark | Data Sources | Exceptional data-issue summary and source badge when it changes interpretation. |
| Backfill, correction, revision, and job recovery | Data Operations | Annotation/status when it affects displayed data and a context-preserving link. |
| Dashboard document composition | Dashboard Editor | Published document only. |
| Versions, review, and publish | Dashboard Activity | Published/draft posture and blocking badge only when relevant. |
| Durable dashboard defaults | Dashboard Settings | Current effective runtime state, not the form. |
| Engine/cache/invalidation behavior | Dashboard Diagnostics / Admin Runtime | One issue summary and troubleshooting link. |
| Contacts and reservations | Contacts | Contact interval, phase, and selected link. |
| Commands and verification | Commands | State/annotation and typed launch or detail link. |
| Point definitions, units, calibration, limits | Catalog | Correct label/unit/limit rendering and a link on mismatch/detail. |
| Spacecraft identity and routing readiness | Spacecraft / Comms | Context label and actionable empty-state link. |
| Extension packages and domain applications | Applications | Registered widget/surface/action behavior, never package administration. |

## 10. Overlay versus page rules

This decision rule prevents future iterations from slowly rebuilding dedicated
pages inside dashboard sheets.

| Surface | Use it for | Do not use it for |
| --- | --- | --- |
| Inline canvas content | Information required to interpret the visualization now. | Healthy diagnostics, audit history, configuration forms. |
| Popover | A short selection or explanation: scope, time, refresh, quick share option. | Long forms, tabs, tables, or scroll-heavy history. |
| Ops context rail | Cross-page, glanceable operational awareness such as alarm posture and command queue/state while the operator remains focused on the current page. | Page-local selected-entity inspection, full collections, configuration, audit history, or multi-step workflows. |
| Inspector sheet | One selected widget, sample, event, warning, or evidence chain; quick read-only detail and one-step links/actions. | Collections, filtering, job recovery, version history, source administration. |
| Modal | Destructive confirmation, privilege confirmation, or a short atomic decision. | Browsing, investigation, or multi-step work. |
| Dedicated page | Any collection, filterable history, multi-entity comparison, multi-step workflow, durable settings, or shareable investigation. | A single quick choice that loses the user's canvas context unnecessarily. |

A page-local inspector becomes a page when it needs any two of: tabs, filters, a
list of many records, pagination, multi-step mutation, independent browser
history, or a URL someone would share as the primary artifact.

## 11. Viewer disclosure hierarchy

The dashboard Viewer participates in five levels of information:

1. **Canvas:** telemetry, units, limit semantics, state, annotations, and the
   minimum labels needed to read the visualization.
2. **Exceptional indicator:** data issue, partial/stale/unsupported posture,
   publish mismatch affecting the viewed version, or active alarm requiring
   attention. Healthy state is absent.
3. **Ops context rail:** cross-page alarm, command, contact, link, and other
   operational posture supplied by the shell.
4. **Page-local inspector:** one widget/sample/event/warning/evidence selection
   or a dashboard comparison.
5. **Dedicated workflow:** Explore, Alarms, Timeline, Sources, Data Operations,
   Contacts, Commands, Activity, Diagnostics, Catalog, Spacecraft, or Comms.

Nothing should skip from level 5 back to permanent level-1 chrome merely because
it is technically related to a widget.

## 12. URL and state ownership

### 12.1 Paths identify workspaces

Viewer, Editor, Activity, Settings, Diagnostics, Explore, Sources, and Data
Operations should have distinct paths. They should not be hidden as a large
`panel=` state on the Viewer route.

### 12.2 Query parameters reproduce runtime context

Dashboard and investigation links preserve, where relevant:

- mission and dashboard identity;
- scope kind and one/many resource IDs;
- time mode, axis, from/to, and selected time/range;
- realm and replay run;
- data view and comparison view;
- data source and source binding;
- limit semantics; and
- explicitly pinned placement, observable, event, warning, or sample.

Hover and crosshair movement stays client-local. An explicit selection may
promote it into URL state. Merely hovering must not create browser history.

### 12.3 State has one persistence boundary

| State | Owner |
| --- | --- |
| Layout, sections, widgets, binding declarations, presentation, durable defaults | Staged Editor transaction, then Dashboard Document on Save. |
| Current scope/time/data/limit/replay selection | URL and session runtime context. |
| Cursor, hover, temporary zoom before promotion | Client interaction state. |
| Ops context-rail expansion, module preferences, and explicitly pinned operational focus | Ops shell/session UI state, independent of the current page and dashboard document. |
| Versions, review, publish, archive | Dashboard lifecycle stores and Activity. |
| Frames, requests, plans, cache, source status | Runtime engine and Diagnostics. |
| Backfill/correction/revision workflows | Data Operations. |

Changing runtime context never dirties a dashboard document. Moving a widget in
the Editor does not write until Save.

## 13. Feature-audit placement

This maps the audit recommendations to their primary implementation home.

| Surface | Audit items primarily owned here |
| --- | --- |
| Dashboard Directory | S1, S2, S10-S13, S15; I17. |
| Dashboard Viewer | S5 viewer actions, S8, S14; I1, I4-I6, I15, I19-I21; N4, N5, N14. |
| Dashboard Editor | S3, S4, S6, S7, S9, S16; I2, I7-I11; authoring side of I16 and I18; N15 validation. |
| Dashboard Settings | S11-S12 dashboard policy/export aspects; durable-default and archive aspects of I16. |
| Dashboard Activity | Review/publish/version aspects of I16; N15 publish readiness. |
| Dashboard Diagnostics | I3 expert layer; N11. |
| Telemetry Explore | I3 operator/evidence layer, I13, I14; N1-N3, N5, N12. |
| Ops context rail | Supporting cross-page projections of I6, I21, N6, and N13; it owns no canonical records. |
| Data Sources | I12, I20; N9. |
| Data Operations | N10 and data-repair/revision portions of I6, I15, and I21. |
| Alarms and Timeline | I6, I21; event/limit portions of N7 and N12. |
| Contacts and Commands | N6, N13. |
| Catalog, Spacecraft, Comms, Applications, and Admin | I18, I22; N7, N8, N16. |

If an audit item appears on more than one surface, one page remains canonical.
Other surfaces receive a summary or a context-preserving link.

## 14. Cross-page workflows

### 14.1 Investigate a degraded widget

```text
Viewer issue indicator
  → widget inspector explains empty/stale/partial state
    → Explore for samples/provenance
    → Data Sources for capability/health/watermark
    → Catalog/Spacecraft/Comms for definition or readiness mismatch
    → Dashboard Diagnostics for plan/cache/invalidation behavior
```

The issue type determines the destination. “Open diagnostics” should not be the
only answer to every failure.

### 14.2 Edit and publish a dashboard

```text
Viewer → Editor → staged WYSIWYG changes → Save draft
       → Activity → review publish readiness/impact → Publish
       → Viewer resolves the published version
```

No document revision is created by individual drag, resize, or section actions.

### 14.3 Repair historical data

```text
Viewer or Explore selection
  → Data Operations request prefilled with scope/time/source/evidence
  → request, jobs, recovery, correction, review, revision decision
  → affected dashboards listed
  → return to the same Viewer/Explore context and compare the result
```

### 14.4 Investigate link degradation

```text
Dashboard annotation/selection
  → queryless Explore: Link degradation
  → Contacts for scheduled/provider/realized state
  → Comms for transport/routing/readiness
  → Timeline for source, RF, command, and contact events
```

## 15. Authentication and router placement

No route changes are made by this proposal. When implemented, routes should be
placed by capability at the router, not merely hidden in templates.

| Router/live-session boundary | Proposed pages | Why |
| --- | --- | --- |
| Existing authenticated `live_session :ops` | Directory, Viewer, Explore, read-only Activity, read-only Diagnostics, Alarms, Timeline, Contacts, Commands, Planning, Requirements, source inventory/detail, Data Operations read paths. | They require organization scope, mission loading, the Ops shell and its context rail, and operator-readable mission context. |
| A dedicated authenticated dashboard-authoring live session or equivalent router-level on-mount policy | New dashboard, Editor, Dashboard Settings, library mutation, playlist mutation. | Authoring changes mission-shared documents and should not rely on disabled buttons for authorization. |
| Existing `live_session :ops_admin` or a narrower source-administrator policy | Source registration/settings, credentials, provision/deprovision, approvals, and destructive data-operation controls. | These mutate data-plane posture or privileged workflow state. |
| Existing mission sessions | Catalog, Spacecraft, Comms, Applications. | They define mission resources and meaning rather than operate the live console. |
| Existing platform-admin session | Cross-organization runtime and platform administration. | Platform diagnostics and tenancy remain separate from mission Ops. |

The exact author/source capability names require policy ratification before route
implementation.

Capability-specific authoring or administrator sessions under `/ops` should
still render the Ops shell and context rail. The authorization boundary changes
what the page may do; it does not remove the operator's shared operational
awareness.

## 16. Migration sequence

The structure can be implemented incrementally without rewriting the dashboard
engine.

### Phase 0: restore trust

- fix the current Data Sources render failure;
- fix source-health event reconstruction failures;
- provide a healthy live showcase fixture; and
- retain the current context-preserving link contracts.

### Phase 1: clarify navigation without moving domain logic

- group the Ops rail as Observe, Act, Plan, and System;
- make Explore a first-class active item and canonical route;
- show favorite/recent dashboards rather than every dashboard;
- simplify the global fleet-health status bar to exceptional state;
- preserve the Ops context rail across every Ops page and establish its first
  alarm-state and command-queue/state modules;
- preserve rail continuity while navigating and keep its collapsed affordance
  visible; and
- implement Compare/Inspect as a separate page-local interaction.

### Phase 2: separate Viewer and Editor

- add the Editor route and staged transaction;
- move widget/section/layout controls into the Editor anatomy;
- implement WYSIWYG candidate rendering;
- add Save and Discard; and
- reduce the Viewer action menu to view-oriented navigation.

### Phase 3: extract grown workflows

- move version/review/publish content to Activity;
- move defaults/archive to Settings;
- move engine/runtime/invalidation collections to Diagnostics;
- move historical-data and recovery workflows to Data Operations; and
- split Data Sources inventory/detail from administrator settings.

### Phase 4: add the missing operational owners

- add Alarms, Timeline, and Commands;
- make dashboard annotations and actions link to those canonical pages; and
- add queryless investigation presets in Explore.

### Phase 5: add reuse and deployment

- add Library, import/export, dashboard-as-code validation, snapshots,
  playlists, and wallboard mode; and
- keep their management surfaces in the Directory/Settings family, not the
  Viewer.

## 17. Acceptance criteria

The information architecture is working when:

1. the Viewer has no always-visible diagnostic collection, configuration form,
   audit trail, or job workflow;
2. healthy/nominal system state is silent on the Viewer and Ops status bar;
3. an operator can reach Explore, Alarms, Timeline, Sources, Contacts, Commands,
   and Diagnostics with the relevant scope/time/evidence preserved;
4. an author can compose a dashboard in a WYSIWYG Editor and either Save or
   Discard one coherent transaction;
5. a reviewer can understand and publish a draft without entering the Viewer or
   Editor's internal controls;
6. source administrators can change credentials or provision a backend without
   exposing those controls to ordinary operators;
7. historical-data recovery can be followed independently of the dashboard that
   first exposed the gap;
8. the Ops navigation rail remains useful with hundreds of dashboards because
   the Directory owns the collection;
9. browser Back/Forward moves between workspaces and explicit selections without
   recording every hover;
10. the Ops context rail carries alarm state, command queue/state, and other
    glanceable operational context across Ops pages without taking focus from
    the current task;
11. page-local comparison or selected-entity inspection does not replace or
    commandeer the Ops context rail; and
12. every important fact or workflow has one canonical page owner.

The result should feel like Grafana where familiarity helps, but the page
hierarchy should make Cadence's product thesis unmistakable: the dashboard is
the visual console, and the surrounding mission system explains, governs, and
acts on what the dashboard shows.

## 18. Related documents

- [Dashboard and Ops information architecture delivery plan](dashboard-and-ops-ia-delivery-plan.md)
- [Grafana and Cadence dashboard feature audit](dashboard-grafana-cadence-feature-audit.md)
- [Dashboard interaction improvements](dashboard-grafana-interaction-improvements-plan.md)
- [Dashboards visualization engine design](dashboards-visualization-engine-design.md)
- [Dashboard feature maturity checklist](dashboard-feature-maturity-checklist.md)
- [Operational event timeline design](operational-event-timeline-design.md)
- [Typed extension packages and product applications](decisions/016-typed-extension-packages-and-product-applications.md)

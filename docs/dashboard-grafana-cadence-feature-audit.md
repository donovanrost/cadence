# Grafana and Cadence dashboard feature audit

Status: product audit and recommendation, not an accepted architecture decision

Observed: 2026-08-01

Grafana: OSS 12.2.10 at `localhost:3300`

Cadence: current working tree at `localhost:4001`

## 1. Decision

Cadence should not recreate Grafana feature for feature. It should recreate the
parts of Grafana that make dashboard composition fast, legible, predictable,
and safe; specialize the parts where a typed telemetry domain can provide a
better answer; and build the operational workflows a generic observability
tool cannot represent.

The practical product boundary is:

| Category | Rule | Product posture |
| --- | --- | --- |
| **Steal** | Grafana already has the better general-purpose interaction or authoring model. | Match its behavior closely enough that a Grafana user does not need to relearn dashboard mechanics. |
| **Improve** | Grafana supplies useful prior art, but Cadence has mission, catalog, provenance, replay, or operational context that can make the feature materially better. | Preserve the familiar interaction, replace generic strings and queries with typed domain semantics. |
| **New** | Grafana has no adequate representation for the domain need. | Design a Cadence-native workflow rather than forcing it through variables, annotations, or panel plugins. |

The short version is:

- **Steal the workshop:** browsing, panel creation, WYSIWYG editing, save/discard
  semantics, inspection, sharing, reuse, keyboard efficiency, and time-control
  ergonomics.
- **Improve the instruments:** variables become typed mission scope, queries
  become governed observable bindings, annotations become canonical mission
  intervals, panel inspection becomes evidence inspection, and transformations
  become catalog-safe presentation.
- **Build the control room:** Live/Archive/Replay continuity, sample validity and
  revisions, packet provenance, contacts, source capability and watermarks,
  spacecraft identity and routing readiness, historical-data workflows, and
  auditable operational actions.

## 2. Scope and method

This is a live-product audit, not a comparison assembled from marketing pages.
The audit used:

- rendered page inspection of the local Grafana and Cadence applications;
- Grafana health, dashboard, data-source, and plugin APIs;
- the saved JSON models for the two configured Grafana dashboards;
- Cadence's live routes and rendered controls; and
- the current Cadence widget registry, dashboard document model, and authoring
  components where a feature is present but could not be exercised safely from
  the current fixture.

“Each page” means the dashboard product surface and the pages directly involved
in composing, sourcing, investigating, governing, or operating a dashboard. It
does not mean every unrelated CRUD page in either application.

### 2.1 Snapshot limitations

- Grafana is configured for anonymous access. Alerting routes are not exposed
  by this local instance, so alert-rule authoring was not observable here.
- Loki and Tempo are configured, but the local drilldown pages currently report
  missing-volume/query errors or no data. Profiles Drilldown is at its setup
  screen. The interaction inventory is still observable; successful result
  behavior is not.
- Cadence's Data Sources page currently raises an `ArgumentError` while
  rendering `:events`. The underlying source and binding model is present, but
  that page is a live regression in this snapshot.
- The sampled Cadence mission's showcase widgets reference points that are not
  active in its current catalog, and one dashboard requires a spacecraft
  context. The empty/error states and investigation affordances are observable;
  those fixtures do not prove a healthy live chart.
- The Cadence working tree contains an in-progress dashboard interaction slice.
  Features such as sections, shared cursor/range selection, presentation
  controls, repeat authoring, and binding preview are recorded as the behavior
  of this working-tree snapshot, not as released product commitments.

## 3. Grafana page inventory

### 3.1 Navigation, discovery, and creation

| Page | Route | Features observed | Local-instance note |
| --- | --- | --- | --- |
| Home | `/` | Persistent product navigation; global search; New and Help entry points; recent/starred discovery; onboarding cards for adding a data source and creating a dashboard. | Establishes one obvious front door for both new and experienced users. |
| Dashboard browser | `/dashboards` | Search dashboards and folders; tag filter; starred-only filter; sort; row selection and bulk affordances; create menu. | Cadence currently has a much simpler mission dashboard card list. |
| Folder | `/dashboards/f/cadence/cadence` | Folder-scoped dashboard list; Dashboards and Panels tabs; folder actions; create menu. | The configured folder contains SRE Overview and Ingress Load Test. |
| New dashboard | `/dashboard/new` | Immediate choices to add a visualization, add a library panel, import a file, or import a Grafana.com dashboard; time range and refresh controls are available before the first panel. | Grafana starts from the canvas. Cadence currently starts from name and description. |
| Library panels | folder **Panels** tab | Search, sort, and type filtering for reusable panels. | Empty in this instance, but the reuse model is visible. |
| Playlists | `/playlists` | Create ordered dashboard rotations for wallboards and television displays. | Empty in this instance. |
| Snapshots | `/dashboard/snapshots` | Browse externally shared, point-in-time dashboard snapshots created from Share. | Empty in this instance. |

### 3.2 Dashboard viewing and composition

| Surface | Features observed |
| --- | --- |
| Dashboard toolbar | Dashboard/folder identity; variables; dashboard links; global time range; back and forward navigation; zoom out; refresh and auto-refresh; dashboard actions. |
| Variables | Query- and text-backed controls, multi/all behavior, compact placement above the canvas, and automatic use by panel queries and links. |
| Dashboard links | Named links can retain the active time range and variables. Both configured dashboards link to the peer dashboard plus logs and traces drilldowns. |
| Rows | Named collapsible groups structure a large canvas. The SRE dashboard has four rows; the ingress dashboard has five. |
| Grid | Free positioning and resizing through `gridPos`; panels retain explicit width, height, and coordinates. |
| Panel header/menu | Per-panel View, Edit, Share, Explore, Inspect, and More actions, with keyboard shortcuts shown beside common actions. |
| Panel inspection | A separate inspection workflow exposes the panel's data/query/runtime details without entering the full editor. |
| Panel descriptions | Descriptions explain intent and caveats without consuming graph area. |
| Cross-panel tooltip | The dashboard model can synchronize hover behavior through `graphTooltip`. |
| Annotations | A built-in dashboard annotation source is enabled on SRE Overview; the ingress dashboard has a named load-test phase/note annotation source. |
| Refresh policy | SRE Overview refreshes every 10 seconds over the last hour; Ingress Load Test refreshes every 5 seconds over the last 15 minutes. |

The configured dashboard inventory is:

| Dashboard | Variables | Rows | Panels | Visualizations | Links |
| --- | --- | ---: | ---: | --- | --- |
| Cadence / SRE Overview | `service`, `mission` | 4 | 12 | Stat, time series | Ingress, logs, traces; keeps time and variables |
| Cadence / Ingress Load Test | `service`, `direction`, `protocol`, `target_mbps` | 5 | 28 | Stat, time series | SRE, logs, traces; keeps time and variables |

### 3.3 Panel editor

Grafana's panel editor is the largest general-purpose gap between the two
products. It combines an actual rendered preview with a dense but predictable
editing workspace.

| Editor area | Features observed |
| --- | --- |
| Transaction controls | Back to dashboard; discard panel changes; save dashboard; additional save options. |
| Preview | The real visualization remains visible while editing and reflects editor changes. Table view can replace the visualization for data inspection. |
| Queries | Multiple named queries; data-source selection; query options; query inspector; Builder/Code modes; metrics browser; run; duplicate, hide, collapse, and remove query; add query or expression. |
| Transformations | A first-class tab between source queries and visualization rendering. |
| Visualization selection | Searchable visualization picker with a large installed catalog. |
| Panel identity | Title, description, transparent/background behavior, panel links, and repeat. |
| Tooltip and legend | Mode, sort, placement, and displayed calculation values. |
| Axes and grid | Time zone, placement, label, width, grid visibility, color, scale, centered zero, min, and max. |
| Graph styling | Lines/bars/points, interpolation, line width, fill, gradient, line style, null handling, point visibility, and stacking. |
| Standard field options | Unit, min/max, decimals, display name, color, and no-value rendering. |
| Links and actions | Data links plus actions associated with displayed values. |
| Semantic display | Value mappings and thresholds. |
| Overrides | Per-field overrides layer exceptions over defaults. |

The installed Grafana API reports 29 panel plugins: alert list, annotation list,
bar chart, bar gauge, candlestick, canvas, dashboard list, data grid, flamegraph,
gauge, geomap, getting started, heatmap, histogram, logs, news, node graph, pie
chart, stat, state timeline, status history, table, text, time series, traces,
trend, welcome, and XY chart.

That breadth is evidence for a good picker and extension model. It is not a
Cadence parity target.

### 3.4 Explore and queryless drilldowns

| Page | Features observed | Local-instance note |
| --- | --- | --- |
| Explore | Data-source selector; multiple panes; split view; global time navigation; run and auto-refresh; query outline; builder/code modes; metric and label selection; operations; legend/format/step/type/exemplar options; add query; query inspector. | The generic expert workbench behind a panel's Explore action. |
| Drilldown hub | Cards for Metrics, Logs, Traces, and Profiles. | Makes exploration approachable without starting with a query language. |
| Metrics Drilldown | Data source and label filters; metric search; sort; grid/row view; prefix/suffix/recent filters; group by labels; bookmarks; saved queries. | Configured against Prometheus/GreptimeDB. |
| Logs Drilldown | Label filters, line filters, search filters, time, and saved searches. | The local Loki volume is not configured, so results error. |
| Traces Drilldown | Root/all spans; Trace ID lookup; rate/error/duration metrics; Breakdown, Service structure, Comparison, and Traces views; favorites; resource/span attribute filters. | The local query returns no data/error. |
| Profiles Drilldown | Guided setup framed around cost, latency, and incident use cases. | No profile source is configured. |

The queryless Drilldown pages are particularly valuable prior art: they retain
the exploratory power of the underlying sources while starting from a question
and a filtered catalog instead of a blank query editor.

### 3.5 Connections, data sources, and administration

| Page | Features observed | Recommendation relevance |
| --- | --- | --- |
| Connections | Add a new connection or manage configured connections. | Clear separation between discovery and configuration. |
| Data sources | Search/sort configured sources; each card offers Build a dashboard and Explore. | Good handoff from source setup to value. |
| Prometheus data-source editor | Name/default source; URL; auth; TLS/certificates; skip verification; headers; cookies; timeout; alert/recording settings; scrape/query intervals; editor behavior; cache/incremental queries; HTTP method; series limit; exemplars; Reset/Delete/Save & test. | Cadence needs the validation rhythm, but source configuration should be capability- and mission-aware. |
| Administration home | Provisioning, General, Plugins and data, Users and access. | Useful information architecture, not a domain feature. |
| Provisioning | Git Sync and dashboard-as-code entry points. | Relevant prior art for governed dashboard deployment. |
| General | Organization defaults and preferences. | Generic platform function. |
| Plugins and data | Plugin management and correlations. | Extension lifecycle prior art. |
| Users and access | Users, teams, and service accounts. | Cadence already has organization and service-identity semantics. |
| Plugin catalog | Search/filter by type and state; core, signed, installable, and enterprise offerings; update affordances. | Ecosystem breadth is explicitly not a parity target. |

The configured sources are Prometheus backed by GreptimeDB (default), Loki,
and Tempo. All use server-side proxy access. The four pinned drilldown apps are
Metrics 2.3.1, Logs 2.4.0, Traces 2.1.0, and Profiles 2.2.0.

## 4. Cadence page inventory

All routes below are inside authenticated browser LiveViews. The dashboard and
investigation routes are in the router's `live_session :ops`, which requires an
organization scope, loads the mission, attaches the user menu, and uses the Ops
layout. This is the right scope because every surface is mission- and
organization-bound; no new routes are proposed by this audit.

### 4.1 Organization, mission, and readiness context

| Page | Route | Features observed |
| --- | --- | --- |
| Platform administration | `/admin` | Organization/user counts, organization management, runtime diagnostics, quick organization creation, and explicit administrator mode. |
| Organizations | `/admin/organizations` | Organization list and creation. |
| Organization detail | `/admin/organizations/:id` | Members, invitations, service identities, organization-scoped credential issuance, and Open Organization. |
| Runtime diagnostics | `/admin/runtime` | Process-local dashboard invalidation decisions filterable by dashboard, mission, boundary, context, replay, and placement; allowed/suppressed decisions; artifacts and impact inspection. |
| Organization home | `/` | Organization-level mission and provider-account navigation plus mission cards. |
| Missions | `/missions` | Mission list and creation. |
| Mission overview | `/missions/:mission_id` | Readiness counts; spacecraft runtime identity/profile state; SCID and downlink/link setup; direct corrective actions. |
| Spacecraft | `/missions/:mission_id/spacecraft` and detail routes | Spacecraft identity, SCID, profile/setup state, drift or missing profiles, protocols, and installed applications. |
| Catalog | `/missions/:mission_id/catalog` | Telemetry database and revision/import governance, runtime usage, packet definitions, and the semantic source for units, calibration, limits, and point identity. |
| Comms | `/missions/:mission_id/comms/...` | Transports, ground stations, routing, validation, provider setup, and readiness findings. |

These are not decorative dashboard variables. They are durable, typed resources
that determine whether data can be interpreted, routed, and trusted.

### 4.2 Dashboard discovery and creation

| Page | Route | Features observed | Gap against Grafana |
| --- | --- | --- | --- |
| Mission dashboards | `/missions/:mission_id/ops/dashboards` | Mission-shared telemetry dashboard cards; names, descriptions, widget counts; create action. Four dashboards exist in the sampled mission. | No search, folders, tags, starring, sorting, bulk actions, recent history, library inventory, or import. |
| New dashboard | `/missions/:mission_id/ops/dashboards/new` | Name and description, then create. | No visualization-first canvas, template, library, clone, or import choice. |

The sampled dashboards are Contact Summary (4 widgets), Live Link Health (6),
RF Anomaly Triage (5), and a one-widget test dashboard.

### 4.3 Dashboard viewing and operation

The dashboard show page is already substantially more than a graph grid.

| Surface | Features observed in the current working tree |
| --- | --- |
| Telemetry-first canvas | Compact toolbar, dense widget canvas, and a collapsible context rail keep visualization primary. |
| Typed scope | Mission, spacecraft, contact, ground station, source endpoint, transport, and link context; supports one or multiple selected resources. |
| Time | Live, Archive, and Replay modes; generation/receipt time axis; explicit from/to; selected replay run; visible current range and Return live action. |
| Data semantics | Realm, canonical or alternate data view, comparison data view, data source, source binding, and observed/alternate limit mode. |
| Selection | Shared selected timestamp/range state, pause at selection, clear selection, and live resume. The working tree adds cross-chart cursor and drag-range coordination. |
| Investigation menu | Telemetry Explore, Source Inventory, Contacts, and Dashboard Diagnostics links preserve relevant mission/dashboard context. |
| Data health | Aggregated affected-widget count, warnings, degraded/blocked status, and a direct diagnostics action. |
| Widget detail | Binding caption, lifecycle status, source status, data-management state, warnings, query diagnostics, frame evidence, and typed data links. |
| Empty states | Reason-aware copy plus Adjust scope & time and Investigate actions. Current fixtures demonstrate catalog/context mismatch states. |
| Context rail | A compact side surface exposes or changes operational context without replacing the canvas. |
| Actions | Edit layout; add widget; Versions & activity; request historical data; diagnostics; save runtime defaults; publish latest draft; rename; archive. |
| Lifecycle | Draft/published/archived model, publish readiness, comparison review queue, source action/activity history, immutable versions, and runtime defaults. |
| Sections | Stable section IDs, title, description, order, open/collapsed default, placement membership, and per-section grids in the working tree. |
| Repeat | Stable instances over selected spacecraft, contacts, ground stations, transports, or links with bounded count and wrap/row/column layout in the working tree. |

The showcase dashboards group operational questions rather than generic
metrics:

- **Contact Summary:** contact health, RF/throughput overview, downlink, and
  latency.
- **Live Link Health:** downlink, uplink, RF SNR, ingress latency, link
  throughput, connection state, and RF state.
- **RF Anomaly Triage:** RF margin, ingress processing latency, throughput
  during degradation, mission/data-source events, and state correlation.

### 4.4 Dashboard authoring

| Authoring surface | Features in the current working tree | Current limitation |
| --- | --- | --- |
| Edit mode | Pauses live updates; Done, Widget, and Sections controls; grid move/resize; configure/remove per widget. | Done is not an explicit Save/Discard transaction for the whole edit session. Layout and section operations create draft revisions as they occur. |
| Widget form | Type, title, optional operational section, binding source, scope mode, fixed spacecraft or active context, repeat declaration, telemetry point or operational observable, precision, and type-specific options. | The editor is a form beside the dashboard rather than a full WYSIWYG composition workspace. |
| Binding picker | Searchable telemetry points; searchable and product-grouped operational observables; source capability and scope warnings; selected chips. | Discovery is capable but visually separated from an actual rendered candidate. |
| Binding preview | Test binding executes a draft through the engine and reports ready/no-data/error plus request, frame, and warning counts without persistence. | It is a diagnostic count summary, not a rendered WYSIWYG widget preview. |
| Presentation | Value-tile unit visibility; time-series legend, line width, fill, gaps, points, axes, shared tooltip, precision, window, and min/max band. | Cadence intentionally lacks Grafana's broad per-field override and transformation surface. |
| Sections editor | Add/edit title and description, collapsed default, reorder, remove, and preserve unsectioned widgets. | Mutations are revision-producing actions rather than a staged dashboard edit. |
| Versions/activity | Version history, lifecycle events, publish impact/readiness, comparison review, source actions, invalidation activity, and recovery-related workflows. | Richer governance than Grafana, but the everyday edit/save path is less legible. |

The compiled first-party widget registry contains seven types:

| Widget | Contract and purpose |
| --- | --- |
| Value Tile | Latest scalar telemetry or operational metric with optional limits/quality. |
| Time Series | Up to eight metric observables; historical/appendable wide frames; limit, event, and quality overlays; repeat support. |
| Status Matrix | Latest metric/state matrix across operational products; repeat support. |
| Data Table | Latest scalar, matrix, or long-form telemetry/operational values; repeat support. |
| State Timeline | Limit or operational state event history with sample, limit, contact, and Explore drilldowns. |
| Event Timeline | Contact, mission, source health/watermark/capability, backfill, and telemetry-revision events and intervals. |
| Constellation Health | Mission-level operational health matrix with drilldown and repeat semantics. |

Every type declares a data contract, binding schema, options schema, layout
contract, drilldown contract, version, and renderer. That is a better safety
boundary than arbitrary panel code, even though it is a much smaller visual
catalog.

### 4.5 Explore, sources, and adjacent operations

| Page | Route | Features observed |
| --- | --- | --- |
| Telemetry Explore | `/missions/:mission_id/ops/telemetry/explore` | Point and spacecraft selection; latest/5m/15m/1h/explicit window; order and limit; realm; logical source; data source; source binding; canonical/all revisions/as recorded/recomputed views; validity filters for canonical, duplicate, conflict, superseded, and advisory; copy link; route identity; requested/returned/physical/effective diagnostics; sample table with receipt/generation time, engineering/raw values, quality, validity, source, evidence, packet, definition, and sample identity. |
| Data Sources | `/missions/:mission_id/ops/data-sources` | Intended inventory for managed/BYO sources, logical bindings, capability, health, and watermarks. | The page currently crashes while presenting `:events`; this is a release-blocking usability regression for the dashboard source story. |
| Contacts | `/missions/:mission_id/ops/contacts` | Opportunity search by spacecraft, downlink route, and time; provider opportunities; reservation ledger; durable workflow; explicit separation of provider truth from Cadence contact state. |
| Contact detail | `/missions/:mission_id/ops/contacts/:provider_reservation_id` | Reservation and provider lifecycle details, route and source context, review/reconciliation state. |

## 5. Steal: copy Grafana's better general-purpose answer

These recommendations should feel deliberately familiar to a Grafana user.
Cadence may use its own visual language, but should not invent different
interaction semantics without a concrete advantage.

| ID | Feature to steal | Grafana prior art | Cadence target | Priority |
| --- | --- | --- | --- | --- |
| S1 | Dashboard browser | Search, folders, tags, stars, sort, recent, selection, bulk actions. | Add the same discovery grammar inside a mission; preserve mission sharing and lifecycle badges. | P1 |
| S2 | Canvas-first creation | Add visualization, library panel, or import from the new-dashboard page. | After minimal identity, land on an empty canvas with Add widget, From library, Clone, and Import choices. | P1 |
| S3 | WYSIWYG widget editor | Real panel preview stays visible while query, visualization, and display options change. | Render the candidate placement through the production engine beside its binding and presentation controls. | P0 |
| S4 | Explicit edit transaction | Discard panel changes and Save dashboard are persistent, unambiguous actions. | Stage layout, section, widget, and metadata edits in one session; expose dirty state, Save, and Discard; create one coherent revision. | P0 |
| S5 | Per-widget action menu | View, Edit, Share, Explore, Inspect, More, and shortcuts. | Give every widget a consistent menu: View, Configure, Investigate, Inspect evidence, Duplicate, Copy to library, Share link, Remove. | P1 |
| S6 | Searchable visualization gallery | Large categorized visual picker with icons and search. | Replace a select input with a searchable seven-widget gallery that explains contract, shape, and supported scope. | P1 |
| S7 | Predictable grid interactions | Mature move/resize behavior and clear edit affordances. | Match Grafana's handles, drop targets, keyboard accessibility, and undo expectations while retaining the Cadence grid document. | P1 |
| S8 | Time-navigation ergonomics | Range picker, back/forward, zoom out, refresh picker, and obvious current range. | Add back/forward/zoom and refresh controls around Cadence's current Live/Archive/Replay control. | P1 |
| S9 | Panel duplication and clipboard flow | Duplicate/copy operations make composition fast. | Duplicate a widget in place, copy between compatible mission dashboards, and surface binding incompatibilities before save. | P1 |
| S10 | Reusable panel library | Library panels are searchable and separable from dashboards. | Add mission/org widget templates with explicit binding placeholders and versioned updates. | P2 |
| S11 | Sharing and portable dashboard artifacts | Panel/dashboard links, snapshots, JSON import/export. | Add permission-aware deep links, read-only snapshots, and versioned export/import for Cadence dashboard documents. | P2 |
| S12 | Dashboard-as-code | Provisioning and Git Sync treat dashboards as deployable assets. | Support validated dashboard bundles in release/config workflows with catalog/binding compatibility checks. | P2 |
| S13 | Playlists/kiosk | Ordered dashboard rotation for wallboards. | Add an operations display mode and mission playlist with live freshness visible at all times. | P3 |
| S14 | Keyboard efficiency | Shortcuts appear in panel menus and accelerate expert workflows. | Add discoverable shortcuts for search, edit, save/discard, add widget, investigate, time navigation, and return live. | P2 |
| S15 | Dashboard and panel descriptions | Intent is accessible without occupying primary chart area. | Preserve descriptions in tooltips/details and add concise operational purpose/caveat fields. | P2 |
| S16 | Search within long editors | Metrics, labels, visualization types, and options are searchable. | Make point, observable, widget type, data source, and option discovery keyboard-first. | P1 |

## 6. Improve: use Grafana's prior art, then add domain semantics

These features should remain recognizable, but a straight copy would discard
Cadence's main advantage.

| ID | Grafana prior art | Cadence improvement | Why this is better than a copy | Priority |
| --- | --- | --- | --- | --- |
| I1 | String/query dashboard variables | Typed scope over mission, spacecraft, contact, ground station, source endpoint, transport, link, and bounded multi-select sets. | Invalid combinations can be prevented, IDs remain stable, and drilldowns know what the selection means. | P0 |
| I2 | Panel query editor | Observable binding editor backed by catalog points and operational-observable contracts, with source plan, capability, frame shape, and evidence preview. | Operators choose meaning rather than storage syntax; the source may change without rewriting the widget. | P0 |
| I3 | Query inspector | Dual-level inspection: concise widget diagnostics for operators and full request/plan/source/frame/cache execution for experts. | Inspection can answer both “why is this empty?” and “which canonical facts produced it?” | P0 |
| I4 | Global time range | One Live/Archive/Replay continuum with generation/receipt time, selected replay run, mission-event/contact-relative ranges, and explicit Return live. | Mission time and replay identity cannot be represented by `now-15m` alone. | P0 |
| I5 | Dashboard links that keep time and variables | Context-preserving typed links that retain mission, scope IDs, time axis/range, realm, view, source/binding, replay run, limit mode, and selected evidence where relevant. | Downstream pages receive valid structured context, not a bag of interpolated strings. | P0 |
| I6 | Annotations | Canonical overlays for contacts, eclipse/pass phases, commands, limits, source health, watermark gaps, backfills, and revision intervals with evidence links. | An overlay is a governed domain fact, not an editable note detached from the source of truth. | P1 |
| I7 | Rows | Operational sections with stable identity, descriptions, collapsed defaults, section-scoped grids, and investigation entry points. | Structure communicates an operational procedure or question, not just visual grouping. | P1 |
| I8 | Repeating panels | Typed repeat declarations over selected domain resources, stable instance IDs, explicit layout, and safety limits. | Fleet/constellation comparison is native and bounded instead of templated query expansion. | P1 |
| I9 | Thresholds and value mappings | Catalog-driven units, calibrations, enum labels, limit bands, quality, and state colors with controlled presentation overrides. | A dashboard cannot silently disagree with telemetry decom or the alarm/limit system. | P0 |
| I10 | Transformations | A small, typed set of domain-safe transforms such as unit-normalized comparison, state interval projection, envelope/decimation, and quality-aware aggregation. | Avoids a second semantic computation language and keeps provenance explainable. | P2 |
| I11 | Field overrides | Registry-declared, bounded presentation options with catalog-safe defaults and explicit exceptions. | Authors get useful control without breaking units, limit semantics, or accessibility. | P1 |
| I12 | Data-source editor and Save & test | Source inventory with managed/BYO posture, credentials reference, isolation, capabilities, health, retention, watermarks, binding priority, and a contract-specific validation run. | “Reachable” is insufficient; Cadence must prove the source can satisfy a particular telemetry contract. | P0 |
| I13 | Explore workbench | Telemetry Explore with governed point selection, scope, time, source/binding, data realm/view, revision validity, copyable routes, and optional side-by-side comparison. | The workbench follows samples across revisions and evidence instead of exposing storage rows alone. | P1 |
| I14 | Queryless Drilldown | Question-led entry points such as Link degradation, Contact performance, Data gap, Limit excursion, Source health, Command outcome, and Fleet comparison. | Starts from mission questions and preloads valid context while retaining a path to expert controls. | P1 |
| I15 | Data links and panel actions | Typed links/actions resolved by stable resource IDs, with availability posture, authorization, stale-target handling, and audit events. | An operator can act from a widget without turning an arbitrary URL/action into an unsafe control path. | P1 |
| I16 | Dashboard version history | One staged edit transaction becomes an immutable version with actor, reason, semantic diff, publish readiness, review state, and restore/republish actions. | Combines Grafana's comprehensible save flow with Cadence's stronger governance. | P0 |
| I17 | Panel library | Versioned mission/org templates with typed binding holes, compatibility posture, and controlled propagation. | Reuse does not accidentally bind a widget to another spacecraft, catalog revision, or unavailable source. | P2 |
| I18 | Plugin/extension model | Typed extension packages publish versioned widget/data/action contracts through the Cadence application host. | Retains extensibility without arbitrary panel JavaScript gaining storage or tenant access. | P2 |
| I19 | Cross-panel hover | Shared cursor, timestamp/range selection, and selected event/evidence state across charts, timelines, matrices, and tables. | Correlation becomes a dashboard-wide investigation context, not only a visual crosshair. | P1 |
| I20 | Refresh and freshness | Auto-refresh plus source watermark, last receipt, staleness, completeness, and partial/blocked state. | “Refreshed five seconds ago” is not the same as “complete through five seconds ago.” | P0 |
| I21 | Generic alert/annotation links | Limits and operational events link back to exact definitions, intervals, samples, contacts, and source facts. | The displayed condition is traceable and cannot drift from its governing definition. | P1 |
| I22 | Administration and service accounts | Organization/mission scope, explicit time-bounded admin mode, and organization-scoped service identities. | Privilege and machine identity match Cadence's tenancy and API boundaries. | Existing strength |

## 7. New: build what Grafana cannot model adequately

These are not “better panels.” They are the product moat. They should not be
delayed until generic Grafana parity is complete.

| ID | Net-new Cadence capability | Operator outcome | Priority |
| --- | --- | --- | --- |
| N1 | Canonical, all-revisions, as-recorded, and recomputed data views | Investigate what was known then, what is canonical now, and why the answer changed. | P0 |
| N2 | Sample validity model for canonical, duplicate, conflict, superseded, and advisory records | Distinguish absence, duplication, correction, and disagreement instead of plotting them as equivalent values. | P0 |
| N3 | Packet-to-pixel provenance | Open the exact sample, packet, definition revision, calibration, quality state, source binding, and evidence that produced a visual mark. | P0 |
| N4 | Live/Archive/Replay runtime isolation | Move from current telemetry to history or a selected replay without contaminating live state or losing context. | P0 |
| N5 | Selected-clock investigation | Pause on a chart sample/event and make the whole console resolve at that operational instant. | P1 |
| N6 | Contact opportunity, reservation, provider-truth, and realized-contact workflows | Explain link performance in the context of what was scheduled, accepted, changed, and actually received. | P0 |
| N7 | Catalog-bound meaning and activation intervals | Guarantee that units, calibration, enums, limits, and packet definitions match the active governed revision for the selected time. | P0 |
| N8 | Spacecraft identity, SCID, profile, transport, and routing readiness | Explain “no data” as an actionable identity/routing/configuration problem when appropriate. | P0 |
| N9 | Source capability, binding, health, retention, and watermark facts | Show whether a request is supported, which source answered, and how complete/fresh the result is. | P0 |
| N10 | Historical-data request, backfill, correction, and revision-decision lifecycle | Request missing history, follow its jobs, review outcomes, and see the resulting dashboard correction in one evidence chain. | P1 |
| N11 | Dashboard runtime invalidation decision inspector | Explain why a domain event did or did not refresh a mission/dashboard/context/placement and which artifacts were invalidated. | P1 |
| N12 | Canonical operational-event evidence graph | Traverse contacts, source health, telemetry samples, limits, commands, transport actions, verifier outcomes, and runtime facts through durable IDs. | P1 |
| N13 | Auditable control actions from telemetry context | Release or review an allowed action with authorization, posture, request document, outcome, and causality preserved. | P1 |
| N14 | Constellation-native health and comparison | Fly one dashboard across a typed fleet selection and retain per-spacecraft identity, coverage, and drilldown. | P1 |
| N15 | Publish readiness based on runtime/source compatibility | Block or warn before publishing when bindings, scope, source capabilities, catalog state, or evidence contracts cannot satisfy the document. | P0 |
| N16 | Domain applications sharing dashboard context | Let typed product applications contribute telemetry, actions, and surfaces without becoming ungoverned dashboard plugins. | P2 |

## 8. Explicit non-targets

The following Grafana capabilities should remain available through Grafana or
through context-preserving links. Rebuilding them inside Cadence would dilute
the mission product and create an unbounded parity program.

- arbitrary SQL, PromQL, LogQL, TraceQL, or generic ad hoc query languages;
- a marketplace for arbitrary third-party panel JavaScript;
- generic BI, news, text, canvas, finance, and unrelated visualization use
  cases;
- infrastructure log, trace, metric, and profile exploration when the subject
  is the Cadence service rather than the spacecraft/mission domain;
- generic infrastructure alert-rule authoring and notification routing;
- replacing Grafana's organization administration for the observability stack;
- importing the full Grafana dashboard/plugin ecosystem without a typed
  compatibility boundary.

Cadence should link to infrastructure dashboards, logs, traces, and profiles
with service, mission, time, request, correlation, and trace context when those
systems contain the right answer.

## 9. Recommended sequence

### 9.1 P0: make the current surface trustworthy

Before broadening the feature catalog:

1. Fix the Data Sources page crash on `:events`.
2. Fix the current source-health event atom conversion crash observed while
   resolving dashboard source facts.
3. Give the showcase mission a catalog/source fixture that renders healthy,
   visibly current live charts and exercises a valid spacecraft context.
4. Add one browser gate that proves dashboard list → dashboard → scope/time →
   widget evidence → Explore and Source Inventory.

### 9.2 P0/P1: close the composition gap

1. Implement one explicit dashboard edit transaction with dirty, Save, Discard,
   and coherent revision semantics.
2. Turn Test binding into a real WYSIWYG candidate preview while retaining its
   request/frame/warning diagnostics.
3. Replace the widget-type select with a searchable contract-aware gallery.
4. Add duplicate, investigate, inspect, library, and remove to one consistent
   widget menu.
5. Upgrade dashboard discovery with search, sort, tags, stars, lifecycle, and
   recent activity.

### 9.3 P1: make investigation the differentiator

1. Finish cross-widget cursor, range, event, and evidence selection.
2. Add canonical contact/limit/source/backfill/revision overlays.
3. Make every empty/degraded state resolve to a specific diagnostic and a safe
   next action.
4. Add question-led domain drilldowns that preload typed context.
5. Ensure every dashboard-to-Explore/source/contact/action link round-trips the
   relevant typed context.

### 9.4 P2/P3: reuse, deployment, and wallboards

1. Add versioned widget templates/library items.
2. Add governed dashboard export/import and dashboard-as-code validation.
3. Add permission-aware sharing and read-only snapshots.
4. Add playlists and a wallboard mode only after live freshness and degraded
   states are impossible to miss.

## 10. Acceptance test for “more like Grafana”

The direction is achieved when a Grafana-literate operator can do the following
without training:

1. find or create a dashboard;
2. add, configure, preview, move, resize, duplicate, and remove a widget;
3. understand what is unsaved and either save or discard the whole edit;
4. change time, move backward/forward, zoom, refresh, and return live;
5. inspect why a widget is empty or degraded;
6. share, reuse, export, and govern a dashboard;
7. carry scope and time into a deeper investigation.

Cadence wins, rather than merely catches up, when that same operator can also:

1. switch among live, archive, and a selected replay;
2. compare canonical and historical interpretations of telemetry;
3. trace a visual value to its packet, definition, source, quality, and validity;
4. correlate telemetry with contacts, routes, source state, limits, commands, and
   operational events;
5. understand whether a source is capable, healthy, retained, and complete
   through the selected time; and
6. take an authorized, auditable domain action without leaving the investigation
   context.

That is the target: Grafana-quality dashboard mechanics with a mission control
model Grafana cannot supply.

## 11. Related Cadence documents

- [Dashboard and Ops information architecture delivery plan](dashboard-and-ops-ia-delivery-plan.md)
- [Dashboard information architecture and page structure](dashboard-information-architecture-and-page-structure.md)
- [Dashboards visualization engine design](dashboards-visualization-engine-design.md)
- [Dashboard interaction improvements](dashboard-grafana-interaction-improvements-plan.md)
- [Dashboard feature maturity checklist](dashboard-feature-maturity-checklist.md)
- [Typed extension packages and product applications](decisions/016-typed-extension-packages-and-product-applications.md)

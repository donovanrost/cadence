# Dashboard interaction improvements

Status: implementation plan, not an accepted architecture decision.

Program placement: this is W0, the active interaction foundation in the
[Dashboard and Ops information architecture delivery plan](dashboard-and-ops-ia-delivery-plan.md).

This plan turns the Grafana comparison into five bounded Cadence improvements while preserving Cadence's telemetry-first, evidence-rich operating model. It deliberately reuses the dashboard engine, typed scope context, placement expansion, evidence inspectors, and first-party widget catalog already in the product.

## 1. Prove bindings before save and make empty states actionable

Current evidence:

- Widget authoring validates structure but does not execute the candidate binding until after persistence.
- Runtime evidence can explain source, scope, time, and empty reasons, but the widget body reduces that to generic empty copy.

Implementation:

- Add an explicit `Test binding` action to the widget editor.
- Resolve a one-placement draft-preview document through the production dashboard engine without persisting it.
- Report one of `ready`, `no_data`, or `error`, together with planned request, frame, and warning counts.
- Invalidate the preview whenever form fields or selected observables change.
- Replace generic empty copy with reason-aware guidance and direct actions to adjust scope/time or inspect source/query evidence.

Acceptance criteria:

- A candidate that produces primary frames reports ready before save.
- A valid request that produces no primary frame reports no data and remains saveable.
- Contract, capability, or execution errors are visible before save; preview never makes runtime availability a prerequisite for preserving a draft.
- Preview never creates or updates a stored dashboard revision.

## 2. Correlate time across every chart

Current evidence:

- All widgets already share one runtime time context.
- Time-series charts have local cursors, but cursor position and range selection are not coordinated.

Implementation:

- Put all dashboard time-series charts in a shared uPlot cursor synchronization group.
- Enable horizontal drag selection outside edit mode.
- Convert the selected range into the dashboard's archive time context so every widget re-queries the same interval.
- Make the active range and the path back to live mode visible in the toolbar.

Acceptance criteria:

- Hovering a time-series chart aligns the cursor in peer charts.
- Dragging a chart range updates `from`, `to`, and `time_mode=archive` once for the dashboard.
- Live mode can be restored in one action and edit-mode layout interactions are unaffected.

## 3. Add operational sections and more discoverable drilldowns

Current evidence:

- Dashboards currently render one undifferentiated grid.
- Point, event, source, and evidence drilldowns exist, but primary investigation entry points are often hidden in per-widget menus.

Implementation:

- Add optional document sections with stable IDs, titles, descriptions, order, and default collapsed state.
- Let authors add, rename, reorder, collapse by default, and remove sections; let each placement choose a section.
- Render each section as a collapsible operational group with its own grid instance.
- Add a compact, first-class investigation menu for telemetry explore, source inventory, contacts, and dashboard diagnostics while preserving mission and runtime context.

Acceptance criteria:

- Existing documents without sections render unchanged.
- Section membership round-trips through document serialization and validation.
- Grid layout changes from one section update only the placements included in that event.
- Drilldowns keep mission identity and relevant dashboard query context.

## 4. Expand catalog-safe widget presentation controls

Current evidence:

- The catalog declares a small options schema, but the editor and renderer only project precision and chart window consistently.
- The chart renderer hard-codes line width, gaps, fill, axes, and legend behavior.

Implementation:

- Value tile: expose `show unit`.
- Time series: expose legend, min/max band, line width, fill opacity, gap policy, point markers, axis grouping, and shared hover values.
- Validate and persist only enumerated/ranged first-party options declared by the widget registry.
- Project options through the server component as data attributes consumed by the existing chart hook.

Acceptance criteria:

- Defaults preserve existing dashboards.
- Invalid or out-of-range option values fail authoring validation.
- Serialized options round-trip and alter only presentation, never source semantics.

## 5. Expose domain-native variables through repeat authoring

Current evidence:

- Runtime scope already supports mission, spacecraft, contact, ground station, source endpoint, transport, and link.
- Placement expansion already implements stable repeated instances, but the editor cannot author repeat declarations.

Implementation:

- Offer `Repeat for selected…` only on widget types whose catalog allows repeat scope mode.
- Let authors choose the domain (`spacecraft`, `contact`, `ground station`, `transport`, or `link`), layout (`wrap`, `row`, or `column`), and a bounded maximum instance count.
- Store the existing canonical repeat declaration and mark the binding scope mode as repeat.
- Explain that the active multi-select dashboard context supplies the repeated IDs.

Acceptance criteria:

- Repeat authoring round-trips through the editor and document schema.
- Runtime expansion keeps stable placement IDs and applies typed per-instance scope overrides.
- The editor does not offer repeat for unsupported widget types or unsupported domains.

## Verification gates

- Domain tests for document sections, placement options, repeat declarations, and range normalization.
- LiveView component/event tests using stable DOM IDs and outcome assertions.
- JavaScript tests for chart option parsing, shared cursors, and range event payloads where the asset suite supports them.
- Browser verification against representative live, archive, empty, sectioned, and repeated dashboards.
- Root `mix precommit` is the final authoritative gate after focused owning-app tests.

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "evidence_panel renders subject details, evidence links, and actions",
  "evidence_panel renders dashboard health activity link",
  "evidence_panel turns resolvable evidence refs into data link handoffs",
  "evidence_panel data links fall back to warning source context"
]

assert.equal(scenarioLedger.length, 4)

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/EvidenceInspectorPanel.vue")
const serverPath = resolve(
  __dirname,
  "../../lib/cadence_web/live/ops_dashboard_show_live/evidence_inspector_panel_components.ex"
)
const componentTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_show_live/evidence_inspector_panel_components_test.exs"
)
const handoffTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/ops_dashboard_show_live/evidence_inspector_panel_data_link_handoff_test.exs"
)

const [componentSource, serverSource, componentTestSource, handoffTestSource] =
  await Promise.all([
    readFile(componentPath, "utf8"),
    readFile(serverPath, "utf8"),
    readFile(componentTestPath, "utf8"),
    readFile(handoffTestPath, "utf8")
  ])

const frozenTestNames = [componentTestSource, handoffTestSource].flatMap((source) =>
  Array.from(source.matchAll(/^\s*test "([^"]+)"/gm), (match) => match[1])
)

assert.deepEqual(
  frozenTestNames,
  scenarioLedger,
  "the four existing evidence-panel scenarios must remain one-for-one and in place"
)

const template = componentSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const hostSource = serverSource.match(
  /def evidence_panel\(assigns\) do[\s\S]*?\n  def presentation\(assigns\) do/
)?.[0]

assert.ok(template, "EvidenceInspectorPanel.vue must have a template block")
assert.ok(hostSource, "evidence_panel/1 must expose one auditable LiveVue host boundary")
assert.equal(hostSource.match(/<\.vue/g)?.length, 1, "evidence_panel/1 must emit one LiveVue host")
assert.match(hostSource, /v-component="EvidenceInspectorPanel"/)
assert.match(hostSource, /v-ssr=\{false\}/)
assert.match(hostSource, /class="contents"/)
assert.doesNotMatch(hostSource, /v-component="ClipboardButton"/)
assert.doesNotMatch(serverSource, /defp (evidence_ref_card|evidence_rows|dashboard_actions)/)

assert.match(componentSource, /import ClipboardButton from "\.\/ClipboardButton\.vue"/)
assert.equal(
  componentSource.match(/<ClipboardButton\b/g)?.length,
  1,
  "the copy control must be directly composed once inside the parent component"
)
assert.doesNotMatch(componentSource, /v-component|<\.vue/)

assert.match(template, /<section v-bind="presentation\.root\.attrs">/)
assert.match(serverSource, /"id" => "dashboard-evidence-inspector"/)
assert.match(serverSource, /"class" => "space-y-4"/)
assert.match(serverSource, /"data-evidence-kind" => text_value\(Map\.get\(inspector, :kind\)\)/)
assert.match(
  serverSource,
  /"data-evidence-subject" => text_value\(Map\.get\(inspector, :subject\) \|\| ""\)/
)
assert.match(
  serverSource,
  /"data-evidence-status" => text_value\(Map\.get\(inspector, :status_text\) \|\| ""\)/
)
assert.match(serverSource, /"id" => "dashboard-evidence-copy-link-component"/)
assert.match(serverSource, /button_id: "dashboard-evidence-copy-link"/)
assert.match(serverSource, /"data-name" => "ClipboardButton"/)

for (const stableAttribute of [
  "data-evidence-kind",
  "data-evidence-subject",
  "data-evidence-status",
  "data-dashboard-action",
  "data-dashboard-action-kind",
  "data-dashboard-action-target",
  "data-dashboard-action-source",
  "data-dashboard-action-presentation",
  "data-dashboard-health-activity-link",
  "data-dashboard-health-activity-snapshot-id",
  "data-evidence-subject-field",
  "data-evidence-detail",
  "data-evidence-ref-kind",
  "data-evidence-ref-id",
  "data-evidence-ref-link-target",
  "data-evidence-link-target",
  "data-evidence-link-id",
  "data-evidence-link-ref",
  "data-evidence-empty"
]) {
  assert.match(serverSource, new RegExp(`"${stableAttribute}"`))
}

for (const branch of [
  "presentation.header.message",
  "presentation.actions.dashboard",
  "presentation.actions.health",
  "presentation.subject",
  "presentation.details",
  "presentation.evidence.items.length",
  "presentation.evidence.empty",
  "presentation.data_links.items.length",
  "presentation.data_links.empty"
]) {
  assert.match(template, new RegExp(branch.replaceAll(".", "\\.")))
}

assert.match(template, /:is="item\.tag"/)
assert.match(serverSource, /tag: if\(data_link, do: "button", else: "div"\)/)
assert.equal(serverSource.match(/"phx-click" => "open_data_link"/g)?.length, 2)
assert.match(serverSource, /DataLinkAttrs\.open\(/)
assert.match(handoffTestSource, /attribute\("phx-value-target"\)/)
assert.match(handoffTestSource, /attribute\("phx-value-target-id"\)/)
assert.match(handoffTestSource, /attribute\("phx-value-timestamp-ms"\)/)
assert.match(serverSource, /timestamp_ms: evidence_timestamp_ms\(evidence\)/)
assert.match(serverSource, /context_fallback: evidence_ref_context\(inspector, current_path\)/)

assert.equal(
  serverSource.match(/"data-phx-link" => "redirect"/g)?.length,
  2,
  "dashboard and health navigation must both preserve LiveView navigate semantics"
)
assert.equal(
  serverSource.match(/"data-phx-link-state" => "push"/g)?.length,
  2,
  "dashboard and health navigation must both preserve push history state"
)
assert.match(serverSource, /ActivityNavigation\.link\(current_path, :health_snapshots, activity\.event\)/)

const evidenceTargetLedger = [
  ["raw_evidence", "raw_evidence"],
  ["telemetry_sample", "telemetry_sample"],
  ["limit_event", "limit_event"],
  ["limit_definition", "limit_definition"],
  ["limit_definition_interval", "limit_definition_interval"],
  ["limit_definition_lifecycle_event", "limit_definition_lifecycle_event"],
  ["mission_event", "mission_event"],
  ["operational_event", "operational_event"],
  ["command_queue_entry", "command_queue_entry"],
  ["command_release_attempt", "command_release_attempt"],
  ["command_verifier_instance", "command_verifier_instance"],
  ["transport_action_request", "transport_action_request"],
  ["transport_capability_record", "transport_capability_record"],
  ["binding_set_interval", "binding_set_interval"],
  ["application_binding_interval", "application_binding_interval"],
  ["catalog_revision_interval", "catalog_revision_interval"],
  ["source_binding_interval", "source_binding_interval"],
  ["source_health_interval", "source_health_interval"],
  ["transport_execution_interval", "transport_execution_interval"],
  ["transport_connection_state_interval", "transport_connection_state_interval"],
  ["ground_station_connection_state_interval", "ground_station_connection_state_interval"],
  [
    "ground_station_antenna_pointing_state_interval",
    "ground_station_antenna_pointing_state_interval"
  ],
  ["link_rf_lock_state_interval", "link_rf_lock_state_interval"],
  ["link_frame_sync_state_interval", "link_frame_sync_state_interval"],
  ["source_health_event", "source_health_event"],
  ["source_watermark_event", "source_watermark_event"],
  ["source_binding_event", "source_binding_event"],
  ["telemetry_revision_decision_event", "telemetry_revision_decision_event"],
  ["telemetry_backfill_lifecycle_event", "telemetry_backfill_lifecycle_event"],
  ["contact", "contact"],
  ["scheduled_contact", "contact"],
  ["realized_contact", "contact"]
]

const evidenceTargetMapSource = serverSource.match(
  /@evidence_data_link_targets %\{([\s\S]*?)\n  \}/
)?.[1]

assert.ok(evidenceTargetMapSource)
assert.equal(
  evidenceTargetMapSource.match(/\b[a-z_]+:\s+:[a-z_]+\b/g)?.length,
  evidenceTargetLedger.length
)

for (const [kind, target] of evidenceTargetLedger) {
  assert.match(evidenceTargetMapSource, new RegExp(`\\b${kind}:\\s+:${target}\\b`))
}

assert.match(serverSource, /defp operational_interval_target\(:operational_interval, evidence\)/)
assert.match(serverSource, /:source_health_interval/)
assert.match(serverSource, /if evidence_kind\(evidence, :confidence\) == :direct, do: :operational_event/)
assert.match(serverSource, /DateTime\.to_unix\(datetime, :millisecond\)/)
assert.match(serverSource, /Map\.get\(query, "scope_id"\) \|\| Map\.get\(query, "spacecraft_id"\)/)
assert.match(serverSource, /Map\.get\(query, "scope_ids"\)/)

console.log("evidence_inspector_panel_test passed")

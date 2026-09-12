import type { ExplorationModel } from "./contracts";
export const context = { organizationId: "org", missionId: "mission" };
export function fixture(): ExplorationModel {
  return {
    version: 3,
    organization_id: "org",
    mission_id: "mission",
    query: {
      point_id: "HK.voltage",
      time_mode: "last_1h",
      source_binding_id: "binding-a",
      source_dashboard_id: "origin",
    },
    loaded_at: "2026-09-07T12:00:00.123456Z",
    origin: { status: "ready", dashboard: { id: "origin", name: "Flight overview" } },
    status: "ready",
    effective_time: {
      mode: "range",
      axis: "receipt_time",
      from: "2026-09-07T11:00:00.123456Z",
      to: "2026-09-07T12:00:00.123456Z",
    },
    rows: [
      {
        key: "a".repeat(64),
        point_id: "HK.voltage",
        sample_id: "sample/one",
        time: "2026-09-07T11:59:59.654321Z",
        axis: "receipt_time",
        value: 4.2,
        value_kind: "number",
        unit: "V",
        source: {
          data_source_id: "source-a",
          source_binding_id: "binding-a",
          dataset: "flight",
          realm: "flight",
        },
      },
    ],
    limited: false,
    warnings: [],
    warnings_limited: false,
    inspection: { status: "not_selected", sample: null },
  };
}

export function selectedFixture(): ExplorationModel {
  const model = fixture();
  model.query.sample_id = "sample/one";
  model.inspection = {
    status: "ready",
    sample: {
      point_id: "HK.voltage",
      point_name: "Battery voltage",
      sample_id: "sample/one",
      spacecraft_id: "spacecraft-a",
      receipt_time: "2026-09-07T11:59:59.654321Z",
      generation_time: "2026-09-07T11:59:58.123456Z",
      quality: "suspect",
      raw_value: { state: "ready", format: "json", text: '{"adc":1234}' },
      engineering_value: { state: "ready", format: "json", text: "4.2" },
      source: {
        data_source_id: "source-a",
        source_binding_id: "binding-a",
        realm: "flight",
        source_endpoint_id: "endpoint-a",
        replay_run_id: null,
      },
      record: {
        packet_id: "packet-7",
        evidence_id: "raw-7",
        packet_definition_id: "HK",
        packet_definition_version: 3,
        validity_state: "superseded",
      },
    },
  };
  return model;
}

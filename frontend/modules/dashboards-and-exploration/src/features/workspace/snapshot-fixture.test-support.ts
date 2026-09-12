import type {
  WorkspaceField,
  WorkspaceFrame,
  WorkspaceSnapshot,
  WorkspaceWidget,
} from "./contracts";
export const snapshotContext = {
  organizationId: "org",
  missionId: "mission",
  resourceId: "dashboard",
};
export const field = (
  name: string,
  kind: WorkspaceField["kind"],
  values: WorkspaceField["values"],
  unit: string | null = null,
): WorkspaceField => ({ name, kind, values, unit });
export const frame = (
  shape: WorkspaceFrame["shape"],
  fields: WorkspaceField[],
  role: WorkspaceFrame["role"] = "primary",
): WorkspaceFrame => ({
  shape,
  fields,
  role,
  time_axis: shape === "matrix" ? null : "generation_time",
});
export function snapshotFixture(type: WorkspaceWidget["type"] = "value_tile"): WorkspaceSnapshot {
  const frames: Record<WorkspaceWidget["type"], WorkspaceFrame[]> = {
    value_tile: [
      frame("scalar", [field("time", "time", [1000]), field("voltage", "number", [28.4], "V")]),
    ],
    time_series: [
      frame("wide", [
        field("time", "time", [1000, 2000, 3000]),
        field("voltage", "number", [28.4, null, 28.7], "V"),
      ]),
    ],
    data_table: [
      frame("scalar", [field("time", "time", [1000]), field("voltage", "number", [28.4], "V")]),
    ],
    status_matrix: [
      frame("matrix", [
        field("resource_id", "string", ["link-1"]),
        field("connection_state", "enum", ["connected"]),
        field("freshness_state", "enum", ["stale"]),
      ]),
    ],
    state_timeline: [
      frame("events", [
        field("time", "time", [1000, 2000]),
        field("normalized_state", "enum", ["green", "red"]),
        field("resource_id", "string", ["link-1", "link-1"]),
      ]),
    ],
    event_timeline: [
      frame("intervals", [
        field("starts_at", "time", [1000]),
        field("ends_at", "time", [2000]),
        field("label", "string", ["Ground station pass"]),
        field("kind", "enum", ["scheduled_contact"]),
      ]),
    ],
    constellation_health: [
      frame("matrix", [
        field("spacecraft_id", "string", ["sc-1", "sc-2"]),
        field("worst_state", "enum", ["red", null]),
      ]),
    ],
  };
  return {
    version: 1,
    organization_id: "org",
    mission_id: "mission",
    dashboard_id: "dashboard",
    document_version: 1,
    document_mode: "published",
    author: true,
    name: "Flight telemetry",
    description: null,
    grid: { columns: 12, row_height_px: 80, gap_px: 8 },
    context: {
      time_mode: "range",
      time_axis: "generation_time",
      from: "1970-01-01T00:00:00Z",
      to: "1970-01-01T00:00:04Z",
      window_seconds: 300,
      relative_duration_ms: null,
      refresh_ms: null,
      realm: "flight",
      data_view: "canonical",
      limit_mode: "observed",
      scope_kind: "spacecraft",
      scope_ids: ["sc-1"],
    },
    sections: [{ id: "power", title: "Power", description: null, collapsed: false }],
    placements: [
      {
        id: "battery",
        authored_id: "battery",
        section_id: "power",
        layout: { x: 0, y: 0, w: 6, h: 3 },
        status: "ready",
        reason: null,
        widget: {
          type,
          version: 1,
          title: "Battery",
          options: { precision: 2, window_seconds: 300 },
        },
        frames: frames[type],
        annotations: [],
        warnings: [],
      },
    ],
    warnings: [],
  };
}

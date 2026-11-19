import type { WidgetType } from "./model/snapshot.ts";
/**
 * D5 payloads as JSON (what the server sends), for decoder and screen tests. The snapshot mirrors
 * `Cadence.Reads.Dashboards.WorkspaceSnapshot`; ported from the module's snapshot fixture.
 */
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type Field = { name: string; kind: string; unit: string | null; values: Json[] };

export const field = (
  name: string,
  kind: string,
  values: Json[],
  unit: string | null = null,
): Field => ({
  name,
  kind,
  unit,
  values,
});
export const frame = (shape: string, fields: Field[], role = "primary") => ({
  role,
  shape,
  time_axis: shape === "matrix" ? null : "generation_time",
  fields,
});

const frames: Partial<Record<WidgetType, ReturnType<typeof frame>[]>> = {
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
    frame("scalar", [field("time", "time", [1000]), field("limit_state", "enum", ["red"])]),
  ],
  constellation_health: [
    frame("matrix", [
      field("spacecraft_id", "string", ["sc-1", "sc-2"]),
      field("worst_state", "enum", ["red", null]),
    ]),
  ],
};

export function snapshotJson(type: WidgetType = "value_tile") {
  return {
    version: 1,
    organization_id: "org",
    mission_id: "mission",
    dashboard_id: "dashboard",
    document_version: 3,
    document_mode: "published",
    author: false,
    name: "Bus overview",
    description: null,
    grid: { columns: 12, row_height_px: 80, gap_px: 8 },
    context: {
      time_mode: "live",
      time_axis: "generation_time",
      from: null,
      to: null,
      window_seconds: 21_600,
      relative_duration_ms: null,
      refresh_ms: 2000,
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
        frames: structuredClone(frames[type] ?? []),
        annotations: [],
        warnings: [],
      },
      {
        id: "gone",
        authored_id: "gone",
        section_id: null,
        layout: { x: null, y: null, w: 4, h: 2 },
        status: "unavailable",
        reason: "unsupported_widget",
        widget: null,
        frames: [],
        annotations: [],
        warnings: [],
      },
    ],
    warnings: [],
  };
}

export function viewJson(type: WidgetType = "value_tile") {
  return {
    dashboard: {
      id: "dashboard",
      name: "Bus overview",
      description: null,
      tags: ["power"],
      current_version: 3,
      updated_at: "2026-11-13T02:51:00Z",
    },
    can_edit: false,
    scope_options: [
      { id: "sc-1", name: "EARENDIL-312" },
      { id: "sc-2", name: "EARENDIL-313" },
    ],
    snapshot: snapshotJson(type),
    resolved_at: "2026-11-13T02:52:10Z",
  };
}

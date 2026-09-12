import { expect, test } from "vite-plus/test";
import { readWorkspaceSnapshot } from "./validation";
import type { WorkspaceSnapshot } from "./contracts";
const context = { organizationId: "org", missionId: "mission", resourceId: "dashboard" };
function fixture(): WorkspaceSnapshot {
  return {
    version: 1,
    organization_id: "org",
    mission_id: "mission",
    dashboard_id: "dashboard",
    document_version: 3,
    document_mode: "published",
    author: false,
    name: "Flight telemetry",
    description: null,
    grid: { columns: 12, row_height_px: 64, gap_px: 8 },
    context: {
      time_mode: "live",
      time_axis: "generation_time",
      from: null,
      to: null,
      window_seconds: 300,
      relative_duration_ms: null,
      refresh_ms: 1000,
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
        layout: { x: 0, y: 0, w: 3, h: 2 },
        status: "ready",
        reason: null,
        widget: {
          type: "value_tile",
          version: 1,
          title: "Battery voltage",
          options: { precision: 2, window_seconds: 300, show_unit: true },
        },
        frames: [
          {
            role: "primary",
            shape: "scalar",
            time_axis: "generation_time",
            fields: [
              { name: "time", kind: "time", unit: null, values: [1_783_000_000_000] },
              { name: "voltage", kind: "number", unit: "V", values: [28.4] },
            ],
          },
        ],
        annotations: [],
        warnings: [],
      },
    ],
    warnings: [],
  };
}
test("admits versioned, resource-bound published data and all seven widget kinds", () => {
  for (const type of [
    "value_tile",
    "time_series",
    "status_matrix",
    "data_table",
    "state_timeline",
    "event_timeline",
    "constellation_health",
  ] as const) {
    const model = fixture();
    model.placements[0].widget!.type = type;
    expect(readWorkspaceSnapshot(model, context)).toBe(model);
  }
});
test("keeps unavailable placements explicit and admits temporal annotations", () => {
  const model = fixture();
  model.placements[0].annotations.push({
    id: "contact",
    title: "Contact",
    severity: "info",
    kind: "interval",
    starts_at_ms: 10,
    ends_at_ms: 20,
  });
  model.placements.push({
    id: "missing",
    authored_id: "missing",
    section_id: null,
    layout: { x: null, y: null, w: 4, h: 2 },
    status: "unavailable",
    reason: "unsupported_widget",
    widget: null,
    frames: [],
    annotations: [],
    warnings: [],
  });
  expect(readWorkspaceSnapshot(model, context).placements).toHaveLength(2);
});
test("rejects context mismatch, draft authority, unknown versions and unknown metadata", () => {
  for (const override of [
    { organizationId: "foreign" },
    { missionId: "foreign" },
    { resourceId: "foreign" },
    { resourceId: undefined },
  ]) {
    expect(() => readWorkspaceSnapshot(fixture(), { ...context, ...override })).toThrow();
  }
  for (const override of [
    { version: 2 },
    { document_version: 0 },
    { document_mode: "draft" },
    { secret: "endpoint" },
  ]) {
    expect(() => readWorkspaceSnapshot({ ...fixture(), ...override }, context)).toThrow();
  }
  expect(
    readWorkspaceSnapshot({ ...fixture(), document_mode: "draft", author: true }, context)
      .document_mode,
  ).toBe("draft");
});
test("rejects duplicate identities, orphan sections, unaligned or mistyped frame data and unsafe numeric values", () => {
  const mutations: Array<(m: WorkspaceSnapshot) => void> = [
    (m) => m.placements.push(m.placements[0]),
    (m) => m.sections.push(m.sections[0]),
    (m) => {
      m.placements[0].section_id = "absent";
    },
    (m) => {
      m.placements[0].frames[0].fields[1].values.push(29);
    },
    (m) => {
      m.placements[0].frames[0].fields[1].values = ["not numeric"];
    },
    (m) => {
      m.placements[0].frames[0].fields[1].values = [Infinity];
    },
    (m) => {
      m.placements[0].frames[0].fields[1].values = [Number.MAX_SAFE_INTEGER + 1];
    },
    (m) => {
      m.placements[0].frames[0].fields[1].name = "time";
    },
    (m) => {
      m.placements[0].layout.w = 0;
    },
    (m) => {
      m.placements[0].status = "unavailable";
    },
    (m) => {
      (m.placements[0].frames[0] as any).metadata = { credentials: "secret" };
    },
  ];
  for (const mutate of mutations) {
    const model = fixture();
    mutate(model);
    expect(() => readWorkspaceSnapshot(model, context)).toThrow();
  }
});

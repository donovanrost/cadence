/** Wire fixtures in the proposed D14/D17/D18 shapes (docs/apogee/plans/dashboards-settings.md). */
const mira = { id: "u1", name: "Mira K." };

export const settingsWire = {
  dashboard: {
    id: "dash_ops",
    name: "Ops overview",
    description: "Power and comms at a glance.",
    tags: ["ops", "power"],
    lifecycle: "active",
    current_version: 7,
    published_version: 7,
  },
  defaults: {
    time: { mode: "relative", range: "now-6h", from: null, to: null },
    scope: { mode: "context", spacecraft_id: null },
  },
  limits: { name: 120, description: 500, tags: 32, tag: 64 },
  shares: {
    rows: [
      {
        id: "shr_1",
        url: "/console/reflect/earendil/telemetry/dashboards/shares/shr_1",
        data_visibility: "authorized_runtime_data",
        state: "active",
        expires_at: "2026-11-20T00:00:00Z",
        created_at: "2026-11-12T21:00:00Z",
        created_by: mira,
      },
    ],
    next: null,
  },
  snapshots: {
    rows: [
      {
        id: "snp_1",
        url: "/console/reflect/earendil/telemetry/dashboards/snapshots/snp_1",
        version: 7,
        data_visibility: "with_data",
        window: { from: "2026-11-12T21:00:00Z", to: "2026-11-12T23:00:00Z" },
        created_at: "2026-11-12T23:02:00Z",
        created_by: mira,
      },
    ],
    next: null,
  },
};

export const activityWire = {
  events: [
    {
      id: "e2",
      kind: "saved",
      at: "2026-11-12T22:40:00Z",
      actor: mira,
      version: 7,
      detail: "Updated dashboard settings",
    },
    {
      id: "e1",
      kind: "share_created",
      at: "2026-11-12T21:00:00Z",
      actor: mira,
      version: null,
      detail: "With data · expires 11-20",
    },
  ],
  next: "e1",
};

const src = (cache: "fresh" | "cached" | null, action: string | null) => ({
  logical_source: "telemetry",
  status: "ok",
  status_code: "executed",
  cache,
  cache_status: cache,
  severity: null,
  retryable: null,
  operator_action: action,
  warning_codes: [],
  duration_ms: null,
  outcome: null,
  error: null,
});

export const diagnosticsWire = {
  version: 7,
  loaded_at: "2026-11-13T02:40:00Z",
  widgets: [
    {
      placement_id: "p1",
      title: "Bus voltage",
      status: "ok",
      sources: [src("fresh", null)],
      warnings: [],
    },
    {
      placement_id: "p2",
      title: "Downlink rate",
      status: "degraded",
      sources: [src("cached", "Check the Svalbard data source.")],
      warnings: [
        { code: "source_unavailable", severity: "warning", field_name: null, message: null },
      ],
    },
  ],
};

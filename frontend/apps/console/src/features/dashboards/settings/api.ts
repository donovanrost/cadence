import { API_BASE, decoders as d, request, type ApiResult, type Decoded, type Reader } from "@/api";

/**
 * Dashboard settings (slice 5, L8): D14–D19 as proposed in docs/apogee/plans/dashboards-settings.md
 * (api reviewing; fixtures until it ships). Base `/missions/:m/dashboards/:id`.
 */
const base = (missionId: string, dashboardId: string) =>
  `/missions/${encodeURIComponent(missionId)}/dashboards/${encodeURIComponent(dashboardId)}`;

/** The domain sends a null name when the user is gone (dashboards). */
const actor = d.nullable(
  d.object({ id: d.optional(d.nullable(d.token)), name: d.nullable(d.string) }),
);

/** api sends `with_data | definition_only`; the domain's `authorized_runtime_data` reads as `with_data`. */
const visibilityWire = d.known([
  "with_data",
  "definition_only",
  "authorized_runtime_data",
] as const);
const visibility: Reader<DataVisibility | "unrecognized"> = (value, path = "") => {
  const v = visibilityWire(value, path);
  return v === "authorized_runtime_data" ? "with_data" : v;
};
export type DataVisibility = "with_data" | "definition_only";

const timeDefault = d.nullable(
  d.object({
    // oneOf, not known: an unknown default can't be edited safely, so the read should fail loudly.
    mode: d.oneOf(["relative", "absolute"] as const),
    range: d.optional(d.nullable(d.string)),
    from: d.optional(d.nullable(d.timestamp)),
    to: d.optional(d.nullable(d.timestamp)),
  }),
);
const scopeDefault = d.nullable(
  d.object({
    mode: d.oneOf(["context", "fixed", "fleet"] as const),
    spacecraft_id: d.optional(d.nullable(d.token)),
  }),
);
export type TimeDefault = Decoded<typeof timeDefault>;
export type ScopeDefault = Decoded<typeof scopeDefault>;

/** Exported: dashboards' D20 shared views read the same rows (one reader, lead). */
export const shareRow = d.object({
  id: d.token,
  url: d.string,
  data_visibility: visibility,
  state: d.known(["active", "expired", "revoked"] as const),
  expires_at: d.nullable(d.timestamp),
  created_at: d.timestamp,
  created_by: actor,
});
export const snapshotRow = d.object({
  id: d.token,
  url: d.string,
  version: d.integer,
  data_visibility: visibility,
  window: d.nullable(d.object({ from: d.timestamp, to: d.timestamp })),
  created_at: d.timestamp,
  created_by: actor,
});
export type Share = Decoded<typeof shareRow>;
export type Snapshot = Decoded<typeof snapshotRow>;
const page = <T>(row: Reader<T>) =>
  d.object({ rows: d.array(row, 200), next: d.nullable(d.string) });

export const settingsReader = d.object({
  dashboard: d.object({
    id: d.token,
    name: d.string,
    description: d.string,
    tags: d.array(d.string, 64),
    lifecycle: d.known(["active", "archived"] as const),
    current_version: d.integer,
    published_version: d.nullable(d.integer),
    updated_at: d.nullable(d.timestamp),
    updated_by: actor,
  }),
  defaults: d.object({ time: timeDefault, scope: scopeDefault }),
  limits: d.object({ name: d.integer, description: d.integer, tags: d.integer, tag: d.integer }),
  shares: page(shareRow),
  snapshots: page(snapshotRow),
});
export type DashboardSettings = Decoded<typeof settingsReader>;

export type SettingsKey = Readonly<{ missionId: string; dashboardId: string }>;

export function fetchSettings(
  k: SettingsKey,
  signal: AbortSignal,
): Promise<ApiResult<DashboardSettings>> {
  return request(`${base(k.missionId, k.dashboardId)}/settings`, settingsReader, { signal });
}

export type GeneralInput = Readonly<{
  name: string;
  description: string;
  tags: readonly string[];
  defaults: Readonly<{ time: TimeDefault; scope: ScopeDefault }>;
  expected_version: number;
}>;

/** D15: a current version through CurrentVersions (Q1); 409 version_conflict, 422 by field. */
export function saveGeneral(k: SettingsKey, body: GeneralInput) {
  return request(base(k.missionId, k.dashboardId), d.object({ version: d.integer }), {
    method: "PATCH",
    body,
  });
}

/** D3: archive; 409 in_use with `used_by.playlists` unless confirmed. */
export function archiveDashboard(k: SettingsKey, confirm: boolean) {
  return request(`${base(k.missionId, k.dashboardId)}/archive`, () => null, {
    method: "POST",
    body: confirm ? { confirm: true } : {},
  });
}

export function createShare(
  k: SettingsKey,
  body: Readonly<{ data_visibility: DataVisibility; expires_at: string | null }>,
) {
  return request(`${base(k.missionId, k.dashboardId)}/shares`, shareRow, { method: "POST", body });
}

export function revokeShare(k: SettingsKey, shareId: string) {
  return request(
    `${base(k.missionId, k.dashboardId)}/shares/${encodeURIComponent(shareId)}`,
    shareRow,
    {
      method: "DELETE",
    },
  );
}

/**
 * D16 snapshot (Q5, domain): always a frozen window. The viewer's ⋯ menu sends its current range made
 * absolute; Settings sends the default range resolved at the moment of creation. 422 without from/to.
 */
export function postSnapshot(
  missionId: string,
  dashboardId: string,
  body: Readonly<{
    data_visibility: DataVisibility;
    runtime: Readonly<{ from: string; to: string; spacecraft_id: string | null }>;
  }>,
) {
  return request(`${base(missionId, dashboardId)}/snapshots`, snapshotRow, {
    method: "POST",
    body,
  });
}

export const activityKinds = [
  "saved",
  "restored",
  "published",
  "archived",
  "unarchived",
  "share_created",
  "share_revoked",
  "snapshot_taken",
  "exported",
] as const;
const activityReader = d.object({
  events: d.array(
    d.object({
      id: d.token,
      kind: d.known(activityKinds),
      at: d.timestamp,
      actor,
      version: d.nullable(d.integer),
      detail: d.nullable(d.string),
    }),
    200,
  ),
  next: d.nullable(d.string),
});
export type ActivityPage = Decoded<typeof activityReader>;
export type ActivityKind = (typeof activityKinds)[number];
export type ActivityEvent = ActivityPage["events"][number];

export function fetchActivity(
  k: SettingsKey & Readonly<{ before: string | null }>,
  signal: AbortSignal,
): Promise<ApiResult<ActivityPage>> {
  const q = k.before ? `?before=${encodeURIComponent(k.before)}` : "";
  return request(`${base(k.missionId, k.dashboardId)}/activity${q}`, activityReader, { signal });
}

export const severities = ["info", "warning", "error"] as const;
const source = d.object({
  logical_source: d.string,
  // Open: the domain's execution words (planned, executed, …), shown only in Technical details.
  status: d.string,
  // Open: the raw cache result, shown only in Technical details; `cache` is the verdict the tab reads.
  cache_status: d.nullable(d.string),
  /** Asked of api: the cache verdict in two words; null when unknown. */
  cache: d.nullable(d.known(["fresh", "cached"] as const)),
  severity: d.nullable(d.known(severities)),
  retryable: d.nullable(d.boolean),
  operator_action: d.nullable(d.string),
  // Open: domain warning codes, shown only in Technical details (the words come from `message`).
  warning_codes: d.array(d.string, 50),
  // Not recorded yet (gap 5): stay null; the console shows no numbers (ux, U20).
  duration_ms: d.nullable(d.integer),
  outcome: d.nullable(d.known(["ok", "timed_out", "failed"] as const)),
  error: d.nullable(d.string),
});
const diagnosticsReader = d.object({
  version: d.integer,
  loaded_at: d.timestamp,
  widgets: d.array(
    d.object({
      placement_id: d.token,
      title: d.string,
      status: d.known(["ok", "degraded", "failed", "planned"] as const),
      sources: d.array(source, 50),
      warnings: d.array(
        d.object({
          // Open: domain warning codes; the tab shows `message` and keeps the code for details.
          code: d.string,
          severity: d.known(severities),
          field_name: d.nullable(d.string),
          /** Asked of api: the warning in words. */
          message: d.nullable(d.string),
        }),
        100,
      ),
    }),
    500,
  ),
  refresh: d.nullable(
    d.object({
      observed_at: d.timestamp,
      // Open: the refresh decision's domain word, for Technical details only.
      decision_status: d.string,
      context_reason: d.nullable(d.string),
    }),
  ),
});
export type Diagnostics = Decoded<typeof diagnosticsReader>;
export type WidgetDiagnostics = Diagnostics["widgets"][number];

export function fetchDiagnostics(
  k: SettingsKey,
  signal: AbortSignal,
): Promise<ApiResult<Diagnostics>> {
  return request(`${base(k.missionId, k.dashboardId)}/diagnostics`, diagnosticsReader, { signal });
}

/** D19: the bundle as an attachment (records the export). A plain link downloads it. */
export const exportUrl = (k: SettingsKey) =>
  `${API_BASE}${base(k.missionId, k.dashboardId)}/export`;

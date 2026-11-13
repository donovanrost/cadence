import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  API_BASE,
  decoders as d,
  orNull,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api";

/**
 * Dashboard settings (slice 5, L8): D14–D19, api's contract docs/apogee/api/dashboards.md (D14–D16
 * f4ef739b9). Base `/missions/:m/dashboards/:id`.
 */
const base = (missionId: MissionId, dashboardId: string) =>
  `/missions/${encodeURIComponent(missionId)}/dashboards/${encodeURIComponent(dashboardId)}`;

/** Who did it: the shared entity (typing §12 A5); the name is null when the user is gone. */
const actor = orNull(sharedActor);

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
  }),
  defaults: d.object({ time: timeDefault, scope: scopeDefault }),
  limits: d.object({ name: d.integer, description: d.integer, tags: d.integer, tag: d.integer }),
  shares: page(shareRow),
  snapshots: page(snapshotRow),
});
export type DashboardSettings = Decoded<typeof settingsReader>;

export type SettingsKey = Readonly<{ missionId: MissionId; dashboardId: string }>;

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
  return request(`${base(k.missionId, k.dashboardId)}/settings`, d.object({ version: d.integer }), {
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
  missionId: MissionId,
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
/** api fc222221: widget and source status are a closed four; the engine's outcome is `status_code`. */
export const diagnosticStates = ["ok", "degraded", "failed", "not_run"] as const;
/** Detail rows are display key/values, so a flag may arrive as text ("true") or a boolean. */
const flag: Reader<boolean | null> = (value, path = "") => {
  if (value === null || value === undefined) return null;
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "false") return value === "true";
  throw new d.DecodeError(path, "boolean");
};
const source = d.object({
  // free-text: the logical source's name (a data source key), shown in Technical details.
  logical_source: d.nullable(d.string),
  status: d.known(diagnosticStates),
  // free-text: the engine's raw outcome (SourceExecutionSemantics), for Technical details only.
  status_code: d.nullable(d.string),
  cache: d.nullable(d.known(["fresh", "cached"] as const)),
  // free-text: the raw cache result, for Technical details only.
  cache_status: d.nullable(d.string),
  severity: d.nullable(d.known(severities)),
  retryable: flag,
  // free-text: what the operator can do, as the server's sentence.
  operator_action: d.nullable(d.string),
  // free-text: domain warning codes, for Technical details (the tab shows `message`).
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
      title: d.nullable(d.string),
      status: d.known(diagnosticStates),
      sources: d.array(source, 50),
      warnings: d.array(
        d.object({
          // free-text: domain warning codes; the tab shows `message` and keeps the code for details.
          code: d.string,
          severity: d.known(severities),
          field_name: d.nullable(d.string),
          /** The warning in words; null until api has words for it. */
          message: d.nullable(d.string),
        }),
        100,
      ),
    }),
    500,
  ),
  // `refresh` isn't read: nothing records invalidation decisions any more (lead, L8c); api drops it.
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

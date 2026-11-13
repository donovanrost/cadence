import type { MissionId } from "@/api/index.ts";
import {
  DecodeError,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api";
import { workspaceSnapshot } from "./model/snapshot.ts";

/**
 * Dashboards endpoints (plans/dashboards.md, "D5 proposed shape"). Base
 * `/api/console/v1/missions/:m/dashboards`. Invalidation: `dashboards` (document) plus
 * `telemetry`, `limits`, `alarms`, `events` (data).
 */

const dashboardHead = d.object({
  id: d.token,
  name: d.string,
  description: d.nullable(d.string),
  tags: d.array(d.string, 64),
  current_version: d.nullable(d.integer),
  updated_at: d.nullable(d.timestamp),
});

const viewShape = d.object({
  dashboard: dashboardHead,
  can_edit: d.boolean,
  scope_options: d.array(d.object({ id: d.token, name: d.string }), 1000),
  /** null: never made current, and the viewer isn't an author. */
  snapshot: d.nullable(workspaceSnapshot),
  resolved_at: d.timestamp,
});

/** The view is for the dashboard and mission asked for; a snapshot of anything else is refused. */
function viewFor(missionId: MissionId, dashboardId: string): Reader<Decoded<typeof viewShape>> {
  return (value, path = "") => {
    const view = viewShape(value, path);
    if (view.dashboard.id !== dashboardId)
      throw new DecodeError(`${path}.dashboard.id`, dashboardId);
    const s = view.snapshot;
    if (s && (s.dashboard_id !== dashboardId || s.mission_id !== missionId))
      throw new DecodeError(`${path}.snapshot`, `dashboard ${dashboardId} of mission ${missionId}`);
    return view;
  };
}

export type DashboardView = Decoded<typeof viewShape>;

/** The viewer's runtime, as URL query text (`now-6h`/`now` or ISO bounds; empty = defaults). */
export type Runtime = Readonly<{ from: string; to: string; spacecraftId: string }>;

export function fetchDashboard(
  missionId: MissionId,
  dashboardId: string,
  runtime: Runtime,
  signal?: AbortSignal,
): Promise<ApiResult<DashboardView>> {
  const params = new URLSearchParams();
  if (runtime.from && runtime.to) {
    params.set("from", runtime.from);
    params.set("to", runtime.to);
  }
  if (runtime.spacecraftId) params.set("spacecraft_id", runtime.spacecraftId);
  const query = params.toString();
  const path = `/missions/${encodeURIComponent(missionId)}/dashboards/${encodeURIComponent(dashboardId)}`;
  return request(
    query ? `${path}?${query}` : path,
    viewFor(missionId, dashboardId),
    signal ? { signal } : {},
  );
}

import type { MissionId } from "@/api/index.ts";
import {
  DecodeError,
  decoders as d,
  isError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api";
import type { Runtime } from "../api.ts";
import { outline } from "../editor/contracts.ts";
import { workspaceSnapshot } from "../model/snapshot.ts";
import { shareRow, snapshotRow } from "../settings/api.ts";

/**
 * D20 shared views (api f622f0772, contract dashboards.md §D20): a share link (live, current
 * version) or a snapshot (frozen window, stored document). `definition` draws the grid, null when
 * the dashboard has no current version; `snapshot` is null when the link shares the definition
 * only. Rows reuse Settings' readers (one definition).
 */
const shape = d.object({
  kind: d.oneOf(["share", "snapshot"] as const),
  share: d.nullable(shareRow),
  snapshot_row: d.nullable(snapshotRow),
  dashboard: d.object({ id: d.token, name: d.string, description: d.nullable(d.string) }),
  definition: d.nullable(outline),
  snapshot: d.nullable(workspaceSnapshot),
});
export type SharedView = Decoded<typeof shape>;

/** The row matches the kind, and the data (if any) is the shared dashboard's. */
const sharedView: Reader<SharedView> = (value, path = "") => {
  const v = shape(value, path);
  if (
    (v.kind === "share") !== (v.share !== null) ||
    (v.kind === "snapshot") !== (v.snapshot_row !== null)
  )
    throw new DecodeError(path, "a row matching its kind");
  if (v.snapshot && v.snapshot.dashboard_id !== v.dashboard.id)
    throw new DecodeError(`${path}.snapshot`, `dashboard ${v.dashboard.id}`);
  return v;
};

const mission = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}`;

export function fetchShare(
  missionId: MissionId,
  shareId: string,
  runtime: Runtime,
  signal?: AbortSignal,
): Promise<ApiResult<SharedView>> {
  // A share is live: the viewer's window and spacecraft apply (api d8de53662; 422 runtime.* if bad).
  const p = new URLSearchParams();
  if (runtime.from && runtime.to) {
    p.set("from", runtime.from);
    p.set("to", runtime.to);
  }
  if (runtime.spacecraftId) p.set("spacecraft_id", runtime.spacecraftId);
  const q = p.toString();
  return request(
    `${mission(missionId)}/dashboard-shares/${encodeURIComponent(shareId)}${q ? `?${q}` : ""}`,
    sharedView,
    signal ? { signal } : {},
  );
}

export function fetchSnapshot(
  missionId: MissionId,
  snapshotId: string,
  signal?: AbortSignal,
): Promise<ApiResult<SharedView>> {
  return request(
    `${mission(missionId)}/dashboard-snapshots/${encodeURIComponent(snapshotId)}`,
    sharedView,
    signal ? { signal } : {},
  );
}

export type EndedLink = Readonly<{ kind: "revoked" | "expired" | "deleted"; message: string }>;
/**
 * A link that ended: 404 `share_revoked` / `share_expired` / `snapshot_deleted`. The message is
 * the sentence the page shows ("Revoked 11-14 02:10Z.", "Deleted by Mira K. on 11-14."); the
 * page says which in its headline.
 */
export function endedLink(error: ApiError): EndedLink | null {
  if (error.kind !== "not_found") return null;
  if (isError(error, "share_revoked")) return { kind: "revoked", message: error.message };
  if (isError(error, "share_expired")) return { kind: "expired", message: error.message };
  if (isError(error, "snapshot_deleted")) return { kind: "deleted", message: error.message };
  return null;
}

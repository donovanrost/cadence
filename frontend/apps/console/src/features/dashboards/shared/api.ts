import {
  DecodeError,
  decoders as d,
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
 * D20 shared views (plans/dashboards-slice6.md): a share link (live, current version) or a
 * snapshot (frozen window, stored document). `definition` always draws the grid; `snapshot` is
 * null when the link shares the definition only. Rows reuse Settings' readers (one definition).
 */
const shape = d.object({
  kind: d.oneOf(["share", "snapshot"] as const),
  share: d.nullable(shareRow),
  snapshot_row: d.nullable(snapshotRow),
  dashboard: d.object({ id: d.token, name: d.string, description: d.nullable(d.string) }),
  definition: outline,
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

const mission = (missionId: string) => `/missions/${encodeURIComponent(missionId)}`;

export function fetchShare(
  missionId: string,
  shareId: string,
  runtime: Runtime,
  signal?: AbortSignal,
): Promise<ApiResult<SharedView>> {
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
  missionId: string,
  snapshotId: string,
  signal?: AbortSignal,
): Promise<ApiResult<SharedView>> {
  return request(
    `${mission(missionId)}/dashboard-snapshots/${encodeURIComponent(snapshotId)}`,
    sharedView,
    signal ? { signal } : {},
  );
}

/**
 * A share that ended: 404 `share_revoked` / `share_expired`. The console's 404 error keeps code
 * and message only (no details), so the page says which, in the server's words for when.
 */
export function endedShare(
  error: ApiError,
): { kind: "revoked" | "expired"; message: string } | null {
  if (error.kind !== "not_found") return null;
  if (error.code === "share_revoked") return { kind: "revoked", message: error.message };
  if (error.code === "share_expired") return { kind: "expired", message: error.message };
  return null;
}

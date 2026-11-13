import { DecodeError, decoders as d, type Decoded, type Reader } from "@/api";
import { context, placement, workspaceSnapshot, type WorkspaceSnapshot } from "./snapshot.ts";

/**
 * C1 `view` pushes (plans/dashboards-live.md) and how they apply to the snapshot on screen.
 * A full push replaces it; a delta replaces changed placements by id, drops removed ones and
 * takes the new context. Pure: the channel composable owns ordering (`seq`) and resubscribes.
 */
const pushShape = d.object({
  seq: d.integer,
  full: d.boolean,
  version: d.integer,
  resolved_at: d.timestamp,
  context,
  snapshot: d.nullable(workspaceSnapshot),
  placements: d.array(placement, 1024),
  removed: d.array(d.token, 1024),
});
export type ViewPush = Decoded<typeof pushShape>;

/** A full push carries the snapshot and nothing else; a delta carries no snapshot. */
export const viewPush: Reader<ViewPush> = (value, path = "") => {
  const p = pushShape(value, path);
  if (p.full !== (p.snapshot !== null))
    throw new DecodeError(`${path}.snapshot`, "a snapshot exactly when full");
  if (p.full && (p.placements.length > 0 || p.removed.length > 0))
    throw new DecodeError(`${path}.placements`, "no deltas on a full push");
  return p;
};

export const versionEvent = d.object({
  current_version: d.integer,
  saved_by: d.nullable(
    d.object({ kind: d.string, id: d.nullable(d.string), name: d.nullable(d.string) }),
  ),
  saved_at: d.nullable(d.timestamp),
  archived: d.optional(d.boolean),
});
export type VersionEvent = Decoded<typeof versionEvent>;

export type Applied =
  | { ok: true; snapshot: WorkspaceSnapshot }
  | { ok: false; reason: "no_base" | "version_mismatch" };

export function applyPush(current: WorkspaceSnapshot | null, push: ViewPush): Applied {
  if (push.snapshot) return { ok: true, snapshot: push.snapshot };
  if (!current) return { ok: false, reason: "no_base" };
  if (current.document_version !== push.version) return { ok: false, reason: "version_mismatch" };
  const changed = new Map(push.placements.map((p) => [p.id, p]));
  const removed = new Set(push.removed);
  const kept = current.placements
    .filter((p) => !removed.has(p.id))
    .map((p) => changed.get(p.id) ?? p);
  const known = new Set(current.placements.map((p) => p.id));
  const added = push.placements.filter((p) => !known.has(p.id));
  return {
    ok: true,
    snapshot: { ...current, context: push.context, placements: [...kept, ...added] },
  };
}

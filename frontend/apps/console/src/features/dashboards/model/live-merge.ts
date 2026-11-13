import { DecodeError, decoders as d, type Decoded, type Reader, actor } from "@/api";
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
  /** null only on a full push for a dashboard with no current version (no snapshot to show). */
  context: d.nullable(context),
  snapshot: d.nullable(workspaceSnapshot),
  placements: d.array(placement, 1024),
  removed: d.array(d.token, 1024),
});
export type ViewPush = Decoded<typeof pushShape>;

/** A full push carries no deltas; a delta carries no snapshot, and always the new context. */
export const viewPush: Reader<ViewPush> = (value, path = "") => {
  const p = pushShape(value, path);
  if (p.full && (p.placements.length > 0 || p.removed.length > 0))
    throw new DecodeError(`${path}.placements`, "no deltas on a full push");
  if (!p.full && (p.snapshot !== null || p.context === null))
    throw new DecodeError(`${path}.snapshot`, "a delta: no snapshot, and a context");
  return p;
};

/** C1 `version` (api-ops 30295106): always this shape; `archived` stops the pushes. */
export const versionEvent = d.object({
  current_version: d.integer,
  saved_by: d.nullable(actor),
  saved_at: d.nullable(d.timestamp),
  archived: d.boolean,
});
export type VersionEvent = Decoded<typeof versionEvent>;

/** What the pushes have built: the board, and the document version the server resolved it for. */
export type LiveBoard = Readonly<{ snapshot: WorkspaceSnapshot | null; version: number }>;
export type Applied =
  | { ok: true; board: LiveBoard }
  | { ok: false; reason: "no_base" | "version_mismatch" };

export function applyPush(board: LiveBoard | null, push: ViewPush): Applied {
  if (push.full) return { ok: true, board: { snapshot: push.snapshot, version: push.version } };
  const current = board?.snapshot;
  if (!board || !current || !push.context) return { ok: false, reason: "no_base" };
  // The channel versions deltas by its own document version: compare with the last full push.
  if (board.version !== push.version) return { ok: false, reason: "version_mismatch" };
  const changed = new Map(push.placements.map((p) => [p.id, p]));
  const removed = new Set(push.removed);
  const kept = current.placements
    .filter((p) => !removed.has(p.id))
    .map((p) => changed.get(p.id) ?? p);
  const known = new Set(current.placements.map((p) => p.id));
  const added = push.placements.filter((p) => !known.has(p.id));
  return {
    ok: true,
    board: {
      version: board.version,
      snapshot: { ...current, context: push.context, placements: [...kept, ...added] },
    },
  };
}

/**
 * The pushed snapshot, only when it is at least as new as the head the D5 read returned. A re-read
 * after this browser's own save or restore (or with the channel down) must not be hidden behind
 * an older push (qa: the board lagged one version).
 */
export function liveSnapshot(
  board: LiveBoard | null,
  headVersion: number | null,
): WorkspaceSnapshot | null {
  if (!board?.snapshot) return null;
  return board.version >= (headVersion ?? 0) ? board.snapshot : null;
}

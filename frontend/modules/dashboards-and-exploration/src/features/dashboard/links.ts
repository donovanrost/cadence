import type { WorkspaceSnapshot } from "../workspace/contracts";

/** Diagnostics inspects the published document in this snapshot's runtime context. */
export function diagnosticsHref(base: string, snapshot: WorkspaceSnapshot | null): string | null {
  if (!snapshot || snapshot.context.time_mode === "replay_run") return null;
  const context = snapshot.context;
  const query = new URLSearchParams({
    time_mode: context.time_mode,
    time_axis: context.time_axis,
    realm: context.realm,
    selection_view: context.data_view,
    limit_mode: context.limit_mode,
  });
  if (context.time_mode !== "live") {
    if (!context.from || !context.to) return null;
    query.set("from", context.from);
    query.set("to", context.to);
  }
  return `${base}/diagnostics?${query}`;
}

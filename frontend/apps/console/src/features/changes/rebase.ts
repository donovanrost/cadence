import { decoders as d, request, type ApiResult } from "@/api";
import type { Preview } from "./actions.ts";

/** Changes.md K1: a conflicting staged op is rebased onto the live revision: keep mine / take live. */
export type RebaseChoice = "keep_mine" | "take_live";

const rebased = d.object({ change_set_id: d.token, version: d.integer, state: d.token });

export function rebaseOp(
  missionId: string,
  opId: string,
  choice: RebaseChoice,
): Promise<ApiResult<{ change_set_id: string; version: number; state: string }>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/config/ops/${encodeURIComponent(opId)}/rebase`,
    rebased,
    { method: "POST", body: { choice } },
  );
}

/** Op ids the Conflicts check flags (live moved under them since they were staged). */
export function conflictOps(preview: Preview | null): ReadonlySet<string> {
  const ids = new Set<string>();
  for (const check of preview?.checks ?? [])
    if (check.key === "conflicts")
      for (const item of check.items) if (item.op_id) ids.add(item.op_id);
  return ids;
}

import type { MissionId } from "@/api/index.ts";
import { changeSetStates } from "./shapes.ts";
import { decoders as d, request, type ApiResult } from "@/api";
import { type Preview, type PreviewItem } from "./actions.ts";
import { valueText } from "./itemLines.ts";

/** Changes.md K1: a conflicting staged op is rebased onto the live revision: keep mine / take live. */
export type RebaseChoice = "keep_mine" | "take_live";

const rebased = d.object({
  change_set_id: d.token,
  version: d.integer,
  state: d.known(changeSetStates),
});

export function rebaseOp(
  missionId: MissionId,
  opId: string,
  choice: RebaseChoice,
): Promise<ApiResult<{ change_set_id: string; version: number; state: string }>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/config/ops/${encodeURIComponent(opId)}/rebase`,
    rebased,
    { method: "POST", body: { choice } },
  );
}

/** The Conflicts check's items by op id (live moved under them since they were staged). */
export function conflictOps(preview: Preview | null): ReadonlyMap<string, readonly PreviewItem[]> {
  const byOp = new Map<string, PreviewItem[]>();
  for (const check of preview?.checks ?? [])
    if (check.key === "conflicts")
      for (const item of check.items)
        if (item.op_id) byOp.set(item.op_id, [...(byOp.get(item.op_id) ?? []), item]);
  return byOp;
}

export type ConflictRow = Readonly<{
  /** The fact beside the buttons: precise for 1–2 fields, a count for more (ux). */
  lines: readonly string[];
  /** 3+ fields: the row points at the Conflicts check for the full list. */
  seeChecks: boolean;
  keep: string;
  take: string;
}>;

/**
 * ux (K1 rows): "TM frame length is 1,200 bytes now, not 900 as r8 left it (changed in r9 by
 * Mira K.). You staged 1,115." Value-labelled buttons when exactly one field conflicts.
 */
export function conflictRow(items: readonly PreviewItem[], leftBy: string): ConflictRow {
  const fields = items.flatMap((i) => i.paths ?? []);
  if (fields.length === 0)
    return {
      lines: ["Live changed under this since it was staged."],
      seeChecks: true,
      keep: "Keep mine",
      take: "Take live",
    };
  if (fields.length > 2)
    return {
      lines: [`${fields.length} fields changed in live since this was staged`],
      seeChecks: true,
      keep: "Keep mine",
      take: "Take live",
    };
  const shown = (v: unknown, f: (typeof fields)[number]) => valueText(v, f.unit, f.format);
  const lines = fields.map((f) => {
    const since =
      f.changed_in === "outside"
        ? "changed outside a change set"
        : `changed in r${f.changed_in}${f.changed_by?.name ? ` by ${f.changed_by.name}` : ""}`;
    return `${f.label ?? f.path} is ${shown(f.live, f)} now, not ${shown(f.base, f)} as ${leftBy} left it (${since}). You staged ${shown(f.staged, f)}.`;
  });
  const only = fields.length === 1 ? fields[0] : undefined;
  return {
    lines,
    seeChecks: false,
    keep: only ? `Keep ${shown(only.staged, only)}` : "Keep mine",
    take: only ? `Take ${shown(only.live, only)}` : "Take live",
  };
}

import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { checkArg } from "../args.ts";
import type { Draft, TargetChip } from "../groups/api.ts";
import type { StackItem } from "./stack.ts";
import type { TargetQuery } from "./targets.ts";

/**
 * Compose → the group draft the server preflights and submits (commanding.md §Draft). Values are
 * spliced as JSON text so 64-bit integers survive; fixed and empty optional arguments are left to
 * the catalog.
 */
export function argumentValuesJson(item: StackItem): string | null {
  const parts: string[] = [];
  for (const arg of item.command.arguments) {
    if (arg.fixed_value_json !== null) continue;
    const checked = checkArg(arg, item.values[arg.id] ?? "");
    if (!checked.ok) return null;
    if (checked.json === "null") continue;
    parts.push(`${JSON.stringify(arg.name)}:${checked.json}`);
  }
  return `{${parts.join(",")}}`;
}

export function queryChips(q: TargetQuery): TargetChip[] {
  const chips: TargetChip[] = [];
  if (q.plane !== null) chips.push({ key: "plane", value: q.plane });
  if (q.profile !== null) chips.push({ key: "profile", value: q.profile });
  if (q.states.length) chips.push({ key: "state", value: q.states });
  return chips;
}

/** C5 release choice: each target's next AOS, or hold until a set time (epoch ms). */
export type Release = { mode: "next_contact" | "not_before"; notBefore: number | null };

export type ComposeInput = Readonly<{
  title: string;
  log: string;
  targets: readonly FleetSpacecraft[];
  query: TargetQuery;
  stack: readonly StackItem[];
  notBefore: number | null;
  approver: string;
  sentBackFrom: string | null;
}>;

/** Null while any argument is invalid: such a stack can't be checked or sent. */
export function buildDraft(input: ComposeInput): Draft | null {
  const commands = [];
  for (const item of input.stack) {
    const json = argumentValuesJson(item);
    if (json === null) return null;
    commands.push({ command_id: item.command.id, argument_values_json: json });
  }
  return {
    title: input.title.trim(),
    log_entry: input.log.trim(),
    targets: input.targets.map((sc) => ({ spacecraft_id: sc.id, source_endpoint_id: null })),
    target_query: { chips: queryChips(input.query), explicit: input.query.explicit },
    commands,
    not_before: input.notBefore === null ? null : new Date(input.notBefore).toISOString(),
    expires_at: null,
    priority: 3,
    requested_approver_user_id: input.approver || null,
    sent_back_from: input.sentBackFrom,
  };
}

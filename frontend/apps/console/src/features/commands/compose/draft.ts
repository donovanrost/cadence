import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { checkArg } from "../args.ts";
import type { Draft, DraftPerTarget, TargetChip } from "../groups/api.ts";
import type { StackItem } from "./stack.ts";
import type { TargetQuery } from "./targets.ts";

/**
 * Compose → the group draft the server preflights and submits (commanding.md §Draft). Values are
 * spliced as JSON text so 64-bit integers survive; fixed and empty optional arguments are left to
 * the catalog.
 */
export function argumentValuesJson(
  item: StackItem,
  spacecraftId: string | null = null,
): string | null {
  const parts: string[] = [];
  for (const arg of item.command.arguments) {
    if (arg.fixed_value_json !== null) continue;
    const own = spacecraftId === null ? undefined : item.perTarget[arg.id]?.[spacecraftId];
    const checked = checkArg(arg, own ?? item.values[arg.id] ?? "");
    if (!checked.ok) return null;
    if (checked.json === "null") continue;
    parts.push(`${JSON.stringify(arg.name)}:${checked.json}`);
  }
  return `{${parts.join(",")}}`;
}

/** The text a target sends for an argument: its own when Per target and set, else the form's. */
export const targetText = (item: StackItem, argId: string, spacecraftId: string) =>
  item.perTarget[argId]?.[spacecraftId] ?? item.values[argId] ?? "";

/**
 * B2 → commands[].per_target (api f1bed1880): each target with a value of its own, with every
 * argument's JSON (its own where set, else the form's). Null while any of them is invalid.
 */
export function perTargetJson(
  item: StackItem,
  spacecraftIds: readonly string[],
): DraftPerTarget[] | null {
  const args = Object.keys(item.perTarget);
  if (args.length === 0) return [];
  const out: DraftPerTarget[] = [];
  for (const id of spacecraftIds) {
    if (!args.some((a) => item.perTarget[a]?.[id] !== undefined)) continue;
    const json = argumentValuesJson(item, id);
    if (json === null) return null;
    out.push({ spacecraft_id: id, argument_values_json: json });
  }
  return out;
}

export function queryChips(q: TargetQuery): TargetChip[] {
  const chips: TargetChip[] = [];
  if (q.plane !== null) chips.push({ key: "plane", value: q.plane });
  if (q.profile !== null) chips.push({ key: "profile", value: q.profile });
  if (q.states.length) chips.push({ key: "state", value: q.states });
  return chips;
}

/**
 * C5 release choice: each target's next AOS, or hold until a set time (epoch ms); an optional
 * expiry (epoch ms) and the priority (ux U68: 3 Normal, 1 High, a resend's own low value).
 */
export type Release = {
  mode: "next_contact" | "not_before";
  notBefore: number | null;
  expiresAt: number | null;
  priority: number;
};

export type ComposeInput = Readonly<{
  title: string;
  log: string;
  targets: readonly FleetSpacecraft[];
  query: TargetQuery;
  stack: readonly StackItem[];
  notBefore: number | null;
  expiresAt: number | null;
  priority: number;
  approver: string;
  sentBackFrom: string | null;
  /** Explicit uplink endpoints by spacecraft id (an audited override; else routing decides). */
  endpoints: Readonly<Record<string, string>>;
}>;

/** Null while any argument is invalid: such a stack can't be checked or sent. */
export function buildDraft(input: ComposeInput): Draft | null {
  const commands = [];
  for (const item of input.stack) {
    const json = argumentValuesJson(item);
    const perTarget = perTargetJson(
      item,
      input.targets.map((sc) => sc.id),
    );
    if (json === null || perTarget === null) return null;
    commands.push({
      command_id: item.command.id,
      argument_values_json: json,
      // Only when set, so a draft without per-target values keeps its digest (api f1bed1880).
      ...(perTarget.length ? { per_target: perTarget } : {}),
    });
  }
  return {
    title: input.title.trim(),
    log_entry: input.log.trim(),
    targets: input.targets.map((sc) => ({
      spacecraft_id: sc.id,
      source_endpoint_id: input.endpoints[sc.id] ?? null,
    })),
    target_query: { chips: queryChips(input.query), explicit: input.query.explicit },
    commands,
    not_before: input.notBefore === null ? null : new Date(input.notBefore).toISOString(),
    expires_at: input.expiresAt === null ? null : new Date(input.expiresAt).toISOString(),
    priority: input.priority,
    requested_approver_user_id: input.approver || null,
    sent_back_from: input.sentBackFrom,
  };
}

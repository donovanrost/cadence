import { plural } from "@/ui";
import { shownValue } from "../groups/resolved.ts";
import type { CommandArgument } from "../api.ts";
import { checkArg } from "../args.ts";
import type { Group } from "../groups/show.ts";

/**
 * Targets with their own values (ux, CommandFlow C2; lead, safety; api f1bed1880): a command's
 * `per_target` entry gives that target a COMPLETE value set that REPLACES the shared values (no
 * merge). The approver sees exactly what each target gets (U20). Values stay JSON text as sent, so
 * "8.0" isn't shown as "8".
 */

type Command = Group["commands"][number];

/**
 * A flat JSON object's entries as raw value text (`{"setpoint":8.0}` → setpoint → "8.0"); nested
 * values keep their own text. null when it isn't an object.
 */
export function rawEntries(json: string): ReadonlyMap<string, string> | null {
  const s = json.trim();
  if (!s.startsWith("{") || !s.endsWith("}")) return null;
  const out = new Map<string, string>();
  let i = 1;
  const skip = () => {
    while (i < s.length && /\s/.test(s[i] ?? "")) i++;
  };
  const stringEnd = (from: number) => {
    let j = from + 1;
    while (j < s.length && s[j] !== '"') j += s[j] === "\\" ? 2 : 1;
    return j;
  };
  skip();
  if (s[i] === "}") return out;
  while (i < s.length) {
    skip();
    if (s[i] !== '"') return null;
    const keyEnd = stringEnd(i);
    let key: unknown;
    try {
      key = JSON.parse(s.slice(i, keyEnd + 1));
    } catch {
      return null;
    }
    if (typeof key !== "string") return null;
    i = keyEnd + 1;
    skip();
    if (s[i] !== ":") return null;
    i++;
    skip();
    const start = i;
    let depth = 0;
    while (i < s.length) {
      const c = s[i];
      if (c === '"') i = stringEnd(i);
      else if (c === "{" || c === "[") depth++;
      else if (c === "}" || c === "]") {
        if (depth === 0) break;
        depth--;
      } else if (c === "," && depth === 0) break;
      i++;
    }
    out.set(key, s.slice(start, i).trim());
    if (s[i] === "}") return out;
    i++;
  }
  return null;
}

export type Override = Readonly<{ spacecraftId: string; values: ReadonlyMap<string, string> }>;

/** The command's overrides, in the group's target order. */
export function overridesOf(command: Command, group: Pick<Group, "targets">): Override[] {
  const order = new Map(group.targets.map((t, i) => [t.spacecraft_id, i]));
  return (command.per_target ?? [])
    .flatMap((p) => {
      const values = rawEntries(p.argument_values_json);
      return values ? [{ spacecraftId: p.spacecraft_id, values }] : [];
    })
    .sort((a, b) => (order.get(a.spacecraftId) ?? 0) - (order.get(b.spacecraftId) ?? 0));
}

/** "8.0–9.5" for numbers (by value, text kept), or the distinct values in order. */
export function valueRange(values: readonly string[]): string | null {
  if (values.length === 0) return null;
  const nums = values.map((v) => ({ v, n: Number(v) }));
  if (nums.every((x) => x.v.trim() !== "" && Number.isFinite(x.n))) {
    const sorted = [...nums].sort((a, b) => a.n - b.n);
    const lo = sorted[0];
    const hi = sorted[sorted.length - 1];
    if (!lo || !hi) return null;
    return lo.n === hi.n ? lo.v : `${lo.v}–${hi.v}`;
  }
  return [...new Set(values)].join(" · ");
}

const withUnit = (text: string, unit: string | null | undefined) =>
  unit ? `${text} ${unit}` : text;

/**
 * A1 readout lines for one argument (ux): the shared line `5.0 → 8.0 °C · ON 95 SPACECRAFT` and
 * `3 WITH THEIR OWN VALUES · 8.5–9.5 °C`; every target overridden: `… · EACH OF 98 WITH ITS OWN
 * VALUES`; one target: `5.0 → 8.5 °C · EARENDIL-312`. Upper case is the readout's style.
 */
export function readoutLines(
  arg: Readonly<{ name: string; to: string; from: string | null }>,
  overrides: readonly Override[],
  targetCount: number,
  unit: string | null | undefined,
  nameOf: (spacecraftId: string) => string,
): string[] {
  const from = arg.from ? `${arg.from} → ` : "";
  if (overrides.length === 0) return [`${arg.name}: ${from}${withUnit(arg.to, unit)}`];
  const own = overrides.map((o) => o.values.get(arg.name) ?? "default");
  const ownRange = valueRange(own.filter((v) => v !== "default")) ?? "default";
  if (targetCount === 1) {
    const only = overrides[0];
    return [
      `${arg.name}: ${from}${withUnit(ownRange, unit)}${only ? ` · ${nameOf(only.spacecraftId)}` : ""}`,
    ];
  }
  if (overrides.length >= targetCount)
    return [
      `${arg.name}: ${from}${withUnit(ownRange, unit)} · each of ${targetCount} with its own values`,
    ];
  return [
    `${arg.name}: ${from}${withUnit(arg.to, unit)} · on ${plural(targetCount - overrides.length, "spacecraft", "spacecraft")}`,
    `${overrides.length} with their own values · ${withUnit(ownRange, unit)}`,
  ];
}

/** One own-values cell: weight 600 when it differs from the shared value, text-4 when equal. */
export type Cell = Readonly<{
  text: string;
  kind: "differs" | "same" | "default";
  caution: string | null;
}>;

export function cellOf(
  override: Override,
  argName: string,
  shared: ReadonlyMap<string, string> | null,
  arg: CommandArgument | undefined,
): Cell {
  const v = override.values.get(argName);
  if (v === undefined) return { text: "default", kind: "default", caution: null };
  const same = shared?.get(argName) === v;
  const check = arg ? checkArg(arg, v.replace(/^"(.*)"$/, "$1")) : null;
  return {
    text: v,
    kind: same ? "same" : "differs",
    caution: check && !check.ok ? check.reason : null,
  };
}

/** The arguments an override table shows: the shared set's, then any only overrides name. */
export function tableArgs(command: Command, overrides: readonly Override[]): string[] {
  const shared = [...(rawEntries(command.argument_values_json)?.keys() ?? [])];
  const extra = overrides.flatMap((o) => [...o.values.keys()]).filter((k) => !shared.includes(k));
  return [...shared, ...new Set(extra)];
}

/** Distinct targets with their own values across the group's commands. */
export function ownTargets(group: Pick<Group, "commands">): number {
  return new Set(group.commands.flatMap((c) => (c.per_target ?? []).map((p) => p.spacecraft_id)))
    .size;
}

/** A3's header meta (ux): `SAME FOR ALL 98 EXCEPT SEQ AND CRC; 3 TARGETS ENCODE THEIR OWN VALUES`. */
export function radiateMeta(group: Pick<Group, "commands" | "target_count">): string | null {
  const k = ownTargets(group);
  return k
    ? `Same for all ${group.target_count} except SEQ and CRC; ${plural(k, "target")} encode${k === 1 ? "s" : ""} ${k === 1 ? "its" : "their"} own values`
    : null;
}

/** A value as an operator reads it: strings unquoted, numbers and the rest as sent. */
const shown = shownValue;

/**
 * Uplink & verify (ux C2): a target's own values as Approve shows them, `setpoint 9.5 °C · mode 1`,
 * in catalog order (then any the catalog doesn't list), with units; null when it has none.
 */
export function ownValuesText(
  command: Command,
  spacecraftId: string,
  args: readonly Readonly<{ name: string; unit: string | null }>[] = [],
): string | null {
  const p = (command.per_target ?? []).find((x) => x.spacecraft_id === spacecraftId);
  const values = p ? rawEntries(p.argument_values_json) : null;
  if (!values) return null;
  const names = [
    ...args.map((a) => a.name).filter((n) => values.has(n)),
    ...[...values.keys()].filter((n) => !args.some((a) => a.name === n)),
  ];
  return names
    .map((n) => {
      const unit = args.find((a) => a.name === n)?.unit;
      return `${n} ${shown(values.get(n) ?? "")}${unit ? ` ${unit}` : ""}`;
    })
    .join(" · ");
}

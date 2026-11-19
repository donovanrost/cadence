import type { CommandDetail } from "../api.ts";
import { checkArg, initialText } from "../args.ts";

/** Compose's command stack (Command.md C2): ordered commands with their argument text. */
export type StackItem = Readonly<{
  key: string;
  command: CommandDetail;
  /** Raw form text per argument id (validated with checkArg; JSON values staged at submit). */
  values: Readonly<Record<string, string>>;
  /**
   * B2 Per target (CommandFlow.md; api f1bed1880): argument id → spacecraft id → raw text. An
   * argument listed here is Per target; a target without its own text inherits the form value.
   */
  perTarget: Readonly<Record<string, Readonly<Record<string, string>>>>;
}>;

let counter = 0;
export function newItem(command: CommandDetail): StackItem {
  counter += 1;
  return {
    key: `${command.id}#${counter}`,
    command,
    values: Object.fromEntries(command.arguments.map((a) => [a.id, initialText(a)])),
    perTarget: {},
  };
}

/** Drag reorder (Command.md C2): the item at `from` lands at `to`; out of range changes nothing. */
export function moveTo<T>(items: readonly T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length)
    return [...items];
  const next = [...items];
  const [item] = next.splice(from, 1);
  if (item !== undefined) next.splice(to, 0, item);
  return next;
}

export function move<T>(items: readonly T[], index: number, by: -1 | 1): T[] {
  const next = [...items];
  const to = index + by;
  const a = next[index];
  const b = next[to];
  if (a === undefined || b === undefined) return next;
  next[index] = b;
  next[to] = a;
  return next;
}

export type ItemCheck = Readonly<{
  ok: boolean;
  /** argument id → reason, for the inline errors. */
  errors: Readonly<Record<string, string>>;
  /** B2: argument id → spacecraft id → reason, for a target's own value. */
  targetErrors: Readonly<Record<string, Readonly<Record<string, string>>>>;
  hazardousValues: readonly string[];
}>;

/** The form's values, then each listed target's own (B2) for the targets in the request. */
export function checkItem(item: StackItem, targetIds: readonly string[] = []): ItemCheck {
  const errors: Record<string, string> = {};
  const targetErrors: Record<string, Record<string, string>> = {};
  const hazardousValues: string[] = [];
  for (const arg of item.command.arguments) {
    const result = checkArg(arg, item.values[arg.id] ?? "");
    if (!result.ok) errors[arg.id] = result.reason;
    else if (result.hazardous) hazardousValues.push(arg.name);
    for (const id of targetIds) {
      const own = item.perTarget[arg.id]?.[id];
      if (own === undefined) continue;
      const r = checkArg(arg, own);
      if (!r.ok) targetErrors[arg.id] = { ...targetErrors[arg.id], [id]: r.reason };
      else if (r.hazardous && !hazardousValues.includes(arg.name)) hazardousValues.push(arg.name);
    }
  }
  const ok = Object.keys(errors).length === 0 && Object.keys(targetErrors).length === 0;
  return { ok, errors, targetErrors, hazardousValues };
}

type PerTarget = StackItem["perTarget"];

/** B2's `Same for all │ Per target` switch for one argument; off forgets the targets' values. */
export function setPerTargetMode(item: StackItem, argId: string, on: boolean): PerTarget {
  const { [argId]: current, ...rest } = item.perTarget;
  return on ? { ...rest, [argId]: current ?? {} } : rest;
}

/** One target's own text; empty inherits the form's value again. */
export function setTargetValue(
  item: StackItem,
  argId: string,
  spacecraftId: string,
  text: string,
): PerTarget {
  const { [spacecraftId]: _old, ...others } = item.perTarget[argId] ?? {};
  return { ...item.perTarget, [argId]: text === "" ? others : { ...others, [spacecraftId]: text } };
}

/** `All from form · 8.0`: every target gets the form's value written in (B2). */
export function fillFromForm(item: StackItem, targetIds: readonly string[]): PerTarget {
  const out: Record<string, Readonly<Record<string, string>>> = {};
  for (const argId of Object.keys(item.perTarget))
    out[argId] = Object.fromEntries(targetIds.map((id) => [id, item.values[argId] ?? ""]));
  return out;
}

/** `Clear`: every target inherits the form again; the arguments stay Per target. */
export const clearPerTarget = (item: StackItem): PerTarget =>
  Object.fromEntries(Object.keys(item.perTarget).map((argId) => [argId, {}]));

export type CsvTarget = Readonly<{ id: string; name: string; scid: number }>;

/**
 * `Paste CSV`: `SCID OR NAME, THEN ONE COLUMN PER ARGUMENT` (B2), the columns in the order of the
 * Per-target arguments. Blank cells leave that value alone; rows naming no target are reported.
 */
export function pastePerTargetCsv(
  item: StackItem,
  text: string,
  targets: readonly CsvTarget[],
): Readonly<{ perTarget: PerTarget; unmatched: readonly string[] }> {
  const argIds = item.command.arguments.map((a) => a.id).filter((id) => id in item.perTarget);
  const out: Record<string, Record<string, string>> = Object.fromEntries(
    argIds.map((id) => [id, { ...item.perTarget[id] }]),
  );
  const unmatched: string[] = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const [who = "", ...cells] = line.split(",").map((c) => c.trim());
    const target = targets.find(
      (t) => String(t.scid) === who || t.name.toLowerCase() === who.toLowerCase(),
    );
    if (!target) {
      unmatched.push(who);
      continue;
    }
    argIds.forEach((argId, i) => {
      const cell = cells[i];
      if (cell !== undefined && cell !== "") (out[argId] ??= {})[target.id] = cell;
    });
  }
  return { perTarget: { ...item.perTarget, ...out }, unmatched };
}

/** Argument chips for a stack row: `mode LOW`, `setpoint 21.5 degC`. */
export function argSummary(item: StackItem): string[] {
  return item.command.arguments.map((a) => {
    const value = item.values[a.id] ?? "";
    const label = a.choices.find((c) => c.value_json === value)?.label ?? value;
    return `${a.name} ${label === "" ? "—" : label}${a.unit && label !== "" ? ` ${a.unit}` : ""}`;
  });
}

/**
 * Second GO (DECISIONS #7/#31): a command whose policy needs one, or fleet reach. Reasons are
 * words for C5 and Approve; the server's policy is authoritative at submit.
 */
export function secondGoReasons(
  stack: readonly StackItem[],
  targetCount: number,
  fleetReach: number,
): string[] {
  const reasons = stack
    .filter((i) => i.command.second_go_required)
    .map(
      (i) =>
        `${i.command.name} is ${i.command.hazardous ? "hazardous" : i.command.critical ? "critical" : "policy-gated"}`,
    );
  if (targetCount >= fleetReach)
    reasons.push(`${targetCount} targets is fleet reach (${fleetReach} or more)`);
  return reasons;
}

/**
 * The verifier line in a command's form (ux Compose ruling #3, CommandFlow: only Verify turns
 * green): "Verifies MODE_CHANGED within 60 s", or "No verifier: this command can't turn green".
 * Completion verifiers name what green means; others are listed when there's no completion one.
 */
export function verifierLine(
  command: Readonly<{
    verifiers: readonly Readonly<{
      name: string;
      phase: CommandDetail["verifiers"][number]["phase"];
      timeout_ms: number | null;
    }>[];
  }>,
): Readonly<{ text: string; verifiable: boolean }> {
  const all = command.verifiers;
  if (all.length === 0)
    return { text: "No verifier: this command can't turn green", verifiable: false };
  const completion = all.filter((v) => v.phase === "completion");
  const shown = completion.length ? completion : all;
  const longest = Math.max(...shown.map((v) => v.timeout_ms ?? 0));
  const within = longest > 0 ? ` within ${Math.round(longest / 1000)} s` : "";
  return { text: `Verifies ${shown.map((v) => v.name).join(", ")}${within}`, verifiable: true };
}

const decimals = (text: string) => (text.includes(".") ? (text.split(".")[1]?.length ?? 0) : 0);

/**
 * `Current + 2.0` (B2): a target's current value plus the form's, kept to the inputs' precision.
 * Null when either isn't a plain number.
 */
export function addToCurrent(currentJson: string, deltaText: string): string | null {
  const a = currentJson.trim();
  const b = deltaText.trim();
  if (!/^-?\d+(\.\d+)?$/.test(a) || !/^-?\d+(\.\d+)?$/.test(b)) return null;
  const places = Math.max(decimals(a), decimals(b));
  return (Number(a) + Number(b)).toFixed(places);
}

/** Each target's current value of an argument's point: argument id → spacecraft id → JSON text. */
export type CurrentValues = ReadonlyMap<string, ReadonlyMap<string, string | null>>;

/**
 * `Current + <form value>`: every Per-target argument with a current point in the same unit gets
 * each target's current value plus the form's; others are left as they are.
 */
export function fillFromCurrent(
  item: StackItem,
  targetIds: readonly string[],
  current: CurrentValues,
): StackItem["perTarget"] {
  const out: Record<string, Readonly<Record<string, string>>> = { ...item.perTarget };
  for (const arg of item.command.arguments) {
    if (!(arg.id in item.perTarget) || !sameUnit(arg)) continue;
    const byTarget = current.get(arg.id);
    if (!byTarget) continue;
    const next: Record<string, string> = { ...item.perTarget[arg.id] };
    for (const id of targetIds) {
      const now = byTarget.get(id);
      const sum = now == null ? null : addToCurrent(now, item.values[arg.id] ?? "");
      if (sum !== null) next[id] = sum;
    }
    out[arg.id] = next;
  }
  return out;
}

/** The argument's current point reads in its own unit, so adding to it is meaningful. */
export const sameUnit = (arg: StackItem["command"]["arguments"][number]) =>
  arg.current_point != null && (arg.current_point.unit ?? null) === (arg.unit ?? null);

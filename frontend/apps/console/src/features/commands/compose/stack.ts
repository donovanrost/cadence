import type { CommandDetail } from "../api.ts";
import { checkArg, initialText } from "../args.ts";

/** Compose's command stack (Command.md C2): ordered commands with their argument text. */
export type StackItem = Readonly<{
  key: string;
  command: CommandDetail;
  /** Raw form text per argument id (validated with checkArg; JSON values staged at submit). */
  values: Readonly<Record<string, string>>;
}>;

let counter = 0;
export function newItem(command: CommandDetail): StackItem {
  counter += 1;
  return {
    key: `${command.id}#${counter}`,
    command,
    values: Object.fromEntries(command.arguments.map((a) => [a.id, initialText(a)])),
  };
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
  hazardousValues: readonly string[];
}>;

export function checkItem(item: StackItem): ItemCheck {
  const errors: Record<string, string> = {};
  const hazardousValues: string[] = [];
  for (const arg of item.command.arguments) {
    const result = checkArg(arg, item.values[arg.id] ?? "");
    if (!result.ok) errors[arg.id] = result.reason;
    else if (result.hazardous) hazardousValues.push(arg.name);
  }
  return { ok: Object.keys(errors).length === 0, errors, hazardousValues };
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

import type { MissionId } from "@/api/index.ts";
import { describeApiError } from "@/api/index.ts";
import { fetchCommand } from "../api.ts";
import { textFromJson } from "../args.ts";
import { fetchGroup, type Group } from "../groups/show.ts";
import { newItem, type StackItem } from "./stack.ts";

/**
 * Edit and resend (DECISIONS #31 (4): send back = a new group prefilled from it). The new draft
 * carries `sent_back_from`; commands come from the *active* catalog, so a command that left it
 * is reported, not silently dropped.
 */

const KEY = /"(?:[^"\\]|\\.)*"/y;
const VALUE = /"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/y;
const WS = /\s*/y;

/** Raw JSON text per key of a flat object of scalars, without JSON.parse (64-bit safe). */
export function splitArgs(json: string): Record<string, string> | null {
  let at = 0;
  const take = (re: RegExp): string | null => {
    WS.lastIndex = at;
    WS.exec(json);
    re.lastIndex = WS.lastIndex;
    const m = re.exec(json);
    if (!m) return null;
    at = re.lastIndex;
    return m[0];
  };
  const char = (c: string) => {
    WS.lastIndex = at;
    WS.exec(json);
    if (json[WS.lastIndex] !== c) return false;
    at = WS.lastIndex + 1;
    return true;
  };
  if (!char("{")) return null;
  const out: Record<string, string> = {};
  if (char("}")) return out;
  for (;;) {
    const key = take(KEY);
    if (key === null || !char(":")) return null;
    const value = take(VALUE);
    if (value === null) return null;
    const name: unknown = JSON.parse(key);
    if (typeof name !== "string") return null;
    out[name] = value;
    if (char("}")) return at === json.trimEnd().length ? out : null;
    if (!char(",")) return null;
  }
}

export type Resend = Readonly<{
  group: Group;
  stack: StackItem[];
  /** Names of commands no longer in the active catalog. */
  missing: string[];
}>;

export async function loadResend(
  missionId: MissionId,
  groupId: string,
): Promise<{ ok: true; value: Resend } | { ok: false; message: string }> {
  const g = await fetchGroup(missionId, groupId);
  if (!g.ok) return { ok: false, message: describeApiError(g.error) };
  const stack: StackItem[] = [];
  const missing: string[] = [];
  const commands = [...g.value.commands].sort((a, b) => a.position - b.position);
  for (const c of commands) {
    const r = await fetchCommand(missionId, c.command_id);
    const detail = r.ok ? r.value.command : null;
    if (!detail) {
      missing.push(c.name ?? c.command_id);
      continue;
    }
    const item = newItem(detail);
    const sent = splitArgs(c.argument_values_json) ?? {};
    const values = { ...item.values };
    for (const arg of detail.arguments) {
      const json = sent[arg.name];
      if (json !== undefined && arg.fixed_value_json === null)
        values[arg.id] = textFromJson(arg, json);
    }
    // api f1bed1880: a target's own values come back as Per target where they differ.
    const perTarget: Record<string, Record<string, string>> = {};
    for (const t of c.per_target ?? []) {
      const own = splitArgs(t.argument_values_json) ?? {};
      for (const arg of detail.arguments) {
        const json = own[arg.name];
        if (json === undefined || arg.fixed_value_json !== null) continue;
        const text = textFromJson(arg, json);
        if (text === values[arg.id]) continue;
        perTarget[arg.id] = { ...perTarget[arg.id], [t.spacecraft_id]: text };
      }
    }
    stack.push({ ...item, values, perTarget });
  }
  return { ok: true, value: { group: g.value, stack, missing } };
}

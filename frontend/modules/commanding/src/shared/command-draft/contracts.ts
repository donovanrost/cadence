import { parseArgumentValues } from "./exact-values";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type Query = Record<
  "command" | "target" | "command_after" | "target_after" | "command_query" | "target_query",
  string
>;
export type Target = {
  id: string;
  name: string | null;
  spacecraft_id: string | null;
  source_ref: string | null;
  scid: number | null;
};
export type Command = { id: string; name: string; display_name: string | null };
export type Argument = {
  id: string;
  name: string;
  description: string | null;
  type: "integer" | "float" | "string" | "binary" | "boolean" | "enumerated";
  required: boolean;
  default_value_json: string | null;
  fixed_value_json: string | null;
  hazardous_values_json: string;
  choices: readonly { label: string; value_json: string }[];
};
export type SelectedCommand = Command & {
  description: string | null;
  opcode_json: string;
  opcode_size_bits: number | null;
  critical: boolean;
  hazardous: boolean;
  significance: string | null;
  supported: boolean;
  arguments: Argument[];
};
export type Catalog = {
  version: 2;
  context: OpsPageContext;
  actor_id: string;
  mission_name: string;
  observed_at: string;
  query: Query;
  basis: {
    token: string;
    activation_id: string;
    generation: number;
    revision_id: string;
    plan_id: string;
  };
  targets: { limit: 25; entries: Target[]; next_after: string | null };
  commands: { limit: 25; entries: Command[]; next_after: string | null };
  selected_target: Target | null;
  selected_command: SelectedCommand | null;
  target_bases?: readonly TargetBasis[] | null;
};
export type TargetBasis = {
  sources: readonly string[];
  revision_id: string;
  plan_id: string;
  compatible: boolean;
};
export function targetBasis(catalog: Catalog, targetId: string): TargetBasis | null {
  if (catalog.target_bases == null)
    return {
      sources: [targetId],
      revision_id: catalog.basis.revision_id,
      plan_id: catalog.basis.plan_id,
      compatible: true,
    };
  return catalog.target_bases.find((basis) => basis.sources.includes(targetId)) ?? null;
}
export type Preview = {
  token: string;
  request_id: string;
  target: Target;
  revision_id: string;
  command_id: string;
  command_name: string;
  command_display_name: string | null;
  actor_id: string;
  priority: number;
  not_before: string | null;
  expires_at: string | null;
  requested_at: string;
  lifecycle_state: "validated" | "approval_pending";
  argument_values_json: string;
  resolved_argument_values_json: string;
  critical: boolean;
  hazardous: boolean;
  significance: string | null;
};
export const queryKeys = [
  "command",
  "target",
  "command_after",
  "target_after",
  "command_query",
  "target_query",
] as const;
export const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export const bytes = (v: string) => new TextEncoder().encode(v).length;
export const text = (v: unknown, max = 2000): v is string =>
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  typeof v === "string" && bytes(v) <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
export const id = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
const digest = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
const integer = (v: unknown): v is number => Number.isSafeInteger(v) && Number(v) >= 0;
const time = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
const nullableText = (v: unknown) => v === null || text(v);
const json = (v: unknown, depth = 0): v is Json =>
  depth <= 20 &&
  (v === null ||
    typeof v === "boolean" ||
    typeof v === "number" ||
    text(v, 131072) ||
    (Array.isArray(v)
      ? v.every((x) => json(x, depth + 1))
      : record(v) && Object.entries(v).every(([k, x]) => text(k) && json(x, depth + 1))));
const target = (v: unknown): v is Target =>
  record(v) &&
  id(v.id) &&
  nullableText(v.name) &&
  (v.spacecraft_id === null || id(v.spacecraft_id)) &&
  nullableText(v.source_ref) &&
  (v.scid === null || integer(v.scid));
const command = (v: unknown): boolean =>
  record(v) && id(v.id) && text(v.name) && !!v.name && nullableText(v.display_name);
export const fail = (): never => {
  throw Error("Unavailable command authoring data");
};
export function readQuery(v: unknown): Query {
  if (!record(v) || Object.keys(v).length !== queryKeys.length) return fail();
  for (const key of queryKeys)
    // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
    if (!text(v[key], 240) || /[\x00-\x1f\x7f]/.test(v[key])) return fail();
  for (const key of ["command", "target", "command_after", "target_after"] as const)
    if (v[key] !== "" && !id(v[key])) return fail();
  return v as Query;
}
function pageEntries(value: unknown, after: string, check: (v: unknown) => boolean) {
  if (
    !record(value) ||
    value.limit !== 25 ||
    !Array.isArray(value.entries) ||
    value.entries.length > 25 ||
    !(value.next_after === null || id(value.next_after))
  )
    return fail();
  let previous = after;
  for (const entry of value.entries) {
    if (!record(entry) || !check(entry) || !id(entry.id) || entry.id <= previous) return fail();
    previous = entry.id;
  }
  if (value.next_after !== null && (value.entries.length !== 25 || value.next_after !== previous))
    return fail();
}
function selected(value: unknown): value is SelectedCommand {
  if (
    !command(value) ||
    !record(value) ||
    !nullableText(value.description) ||
    !jsonText(value.opcode_json) ||
    !(
      value.opcode_size_bits === null ||
      (integer(value.opcode_size_bits) &&
        value.opcode_size_bits > 0 &&
        value.opcode_size_bits <= 8388608)
    ) ||
    typeof value.critical !== "boolean" ||
    typeof value.hazardous !== "boolean" ||
    !nullableText(value.significance) ||
    typeof value.supported !== "boolean" ||
    !Array.isArray(value.arguments) ||
    value.arguments.length > 64
  )
    return false;
  const names = new Set<string>(),
    ids = new Set<string>();
  const supported = value.supported;
  return value.arguments.every((a) => {
    if (
      !record(a) ||
      ["default_value", "fixed_value", "hazardous_values"].some((key) => Object.hasOwn(a, key)) ||
      !id(a.id) ||
      !text(a.name, 240) ||
      !a.name ||
      names.has(a.name) ||
      ids.has(a.id) ||
      !nullableText(a.description) ||
      !["integer", "float", "string", "binary", "boolean", "enumerated"].includes(String(a.type)) ||
      typeof a.required !== "boolean" ||
      !(a.default_value_json === null || jsonText(a.default_value_json)) ||
      !(a.fixed_value_json === null || jsonText(a.fixed_value_json)) ||
      !jsonText(a.hazardous_values_json, true) ||
      !argumentChoices(a.choices, a.type, supported)
    )
      return false;
    names.add(a.name);
    ids.add(a.id);
    return true;
  });
}
function argumentChoices(value: unknown, type: unknown, supported: boolean): boolean {
  if (!Array.isArray(value) || value.length > 1024) return false;
  if (type !== "enumerated") return value.length === 0;
  if (supported && value.length === 0) return false;
  const values = new Set<string>();
  return value.every((choice) => {
    if (
      !record(choice) ||
      !text(choice.label) ||
      !choice.label ||
      !text(choice.value_json, 32768) ||
      !/^-?(?:0|[1-9]\d*)$/.test(choice.value_json) ||
      values.has(BigInt(choice.value_json).toString())
    )
      return false;
    values.add(BigInt(choice.value_json).toString());
    return true;
  });
}
export function readCommandSemantics(
  value: unknown,
  catalog: Pick<Catalog, "actor_id">,
): CommandSemantics {
  if (
    !record(value) ||
    ["argument_values", "resolved_argument_values"].some((key) => Object.hasOwn(value, key)) ||
    !target(value.target) ||
    !id(value.revision_id) ||
    !id(value.command_id) ||
    !text(value.command_name) ||
    !nullableText(value.command_display_name) ||
    value.actor_id !== catalog.actor_id ||
    !integer(value.priority) ||
    value.priority > 2147483647 ||
    ![value.not_before, value.expires_at].every((x) => x === null || time(x)) ||
    typeof value.critical !== "boolean" ||
    typeof value.hazardous !== "boolean" ||
    !nullableText(value.significance) ||
    !argumentDocument(value.argument_values_json) ||
    !argumentDocument(value.resolved_argument_values_json, 131072)
  )
    return fail();
  return value as CommandSemantics;
}
export type CommandSemantics = Omit<
  Preview,
  "token" | "request_id" | "lifecycle_state" | "requested_at"
>;
export function readPreview(value: unknown, catalog: Pick<Catalog, "actor_id">): Preview {
  readCommandSemantics(value, catalog);
  if (
    !record(value) ||
    !digest(value.token) ||
    !id(value.request_id) ||
    !time(value.requested_at) ||
    !["validated", "approval_pending"].includes(String(value.lifecycle_state))
  )
    return fail();
  return value as Preview;
}
export function readCatalog(value: unknown, context: OpsPageContext): Catalog {
  const c = value;
  if (!record(c)) return fail();
  if (
    c.version !== 2 ||
    !record(c.context) ||
    c.context.organizationId !== context.organizationId ||
    c.context.missionId !== context.missionId ||
    !id(context.organizationId) ||
    !id(context.missionId) ||
    !id(c.actor_id) ||
    !text(c.mission_name) ||
    !time(c.observed_at) ||
    !record(c.basis) ||
    !digest(c.basis.token) ||
    !id(c.basis.activation_id) ||
    !integer(c.basis.generation) ||
    c.basis.generation < 1 ||
    !id(c.basis.revision_id) ||
    !id(c.basis.plan_id)
  )
    return fail();
  const q = readQuery(c.query);
  pageEntries(c.targets, q.target_after, target);
  pageEntries(c.commands, q.command_after, command);
  if (
    !(
      c.selected_target === null ||
      (target(c.selected_target) && c.selected_target.id === q.target)
    ) ||
    !(
      c.selected_command === null ||
      (selected(c.selected_command) && c.selected_command.id === q.command)
    )
  )
    return fail();
  const catalog = c as Catalog;
  if (c.target_bases !== undefined && c.target_bases !== null) {
    if (!Array.isArray(c.target_bases) || c.target_bases.length > 100) return fail();
    const sources = new Set<string>();
    for (const value of c.target_bases) {
      if (
        !record(value) ||
        !id(value.revision_id) ||
        !id(value.plan_id) ||
        typeof value.compatible !== "boolean" ||
        !Array.isArray(value.sources) ||
        value.sources.length < 1 ||
        value.sources.length > 100
      )
        return fail();
      for (const source of value.sources) {
        if (!id(source) || sources.has(source)) return fail();
        sources.add(source);
      }
    }
    if (catalog.selected_target) {
      const basis = targetBasis(catalog, catalog.selected_target.id);
      if (
        !basis ||
        basis.revision_id !== catalog.basis.revision_id ||
        basis.plan_id !== catalog.basis.plan_id
      )
        return fail();
    }
  }
  return catalog;
}
export function previewInput(
  catalog: Catalog,
  values: string,
  priority: string,
  notBefore: string,
  expiresAt: string,
) {
  if (
    !catalog.selected_command?.supported ||
    !catalog.selected_target ||
    !/^(0|[1-9]\d*)$/.test(priority) ||
    Number(priority) > 2147483647
  )
    return fail();
  if (!argumentDocument(values)) return fail();
  if ([notBefore, expiresAt].some((v) => v !== "" && !time(v))) return fail();
  return {
    expected_basis: catalog.basis.token,
    source_endpoint_ref: catalog.selected_target.id,
    command_id: catalog.selected_command.id,
    argument_values_json: values,
    priority: Number(priority),
    not_before: notBefore || null,
    expires_at: expiresAt || null,
  };
}

function argumentDocument(value: unknown, maxBytes: 32768 | 131072 = 32768): value is string {
  try {
    parseArgumentValues(value, maxBytes);
    return true;
  } catch {
    return false;
  }
}
function jsonText(value: unknown, array = false): value is string {
  if (!text(value, 131072) || !value) return false;
  try {
    const decoded: unknown = JSON.parse(value);
    return (!array || Array.isArray(decoded)) && json(decoded);
  } catch {
    return false;
  }
}

import type { HostActionReceipt } from "@cadence/plugin-sdk";
export type Definition = {
  id: string;
  point_id: string;
  point_name: string;
  expression: string;
  version: number;
  source_count: number;
};
export type DefinitionRow = Omit<Definition, "expression"> & {
  expression_preview: string;
  href: string;
};
export type Page<T> = {
  items: T[];
  total_count: number;
  page: number;
  page_size: 25;
  previous_href: string | null;
  next_href: string | null;
};
export type Value = {
  id: string;
  point_id: string;
  point_name: string;
  spacecraft_id: string | null;
  definition_id: string;
  definition_version: number;
  trigger_sample_id: string;
  value: string;
  quality: "good" | "suspect" | "bad";
  generation_time: string | null;
  receipt_time: string;
  definition_href: string;
};
export type DefinitionsDocument = {
  contract_version: 1;
  context: {
    organization_id: string;
    mission_id: string;
    actor_id: string;
    installation_id: string;
  };
  mission_name: string;
  query: {
    page: number;
    history_page: number;
    values_page: number;
    sources_page: number;
    spacecraft_page: number;
    spacecraft_q: string;
    q: string;
    values_q: string;
    definition: string;
    version: number | null;
    spacecraft: string;
  };
  definitions: Page<DefinitionRow>;
  selection:
    | null
    | { available: false; id: string }
    | {
        available: true;
        id: string;
        current: Definition;
        inspected: Definition;
        history: Page<DefinitionRow>;
        sources: Page<string>;
      };
  values: Page<Value>;
  spacecraft: Page<{ id: string; label: string }>;
  spacecraft_filter: string;
  links: { self: string; applications: string };
};
export type DefinitionInput = {
  point_id: string;
  point_name: string;
  expression: string;
  expected_definition_id: string | null;
  expected_version: number;
};
export type DefinitionsPort = {
  read: () => Promise<unknown>;
  save: (input: DefinitionInput, key: string) => Promise<HostActionReceipt<unknown>>;
  navigate: (href: string) => void;
};
export type DefinitionReceipt = HostActionReceipt<{
  definitionId: string;
  pointId: string;
  pointName: string;
  expression: string;
  version: number;
  sourceCount: number;
}>;
export const record = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
export const text = (v: unknown, max = 8192): v is string =>
  typeof v === "string" && new TextEncoder().encode(v).length <= max;
export const id = (v: unknown): v is string => text(v, 240) && v.length > 0 && !/[/?#\s]/.test(v);
const integer = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
const stamp = (v: unknown): v is string => text(v, 64) && Number.isFinite(Date.parse(v));
const numberKeys = [
  "page",
  "history_page",
  "values_page",
  "sources_page",
  "spacecraft_page",
  "version",
];
const textKeys = ["q", "values_q", "definition", "spacecraft", "spacecraft_q"];
function queryValue(k: string, v: string) {
  return numberKeys.includes(k)
    ? /^[1-9][0-9]{0,5}$/.test(v) && Number(v) <= 100000
    : textKeys.includes(k) && text(v, 240);
}
export function localLink(value: unknown, base: string): value is string {
  if (
    typeof value !== "string" ||
    !value.startsWith(base + "?") ||
    value.includes("#") ||
    value.includes("\\") ||
    value.split("").some((c) => c.charCodeAt(0) <= 32)
  )
    return false;
  const query = new URLSearchParams(value.slice(base.length + 1));
  return (
    [...query].every(([k, v]) => queryValue(k, v)) &&
    new Set(query.keys()).size === [...query.keys()].length
  );
}
function definitionLink(
  value: unknown,
  base: string,
  definitionId: string,
  version: number,
): value is string {
  if (!localLink(value, base)) return false;
  const q = new URLSearchParams(value.slice(base.length + 1));
  return q.get("definition") === definitionId && q.get("version") === String(version);
}
function page<T>(v: unknown, row: (v: unknown) => v is T, base: string): v is Page<T> {
  return (
    record(v) &&
    Array.isArray(v.items) &&
    v.items.length <= 25 &&
    v.items.every(row) &&
    integer(v.total_count) &&
    integer(v.page) &&
    v.page >= 1 &&
    v.page <= Math.max(1, Math.ceil(v.total_count / 25)) &&
    v.page_size === 25 &&
    v.items.length === Math.min(25, Math.max(0, v.total_count - (v.page - 1) * 25)) &&
    (v.previous_href === null ? v.page === 1 : v.page > 1 && localLink(v.previous_href, base)) &&
    (v.next_href === null
      ? v.page * 25 >= v.total_count
      : v.page * 25 < v.total_count && localLink(v.next_href, base))
  );
}
function definition(v: unknown): v is Definition {
  return (
    record(v) &&
    id(v.id) &&
    id(v.point_id) &&
    text(v.point_name, 240) &&
    text(v.expression) &&
    integer(v.version) &&
    v.version > 0 &&
    integer(v.source_count)
  );
}
export function admitDocument(value: unknown, expected?: unknown): DefinitionsDocument | null {
  if (!record(value) || value.contract_version !== 1 || !record(value.context)) return null;
  const c = value.context;
  if (![c.organization_id, c.mission_id, c.actor_id, c.installation_id].every(id)) return null;
  if (
    expected !== undefined &&
    (!record(expected) ||
      expected.scope !== "mission" ||
      expected.organizationId !== c.organization_id ||
      expected.missionId !== c.mission_id)
  )
    return null;
  const base = `/missions/${String(c.mission_id)}/applications/derived_telemetry/manage`;
  if (
    !text(value.mission_name, 240) ||
    !text(value.spacecraft_filter, 240) ||
    !record(value.links) ||
    value.links.self !== base ||
    value.links.applications !== `/missions/${String(c.mission_id)}/applications`
  )
    return null;
  if (!record(value.query)) return null;
  const q = value.query;
  if (
    !numberKeys.every(
      (k) =>
        (k === "version" && q[k] === null) ||
        (integer(q[k]) && (q[k] as number) > 0 && (q[k] as number) <= 100000),
    ) ||
    !textKeys.every((k) => text(q[k], 240))
  )
    return null;
  const row = (v: unknown): v is DefinitionRow =>
    record(v) &&
    id(v.id) &&
    id(v.point_id) &&
    text(v.point_name, 240) &&
    text(v.expression_preview, 640) &&
    integer(v.version) &&
    v.version > 0 &&
    integer(v.source_count) &&
    definitionLink(v.href, base, v.id, v.version);
  const sample = (v: unknown): v is Value =>
    record(v) &&
    id(v.id) &&
    id(v.point_id) &&
    text(v.point_name, 240) &&
    (v.spacecraft_id === null || id(v.spacecraft_id)) &&
    id(v.definition_id) &&
    integer(v.definition_version) &&
    v.definition_version > 0 &&
    id(v.trigger_sample_id) &&
    text(v.value, 4096) &&
    ["good", "suspect", "bad"].includes(v.quality as string) &&
    (v.generation_time === null || stamp(v.generation_time)) &&
    stamp(v.receipt_time) &&
    definitionLink(v.definition_href, base, v.definition_id, v.definition_version);
  if (
    !page(value.definitions, row, base) ||
    !page(value.values, sample, base) ||
    !page(
      value.spacecraft,
      (v): v is { id: string; label: string } => record(v) && id(v.id) && text(v.label, 240),
      base,
    )
  )
    return null;
  if (
    new Set(value.definitions.items.map((x) => x.id)).size !== value.definitions.items.length ||
    new Set(value.values.items.map((x) => x.id)).size !== value.values.items.length
  )
    return null;
  if (new Set(value.spacecraft.items.map((x) => x.id)).size !== value.spacecraft.items.length)
    return null;
  if (
    q.spacecraft !== "" &&
    value.values.items.some(
      (x) => x.spacecraft_id !== (q.spacecraft === "mission" ? null : q.spacecraft),
    )
  )
    return null;
  const selected = value.selection;
  if ((selected === null) !== (q.definition === "")) return null;
  if (selected !== null) {
    if (
      !record(selected) ||
      !id(selected.id) ||
      typeof selected.available !== "boolean" ||
      selected.id !== q.definition
    )
      return null;
    if (selected.available) {
      if (
        !definition(selected.current) ||
        !definition(selected.inspected) ||
        selected.current.id !== selected.id ||
        selected.inspected.id !== selected.id ||
        selected.current.point_id !== selected.inspected.point_id ||
        selected.inspected.version !== (q.version ?? selected.current.version) ||
        selected.inspected.version > selected.current.version ||
        !page(selected.history, row, base) ||
        !page(selected.sources, (x): x is string => id(x), base)
      )
        return null;
      const current = selected.current,
        inspected = selected.inspected;
      if (
        selected.sources.total_count !== inspected.source_count ||
        new Set(selected.sources.items).size !== selected.sources.items.length
      )
        return null;
      if (
        selected.history.items.some((item, index, items) => {
          const previous = items[index - 1];
          return (
            item.id !== current.id ||
            item.point_id !== current.point_id ||
            item.version > current.version ||
            (index > 0 && (!previous || item.version >= previous.version))
          );
        })
      )
        return null;
    }
  }
  return value as DefinitionsDocument;
}
export function validInput(v: unknown): v is DefinitionInput {
  return (
    record(v) &&
    Object.keys(v).length === 5 &&
    Object.keys(v).every((k) =>
      [
        "point_id",
        "point_name",
        "expression",
        "expected_definition_id",
        "expected_version",
      ].includes(k),
    ) &&
    id(v.point_id) &&
    text(v.point_name, 240) &&
    v.point_name.trim() !== "" &&
    text(v.expression) &&
    v.expression.trim() !== "" &&
    integer(v.expected_version) &&
    (v.expected_version === 0 ? v.expected_definition_id === null : id(v.expected_definition_id))
  );
}
export function admitReceipt(value: unknown, input: DefinitionInput): DefinitionReceipt | null {
  if (!record(value) || !id(value.receiptId) || !stamp(value.completedAt) || !record(value.result))
    return null;
  const r = value.result;
  if (
    !id(r.definitionId) ||
    (input.expected_definition_id !== null && r.definitionId !== input.expected_definition_id) ||
    r.pointId !== input.point_id ||
    r.pointName !== input.point_name ||
    r.expression !== input.expression ||
    r.version !== input.expected_version + 1 ||
    !integer(r.sourceCount)
  )
    return null;
  return {
    receiptId: value.receiptId,
    completedAt: value.completedAt,
    result: {
      definitionId: r.definitionId,
      pointId: input.point_id,
      pointName: input.point_name,
      expression: input.expression,
      version: input.expected_version + 1,
      sourceCount: r.sourceCount,
    },
  };
}

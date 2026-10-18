import type { HostActionReceipt } from "@cadence/plugin-sdk";
import {
  active,
  base,
  definition,
  definitionRow,
  fields,
  id,
  integer,
  name,
  nullable,
  page,
  record,
  selection,
  stamp,
  text,
  thresholds,
  type Active,
  type Base,
  type Definition,
  type DefinitionRow,
  type Page,
  type Selection,
  type Thresholds,
} from "../../shared/contracts";
export type Review = {
  definition_id: string | null;
  version: number;
  activation_event_id: string | null;
};
export type Editor = {
  point_id: string;
  limit_set_name: string;
  current: Definition | null;
  active: Active | null;
  review: Review;
};
export type DefinitionsDocument = Base & {
  surface: "manage";
  definitions: Page<DefinitionRow>;
  points: Page<{ id: string; label: string; kind: "telemetry" | "derived" }>;
  selection: Selection;
  editor: Editor | null;
};
export type DefinitionInput = Record<(typeof fields)[number], string> & {
  point_id: string;
  limit_set_name: string;
  expected_definition_id: string | null;
  expected_version: number;
  expected_activation_event_id: string | null;
};
export type DefinitionReceipt = HostActionReceipt<{
  definitionId: string;
  pointId: string;
  limitSetName: string;
  version: number;
  thresholds: Thresholds;
}>;
export type DefinitionsPort = {
  read: () => Promise<unknown>;
  save: (input: DefinitionInput, key: string) => Promise<HostActionReceipt<unknown>>;
  navigate: (href: string) => void;
};
export function admitDocument(value: unknown, expected?: unknown): DefinitionsDocument | null {
  if (
    !base(value, "manage", expected) ||
    !record(value) ||
    !page(
      value.definitions,
      (v): v is DefinitionRow => definitionRow(v, value.links.self),
      value.links.self,
    ) ||
    !page(
      value.points,
      (v): v is { id: string; label: string; kind: "telemetry" | "derived" } =>
        record(v) &&
        name(v.id) &&
        text(v.label) &&
        ["telemetry", "derived"].includes(v.kind as string),
      value.links.self,
    ) ||
    !selection(value.selection, value)
  )
    return null;
  if (
    new Set(value.definitions.items.map((d) => d.id)).size !== value.definitions.items.length ||
    new Set(value.points.items.map((d) => d.id)).size !== value.points.items.length
  )
    return null;
  const e = value.editor;
  if (e !== null) {
    if (
      !record(e) ||
      !name(e.point_id) ||
      !name(e.limit_set_name) ||
      !nullable(e.current, definition) ||
      !nullable(e.active, active) ||
      !record(e.review) ||
      !integer(e.review.version) ||
      !nullable(e.review.definition_id, id) ||
      !nullable(e.review.activation_event_id, id)
    )
      return null;
    const c = e.current as Definition | null,
      a = e.active as Active | null;
    if (
      e.review.definition_id !== (c?.id ?? null) ||
      e.review.version !== (c?.version ?? 0) ||
      e.review.activation_event_id !== (a?.event_id ?? null) ||
      (c && (c.point_id !== e.point_id || c.limit_set_name !== e.limit_set_name))
    )
      return null;
    if (
      value.selection?.available
        ? value.selection.inspected.point_id !== e.point_id ||
          value.selection.inspected.limit_set_name !== e.limit_set_name
        : value.query.point !== e.point_id || (value.query.set || "DEFAULT") !== e.limit_set_name
    )
      return null;
  } else if (value.selection?.available || (value.selection === null && value.query.point !== ""))
    return null;
  return value as DefinitionsDocument;
}
export function inputThresholds(input: DefinitionInput): Thresholds {
  return Object.fromEntries(
    fields.filter((k) => input[k].trim() !== "").map((k) => [k, Number(input[k])]),
  );
}
export function validInput(v: unknown): v is DefinitionInput {
  if (
    !record(v) ||
    Object.keys(v).length !== 9 ||
    !name(v.point_id) ||
    !name(v.limit_set_name) ||
    !integer(v.expected_version) ||
    (v.expected_version === 0
      ? v.expected_definition_id !== null
      : !id(v.expected_definition_id)) ||
    !nullable(v.expected_activation_event_id, id) ||
    !fields.every((k) => text(v[k], 80))
  )
    return false;
  const values = fields.map((k) => (v[k] as string).trim()).filter((x) => x !== "");
  return (
    values.length > 0 &&
    values.every(
      (x) =>
        /^[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/.test(x) &&
        Number.isFinite(Number(x)) &&
        Math.abs(Number(x)) <= Number.MAX_SAFE_INTEGER,
    ) &&
    values.every((x, i) => i === 0 || Number(values[i - 1]) < Number(x))
  );
}
export function admitReceipt(v: unknown, input: DefinitionInput): DefinitionReceipt | null {
  if (
    !record(v) ||
    !id(v.receiptId) ||
    !stamp(v.completedAt) ||
    !record(v.result) ||
    !id(v.result.definitionId) ||
    v.result.pointId !== input.point_id ||
    v.result.limitSetName !== input.limit_set_name ||
    v.result.version !== input.expected_version + 1 ||
    (input.expected_definition_id !== null &&
      v.result.definitionId !== input.expected_definition_id) ||
    !thresholds(v.result.thresholds)
  )
    return null;
  const expected = inputThresholds(input),
    got = v.result.thresholds;
  if (
    Object.keys(got).length !== Object.keys(expected).length ||
    fields.some((k) => got[k] !== expected[k])
  )
    return null;
  return {
    receiptId: v.receiptId,
    completedAt: v.completedAt,
    result: {
      definitionId: v.result.definitionId,
      pointId: input.point_id,
      limitSetName: input.limit_set_name,
      version: input.expected_version + 1,
      thresholds: expected,
    },
  };
}

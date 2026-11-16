import { isRecord } from "@/api";
import {
  displayValue,
  type FormValues,
  type KindSchema,
  type SchemaField,
  type StageOp,
} from "@/features/changes/index.ts";
import type { ProfileDetail } from "./detail.ts";
import { toDocument as rulesDocument, toDrafts } from "./rulesDraft.ts";
import { editableSection, schemaFieldOf } from "./sectionEdit.ts";

/**
 * Profile.md `New profile` / `Duplicate as new profile`: a create op for spacecraft_profile.
 * Fields come only from a server schema: the kind schema (blank), or the source profile's
 * sections (duplicate). The name is its own field.
 */
export type NewProfileForm = Readonly<{
  schema: KindSchema;
  values: FormValues;
  /** Copied as-is from the source profile (duplicate only): routing rules and app settings. */
  carried: Readonly<Record<string, unknown>>;
}>;

/** Blank: the kind schema minus the name, each field at its default. */
export function blankForm(schema: KindSchema): NewProfileForm {
  // compared-as-text: a schema field path, an open set the server's schema defines
  const fields = schema.fields.filter((f) => f.path !== "display_name");
  const values: FormValues = {};
  for (const f of fields)
    values[f.path] =
      f.default === null || f.default === undefined ? "" : displayValue(f, f.default);
  return { schema: { kind: "spacecraft_profile", fields }, values, carried: {} };
}

/** Duplicate: the source's editable sections with its values, plus its rules and app settings. */
export function duplicateForm(
  source: Pick<ProfileDetail, "sections" | "rules" | "applications">,
): NewProfileForm {
  const fields: SchemaField[] = [];
  const values: FormValues = {};
  for (const section of source.sections.filter((s) => editableSection(s.key)))
    for (const f of section.fields) {
      const field = schemaFieldOf(f);
      fields.push(field);
      values[f.path] =
        f.value === null || f.value === undefined ? "" : displayValue(field, f.value);
    }
  // keyed-by-text: a create document keyed by the kind schema's field paths, not a word map
  const carried: Record<string, unknown> = {
    // The server gives each copied rule a new id (RoutingRule.normalize), so drop the source's.
    routing_rules: rulesDocument(toDrafts(source.rules)).map(({ id: _id, ...rule }) => rule),
  };
  if (source.applications !== null && typeof source.applications === "object")
    carried["applications"] = source.applications;
  return { schema: { kind: "spacecraft_profile", fields }, values, carried };
}

/** Sets `value` at a dotted path, creating objects on the way (`frame_parameters.frame_size`). */
function setPath(doc: Record<string, unknown>, path: string, value: unknown) {
  const keys = path.split(".");
  let at = doc;
  for (const k of keys.slice(0, -1)) {
    const next = at[k];
    const obj: Record<string, unknown> = isRecord(next) ? { ...next } : {};
    at[k] = obj;
    at = obj;
  }
  at[keys.at(-1) ?? path] = value;
}

export function createOp(
  name: string,
  carried: Readonly<Record<string, unknown>>,
  changes: readonly Readonly<{ path: string; value: unknown }>[],
): StageOp {
  // keyed-by-text: a create document keyed by the kind schema's field paths, not a word map
  const document: Record<string, unknown> = { ...carried, display_name: name.trim() };
  for (const c of changes) setPath(document, c.path, c.value);
  return { kind: "spacecraft_profile", action: "create", document };
}

import type { SchemaField, StageOp } from "@/features/changes/index.ts";
import {
  fieldText,
  type ProfileDetail,
  type ProfileField,
  type ProfileOverride,
} from "./detail.ts";
import { schemaFieldOf } from "./sectionEdit.ts";

/**
 * P3 overrides (DECISIONS #3, #65). An override document has one key per overridden path, with the
 * path's dots written as slashes (`SpacecraftOverride.key/1`): `frame_parameters/frame_size`. A
 * change path with dots would be split into nested keys by the server, so ops use the key.
 */
export const overrideKey = (path: string) => path.replaceAll(".", "/");

/** Set (`{value, reason}`) or reset (`null`) one override on one spacecraft. */
export function overrideOp(
  spacecraftId: string,
  path: string,
  override: Readonly<{ value: unknown; reason: string }> | null,
): StageOp {
  return {
    kind: "spacecraft_override",
    action: "update",
    entity_id: spacecraftId,
    changes: [{ path: overrideKey(path), value: override }],
  };
}

export type OverridableField = Readonly<{ section: string; field: ProfileField }>;

/** The profile fields a spacecraft may override, Catalog revision first (#65 canaries). */
export function overridableFields(detail: Pick<ProfileDetail, "sections">): OverridableField[] {
  const all = detail.sections.flatMap((s) =>
    s.fields.filter((f) => f.overridable).map((field) => ({ section: s.label, field })),
  );
  // compared-as-text: a schema field path, an open set the server's schema defines
  const catalog = all.filter((o) => o.field.path === "catalog_revision_id");
  // compared-as-text: a schema field path, an open set the server's schema defines
  return [...catalog, ...all.filter((o) => o.field.path !== "catalog_revision_id")];
}

/** The one-field form schema for an override's value, from the profile schema. */
export const overrideSchemaField = (f: ProfileField): SchemaField => ({
  ...schemaFieldOf(f),
  required: true,
});

/** An override value in the profile schema's words: "rev 4 · …" for a catalog revision, not its id. */
export function valueText(f: ProfileField | undefined, value: unknown): string {
  if (f) return fieldText({ ...f, value: value ?? null, default: null });
  return value == null ? "—" : typeof value === "string" ? value : JSON.stringify(value);
}

/** The override the spacecraft already holds on that path, if any (so nothing is replaced silently). */
export const existingOverride = (
  detail: Pick<ProfileDetail, "overrides">,
  spacecraftId: string,
  path: string,
): ProfileOverride | null =>
  detail.overrides.find((o) => o.spacecraft.id === spacecraftId && o.path === path) ?? null;

/** The overridden spacecraft's name; the shared reference may not know it (§12 A5). */
export const overrideCraft = (o: ProfileOverride) => o.spacecraft.name ?? "Unknown spacecraft";

/** "EARENDIL-001 already overrides this: rev 4 since r3 (Mira K.: canary for rev 4)" (ux P3). */
export function existingLine(o: ProfileOverride, f: ProfileField | undefined): string {
  const since = o.since_revision !== null ? ` since r${o.since_revision}` : "";
  const why = o.reason ? ` (${o.actor?.name ? `${o.actor.name}: ` : ""}${o.reason})` : "";
  return `${overrideCraft(o)} already overrides this: ${valueText(f, o.spacecraft_value)}${since}${why}`;
}

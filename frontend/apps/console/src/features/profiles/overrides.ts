import type { SchemaField, StageOp } from "@/features/changes/index.ts";
import type { ProfileDetail, ProfileField } from "./detail.ts";
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
  const catalog = all.filter((o) => o.field.path === "catalog_revision_id");
  return [...catalog, ...all.filter((o) => o.field.path !== "catalog_revision_id")];
}

/** The one-field form schema for an override's value, from the profile schema. */
export const overrideSchemaField = (f: ProfileField): SchemaField => ({
  ...schemaFieldOf(f),
  required: true,
});

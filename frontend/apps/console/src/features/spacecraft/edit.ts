import type { KindSchema, Preview, PreviewItem, StageOp } from "@/features/changes/index.ts";
import type { SpacecraftDetail } from "./detail.ts";

/**
 * L17 spacecraft edits (setup.md "Spacecraft edits"): the editor's starting document, the pinned
 * profile kept as a choice even when it's inactive, and a version staged with its profile.
 */
export function spacecraftDocument(d: SpacecraftDetail): Record<string, unknown> {
  return {
    display_name: d.spacecraft.name,
    scid: d.spacecraft.scid,
    spacecraft_type_id: d.profile?.id ?? null,
    spacecraft_type_version: d.profile?.version ?? null,
  };
}

/** U40 (#309, ux #305 §10): the switches are staged on the Operation panel, not the Edit form. */
const SWITCHES: readonly string[] = ["commanding_enabled", "telemetry_enabled"];

/**
 * The schema lists active profiles; an unchanged inactive pin passes, so keep it choosable. The
 * switches leave the form: the Operation panel stages them, with U40's consequence sheet.
 */
export function withPinnedProfile(d: SpacecraftDetail) {
  return (full: KindSchema): KindSchema => {
    const schema = { ...full, fields: full.fields.filter((f) => !SWITCHES.includes(f.path)) };
    const pin = d.profile;
    if (!pin) return schema;
    return {
      ...schema,
      fields: schema.fields.map((f) => {
        // compared-as-text: a schema field path, an open set the server's schema defines
        if (f.path !== "spacecraft_type_id" || !f.enum || f.enum.some((o) => o.value === pin.id))
          return f;
        return {
          ...f,
          enum: [
            ...f.enum,
            { value: pin.id, label: `${pin.name ?? "Deleted profile"} (inactive)` },
          ],
        };
      }),
    };
  };
}

/** A version alone is a 422 ("together"), so a version change also sends the profile it's of. */
export function pairProfile(d: SpacecraftDetail) {
  return (changes: readonly { path: string; value: unknown }[]) => {
    const version = changes.some((c) => c.path === "spacecraft_type_version");
    const profile = changes.some((c) => c.path === "spacecraft_type_id");
    if (!version || profile || !d.profile) return changes;
    return [{ path: "spacecraft_type_id", value: d.profile.id }, ...changes];
  };
}

/** Archive is `delete` on the wire (api setup.md); the console says "Archive". */
export function archiveOp(d: SpacecraftDetail): StageOp {
  return { kind: "spacecraft", action: "delete", entity_id: d.spacecraft.id };
}

/** U40: the dry run's archive HOLDs for this spacecraft. Waiting requests block; booked passes don't. */
export function archiveHolds(
  preview: Preview,
  spacecraftId: string,
): Readonly<{ waiting: PreviewItem | null; booked: PreviewItem | null }> {
  const items = preview.checks.flatMap((c) => c.items).filter((i) => i.entity_id === spacecraftId);
  const find = (reason: string) => items.find((i) => i.reason === reason) ?? null;
  return { waiting: find("spacecraft_commands_waiting"), booked: find("spacecraft_passes_booked") };
}

/** qa 11-13: an archive of this spacecraft already staged in the open set isn't staged twice. */
type StagedSet = Readonly<{
  changes: readonly Readonly<{
    state: unknown;
    ops: readonly Readonly<{ kind: unknown; action: unknown; entity_id: string | null }>[];
  }>[];
}>;
export function archiveStaged(set: StagedSet | null, spacecraftId: string): boolean {
  return (set?.changes ?? []).some(
    (c) =>
      c.state === "staged" &&
      c.ops.some(
        (o) => o.kind === "spacecraft" && o.action === "delete" && o.entity_id === spacecraftId,
      ),
  );
}

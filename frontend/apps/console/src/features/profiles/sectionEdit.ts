import {
  displayValue,
  itemLine,
  type FormValues,
  type Preview,
  type SchemaField,
  type StageOp,
} from "@/features/changes/index.ts";
import { plural } from "@/ui";
import type { ProfileSection } from "./detail.ts";

/**
 * Profile.md P1/P4: a section's fields come from the server's section schema, so the form is
 * generated. Framing stays read-only until P2 (DECISIONS #19); Limits has no per-profile values.
 */
export const editableSection = (key: string) => key !== "framing" && key !== "limits";

export function schemaFieldsOf(section: ProfileSection): SchemaField[] {
  return section.fields.map((f) => ({
    path: f.path,
    label: f.label,
    type: f.type,
    unit: f.unit,
    enum: f.enum,
    range: f.range,
    default: f.default,
    required: false,
    help: f.help,
    visible_when: null,
    pattern: null,
  }));
}

export function sectionValues(section: ProfileSection, fields: readonly SchemaField[]): FormValues {
  const out: FormValues = {};
  section.fields.forEach((f, i) => {
    const schema = fields[i];
    out[f.path] =
      f.value === null || f.value === undefined || !schema ? "" : displayValue(schema, f.value);
  });
  return out;
}

export const sectionOp = (
  profileId: string,
  changes: readonly Readonly<{ path: string; value: unknown }>[],
): StageOp => ({ kind: "spacecraft_profile", action: "update", entity_id: profileId, changes });

/** The server's dry run in one line (Changes.md §1): verdict, spacecraft changed / kept and why. */
export function describePreview(
  p: Preview,
  /** Field labels by path, so errors read "Catalog revision: …" rather than the raw path (ux). */
  labels: Readonly<Record<string, string>> = {},
): { tone: "nominal" | "caution" | "crit"; text: string } {
  const issues = p.checks.flatMap((c) =>
    c.items.flatMap((i) =>
      i.errors && i.errors.length > 0
        ? i.errors.map((e) => `${labels[e.path] ?? e.path}: ${e.message}`)
        : [itemLine(i)],
    ),
  );
  const changes = p.effects.reduce((n, e) => n + e.changes, 0);
  const keeps = p.effects.flatMap((e) => e.keeps);
  const reasons = [...new Set(keeps.map((k) => k.reason))].slice(0, 2).join("; ");
  const keptText =
    keeps.length > 0
      ? ` · keeps ${plural(keeps.length, "spacecraft", "spacecraft")} (${reasons})`
      : "";
  if (p.verdict === "no_go")
    return { tone: "crit", text: `NO-GO: ${issues.slice(0, 3).join(" · ")}` };
  return {
    tone: p.verdict === "hold" || (changes === 0 && keeps.length > 0) ? "caution" : "nominal",
    text: `Checks pass · changes ${plural(changes, "spacecraft", "spacecraft")}${keptText}${issues.length ? ` · ${issues.join(" · ")}` : ""}`,
  };
}

import {
  displayValue,
  itemLine,
  type FormValues,
  type Preview,
  type SchemaField,
  type StageOp,
} from "@/features/changes/index.ts";
import { plural } from "@/ui";
import type { ProfileField, ProfileSection } from "./detail.ts";

/**
 * Profile.md P1/P4: a section's fields come from the server's section schema, so the form is
 * generated. Limits has no per-profile values. Framing is editable since #19 was lifted (#33/#45).
 */
export const editableSection = (key: string) => key !== "limits";

export const schemaFieldOf = (f: ProfileField): SchemaField => ({
  path: f.path,
  label: f.label,
  // A type the console doesn't know yet reads as text.
  type: f.type === "unrecognized" ? "string" : f.type,
  unit: f.unit,
  enum: f.enum,
  range: f.range,
  default: f.default,
  required: false,
  help: f.help,
  visible_when: null,
  pattern: null,
  create_only: undefined,
});

export const schemaFieldsOf = (section: ProfileSection): SchemaField[] =>
  section.fields.map(schemaFieldOf);

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

/** "That catalog revision doesn't exist" + typed 16 → "Catalog revision 16 doesn't exist." */
function errorLine(
  e: Readonly<{ path: string; message: string }>,
  labels: Readonly<Record<string, string>>,
  typed: Readonly<Record<string, string>>,
): string {
  const label = labels[e.path] ?? e.path;
  const value = typed[e.path];
  if (value && /^That .+ doesn't exist\.?$/.test(e.message))
    return `${label} ${value} doesn't exist.`;
  return `${label}: ${e.message}`;
}

export type PreviewCounts = Readonly<{ changes: number; keeps: number }>;

/** P4's tiles (`Changes 499 SC` / `Keeps 1 SC`): spacecraft the dry run changes and keeps. */
export const previewCounts = (p: Preview): PreviewCounts => ({
  changes: p.effects.reduce((n, e) => n + e.changes, 0),
  keeps: p.effects.reduce((n, e) => n + e.keeps.length, 0),
});

/** The server's dry run in one line (Changes.md §1): verdict, spacecraft changed / kept and why. */
export function describePreview(
  p: Preview,
  /** Field labels by path, so errors read "Catalog revision: …" rather than the raw path (ux). */
  labels: Readonly<Record<string, string>> = {},
  /** What was typed, by path: "Catalog revision 16 doesn't exist." (ux). */
  typed: Readonly<Record<string, string>> = {},
): { tone: "nominal" | "caution" | "crit"; text: string } {
  const issues = p.checks.flatMap((c) =>
    c.items.flatMap((i) =>
      i.errors && i.errors.length > 0
        ? i.errors.map((e) => errorLine(e, labels, typed))
        : [itemLine(i)],
    ),
  );
  const changes = p.effects.reduce((n, e) => n + e.changes, 0);
  const all = p.effects.flatMap((e) => e.keeps);
  // ux (Profile.md P4): spacecraft whose framing their own configuration review sets get a sentence.
  const governed = all.filter((k) => k.code === "framing_governed").length;
  const keeps = all.filter((k) => k.code !== "framing_governed");
  const reasons = [...new Set(keeps.map((k) => k.reason))].slice(0, 2).join("; ");
  const keptText =
    (keeps.length > 0
      ? ` · keeps ${plural(keeps.length, "spacecraft", "spacecraft")} (${reasons})`
      : "") +
    (governed === 1
      ? " · 1 keeps its framing: it's set in its own configuration review."
      : governed > 1
        ? ` · ${governed} keep their framing: it's set in their own configuration review.`
        : "");
  if (p.verdict === "no_go")
    return { tone: "crit", text: `NO-GO: ${issues.slice(0, 3).join(" · ")}` };
  return {
    tone: p.verdict === "hold" || (changes === 0 && all.length > 0) ? "caution" : "nominal",
    text: `Checks pass · changes ${plural(changes, "spacecraft", "spacecraft")}${keptText}${issues.length ? ` · ${issues.join(" · ")}` : ""}`,
  };
}

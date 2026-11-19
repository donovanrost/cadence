import { isKnown } from "@/api";
import { plural } from "@/ui";
import type { EditableKind } from "./kindSchema.ts";
import { configKindText, type Change } from "./shapes.ts";

/**
 * #308 (d; mms-ux's table, ca-ux): a staged change's ops in words, never raw actions, kinds, ids
 * or paths. "Changed transport · Name, Frame size and 2 other settings"; an op has no entity name,
 * so none is shown (U25: never its id).
 */
export type ChangeOp = Change["ops"][number];

const VERBS = { create: "Added", update: "Changed", delete: "Removed" } as const;

/** The kinds whose schema the console can read (their field labels). */
export const editableKinds = [
  "ground_station",
  "transport",
  "spacecraft_profile",
  "spacecraft",
  "spacecraft_route",
] as const satisfies readonly EditableKind[];
export const isEditableKind = (k: ChangeOp["kind"]): k is EditableKind =>
  isKnown(k) && (editableKinds as readonly string[]).includes(k);

/** "Changed transport", "Added extra route", "Removed ground station". */
export const opHead = (op: ChangeOp): string =>
  `${VERBS[op.action]} ${configKindText(op.kind).toLowerCase()}`;

/**
 * The fields an op touches: their labels from the kind's schema, the rest counted ("2 other
 * settings"); with no schema (not loaded, or a kind without one), only the count.
 */
export function opFields(
  op: ChangeOp,
  schema: Readonly<{ fields: readonly Readonly<{ path: string; label: string }>[] }> | null,
): string | null {
  if (op.paths.length === 0) return null;
  const labels: string[] = [];
  let others = 0;
  for (const path of op.paths) {
    const label = schema?.fields.find((f) => f.path === path)?.label;
    if (label) labels.push(label);
    else others += 1;
  }
  if (labels.length === 0) return plural(others, "setting");
  const rest = others > 0 ? [plural(others, "other setting")] : [];
  const all = [...labels, ...rest];
  return all.length === 1
    ? (all[0] ?? "")
    : `${all.slice(0, -1).join(", ")} and ${all.at(-1) ?? ""}`;
}

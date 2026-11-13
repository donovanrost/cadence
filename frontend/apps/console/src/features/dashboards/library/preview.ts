import { recordOf } from "@/api";
import { widgetTypeWord } from "./api.ts";

/**
 * The row page's definition preview (v1, plans/dashboards-library.md "Live preview"): what the
 * widget is and what it reads, from `definition_json`, without evaluating it. Unknown or
 * malformed JSON says so instead of guessing.
 *
 * The definition (live, api ffd5c6d69): `{widget_type_id, widget_type_version, title,
 * binding: {observables, scope_mode, sampling, …}, options: {…}}`.
 */
export type DefinitionPreview = Readonly<{
  kind: string;
  title: string | null;
  reads: readonly string[];
  /** Other scalar settings, as `key: value`, for Technical details. */
  settings: readonly string[];
}>;

const scalar = (v: unknown): v is string | number | boolean =>
  typeof v === "string" || typeof v === "number" || typeof v === "boolean";

/** Scalar `key: value` lines of an object, skipping blanks and the keys already shown. */
const lines = (o: Readonly<Record<string, unknown>> | null, skip: readonly string[]) =>
  Object.entries(o ?? {})
    .filter(([k, v]) => !skip.includes(k) && scalar(v) && v !== "")
    .map(([k, v]) => `${k.replaceAll("_", " ")}: ${String(v)}`);

function pointNames(observables: unknown): string[] {
  if (!Array.isArray(observables)) return [];
  return observables.flatMap((o): string[] => {
    if (typeof o === "string") return [o];
    const r = recordOf(o);
    const name = r?.name ?? r?.point_id ?? r?.id;
    return typeof name === "string" ? [name] : [];
  });
}

export function previewOf(definitionJson: string): DefinitionPreview | null {
  let raw: unknown;
  try {
    raw = JSON.parse(definitionJson);
  } catch {
    return null;
  }
  const def = recordOf(raw);
  if (def === null) return null;
  const type = def.widget_type_id;
  const kind = typeof type === "string" ? widgetTypeWord(type) : "Widget";
  const title = typeof def.title === "string" && def.title.trim() ? def.title : null;
  const binding = recordOf(def.binding);
  // scope_mode context: the points are read for whichever spacecraft the dashboard shows (lead).
  const scope = binding?.scope_mode === "context" ? " for the dashboard's spacecraft" : "";
  const reads = pointNames(binding?.observables).map((name) => `${name}${scope}`);
  const settings = [
    ...lines(recordOf(def.options), []),
    ...lines(binding, ["observables", "scope_mode"]),
  ];
  return { kind, title, reads, settings };
}

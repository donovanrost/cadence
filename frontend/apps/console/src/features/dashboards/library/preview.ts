import { recordOf } from "@/api";
import { kindWord } from "./api.ts";

/**
 * The row page's definition preview (v1, plans/dashboards-library.md "Live preview"): what the
 * widget is and what it reads, from `definition_json`, without evaluating it. Unknown or
 * malformed JSON says so instead of guessing.
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

export function previewOf(definitionJson: string): DefinitionPreview | null {
  let raw: unknown;
  try {
    raw = JSON.parse(definitionJson);
  } catch {
    return null;
  }
  const def = recordOf(raw);
  if (def === null) return null;
  const kind = typeof def.type === "string" ? kindWord(def.type) : "Widget";
  const title = typeof def.title === "string" && def.title.trim() ? def.title : null;
  const observables = Array.isArray(def.observables) ? def.observables : [];
  const reads = observables.flatMap((o): string[] => {
    if (typeof o === "string") return [o];
    const r = recordOf(o);
    if (r !== null) {
      const name = r.name ?? r.point_id ?? r.id;
      return typeof name === "string" ? [name] : [];
    }
    return [];
  });
  const settings = Object.entries(def)
    .filter(([k, v]) => !["type", "title", "observables"].includes(k) && scalar(v) && v !== "")
    .map(([k, v]) => `${k.replaceAll("_", " ")}: ${String(v)}`);
  return { kind, title, reads, settings };
}

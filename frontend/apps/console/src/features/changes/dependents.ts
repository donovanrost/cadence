import type { Preview } from "./actions.ts";

export type Dependent = Readonly<{ point_id: string; definition_id: string }>;

/**
 * U42: the derived points a retire would break, once each, so Changes can link each to its definition
 * in the derived_telemetry app's manage surface (`?definition=<id>`, AppSurfaces.md › Deep links).
 */
export function dependents(preview: Preview): readonly Dependent[] {
  const seen = new Map<string, Dependent>();
  for (const check of preview.checks)
    for (const item of check.items)
      if (item.reason === "derived_point_in_use")
        for (const d of item.details?.used_by ?? [])
          seen.set(d.definition_id, { point_id: d.point_id, definition_id: d.definition_id });
  return [...seen.values()];
}

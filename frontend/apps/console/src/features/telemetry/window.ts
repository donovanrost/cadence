import type { LocationQuery, LocationQueryRaw } from "vue-router";
import type { RangePreset, TimeRange } from "@/ui";
import { RANGES, rangeWindow, type RangeKey } from "@/features/investigate/index.ts";

/**
 * A plot/timeline window kept in the URL: a preset that slides with now (`?range=6h`) or a fixed
 * custom range (`?from=…&to=…`, ISO). Presets resolve at each fetch, so live screens keep up.
 */
export type WindowSel =
  | Readonly<{ kind: "preset"; key: RangeKey }>
  | Readonly<{ kind: "custom"; from: number; to: number }>;

const one = (value: LocationQuery[string] | undefined) => (typeof value === "string" ? value : "");
const isKey = (value: string): value is RangeKey => RANGES.some((r) => r.value === value);

export function parseWindow(query: LocationQuery, fallback: RangeKey): WindowSel {
  const from = Date.parse(one(query.from));
  const to = Date.parse(one(query.to));
  if (Number.isFinite(from) && Number.isFinite(to) && from < to)
    return { kind: "custom", from, to };
  const range = one(query.range);
  return { kind: "preset", key: isKey(range) ? range : fallback };
}

/** Query for `sel`, dropping the default preset and keeping unrelated keys. */
export function windowQuery(
  sel: WindowSel,
  base: LocationQuery,
  fallback: RangeKey,
): LocationQueryRaw {
  const { range: _r, from: _f, to: _t, ...rest } = base;
  if (sel.kind === "custom")
    return { ...rest, from: new Date(sel.from).toISOString(), to: new Date(sel.to).toISOString() };
  return sel.key === fallback ? rest : { ...rest, range: sel.key };
}

export function resolveWindow(sel: WindowSel, now: Date): TimeRange {
  return sel.kind === "custom" ? { from: sel.from, to: sel.to } : rangeWindow(sel.key, now);
}

export function windowPresets(now: Date): RangePreset[] {
  return RANGES.map((r) => ({
    id: r.value,
    label: `Last ${r.label}`,
    ...rangeWindow(r.value, now),
  }));
}

/** A range from the picker: a preset when it matches one (within a minute), else custom. */
export function windowFromRange(range: TimeRange, now: Date): WindowSel {
  const preset = windowPresets(now).find(
    (p) => Math.abs(p.from - range.from) <= 60_000 && Math.abs(p.to - range.to) <= 60_000,
  );
  return preset && isKey(preset.id)
    ? { kind: "preset", key: preset.id }
    : { kind: "custom", from: range.from, to: range.to };
}

export function windowLabel(sel: WindowSel): string {
  if (sel.kind === "preset")
    return `Last ${RANGES.find((r) => r.value === sel.key)?.label ?? sel.key}`;
  const iso = (t: number) => new Date(t).toISOString().slice(0, 16).replace("T", " ");
  return `${iso(sel.from)} – ${iso(sel.to)}Z`;
}

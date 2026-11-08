import type { LocationQuery, LocationQueryRaw } from "vue-router";
import type { ComparisonSeries, RangeKey } from "@/features/investigate/index.ts";

/**
 * Telemetry explore selection (OpsLists §Telemetry), kept in the URL:
 * ?sc=1,312&p=EPS.VBAT,EPS.sa1_current&range=6h. Series = every spacecraft × point, max 6.
 */
export const MAX_SERIES = 6;

export type Selection = Readonly<{
  scids: readonly number[];
  points: readonly string[];
  range: RangeKey;
}>;

const one = (value: LocationQuery[string] | undefined) => (typeof value === "string" ? value : "");
const list = (value: LocationQuery[string] | undefined) =>
  one(value)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

export function parseSelection(query: LocationQuery): Selection {
  const range = one(query.range);
  return {
    scids: [
      ...new Set(
        list(query.sc)
          .map(Number)
          .filter((n) => Number.isInteger(n) && n > 0),
      ),
    ],
    points: [...new Set(list(query.p))],
    range: range === "1h" || range === "24h" ? range : "6h",
  };
}

export function selectionQuery(selection: Selection, base: LocationQuery): LocationQueryRaw {
  const { sc: _sc, p: _p, range: _r, ...rest } = base;
  return {
    ...rest,
    ...(selection.scids.length ? { sc: selection.scids.join(",") } : {}),
    ...(selection.points.length ? { p: selection.points.join(",") } : {}),
    ...(selection.range === "6h" ? {} : { range: selection.range }),
  };
}

export type SeriesKey = Readonly<{ scid: number; pointId: string }>;

/** Spacecraft × point pairs in a stable order, capped at MAX_SERIES (the rest are reported). */
export function seriesOf(selection: Selection): { series: SeriesKey[]; dropped: number } {
  const all = selection.scids.flatMap((scid) =>
    selection.points.map((pointId) => ({ scid, pointId })),
  );
  return { series: all.slice(0, MAX_SERIES), dropped: Math.max(0, all.length - MAX_SERIES) };
}

/** Series styles in order: white (primary, with band), then grays and dashes. Never status hues. */
export const STYLES: readonly Omit<ComparisonSeries, "points">[] = [
  { tone: "readout", dash: "solid" },
  { tone: "text-2", dash: "solid" },
  { tone: "text-3", dash: "solid" },
  { tone: "text-4", dash: "solid" },
  { tone: "readout", dash: "dashed" },
  { tone: "readout", dash: "dotted" },
];

export function addTo<T>(items: readonly T[], item: T): T[] {
  return items.includes(item) ? [...items] : [...items, item];
}
export function removeFrom<T>(items: readonly T[], item: T): T[] {
  return items.filter((x) => x !== item);
}

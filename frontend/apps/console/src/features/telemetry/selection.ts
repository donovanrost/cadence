import type { LocationQuery, LocationQueryRaw } from "vue-router";
import { scidParam, type Scid } from "@/api/index.ts";
import type { ComparisonSeries } from "@/features/investigate/index.ts";
import { parseWindow, windowQuery, type WindowSel } from "./window.ts";

/**
 * Telemetry explore selection (OpsLists §Telemetry), kept in the URL:
 * ?sc=1,312&p=EPS.VBAT,EPS.sa1_current&range=6h (or &from=&to=). Series = every spacecraft × point, max 6.
 */
export const MAX_SERIES = 6;

export type Selection = Readonly<{
  scids: readonly Scid[];
  points: readonly string[];
  window: WindowSel;
}>;

const one = (value: LocationQuery[string] | undefined) => (typeof value === "string" ? value : "");
const list = (value: LocationQuery[string] | undefined) =>
  one(value)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

export function parseSelection(query: LocationQuery): Selection {
  return {
    scids: [
      ...new Set(
        list(query.sc).flatMap((part) => {
          const scid = scidParam(part);
          return scid === null ? [] : [scid];
        }),
      ),
    ],
    points: [...new Set(list(query.p))],
    window: parseWindow(query, "6h"),
  };
}

export function selectionQuery(selection: Selection, base: LocationQuery): LocationQueryRaw {
  const { sc: _sc, p: _p, ...rest } = base;
  return {
    ...windowQuery(selection.window, rest, "6h"),
    ...(selection.scids.length ? { sc: selection.scids.join(",") } : {}),
    ...(selection.points.length ? { p: selection.points.join(",") } : {}),
  };
}

export type SeriesKey = Readonly<{ scid: Scid; pointId: string }>;

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

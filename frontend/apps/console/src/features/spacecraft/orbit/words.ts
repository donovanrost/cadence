import { formatAbsolute, formatCountdown, formatDayTime, formatShort, plural } from "@/ui";
import type { Coverage, ElementSet, PredictedPass } from "./api.ts";

/** The element set's format as operators write it; an unknown one says so (U20). */
export const formatWords: Readonly<Record<ElementSet["format"], string>> = {
  tle: "TLE",
  omm: "OMM",
  unrecognized: "Unknown format",
};

/** Who stored it: a person (`manual`) or a service (`api`, the catalog feed). */
export const sourceWords: Readonly<Record<ElementSet["source"], string>> = {
  manual: "Manual",
  api: "API",
  unrecognized: "Unknown source",
};

/** `Manual · Mira K.`: the source, and who stored it when known. */
export function sourceLine(set: ElementSet): string {
  const by = set.created_by?.name?.trim();
  return by ? `${sourceWords[set.source]} · ${by}` : sourceWords[set.source];
}

/** The epoch's age, `T+1d 03:28:39` (design-language §4: an absolute time carries its distance). */
export const epochAge = (set: ElementSet, now: Date) => formatCountdown(new Date(set.epoch), now);

/** One fact of the current set: the kit's ApKeyValue item, typed here so plain TS reads it. */
export type OrbitFact = Readonly<{ key: string; label: string; value: string; mono?: boolean }>;

/** The current set's facts for D7 (#895): format, epoch, age, source, object name and NORAD id. */
export function currentFacts(set: ElementSet, now: Date): readonly OrbitFact[] {
  return [
    { key: "format", label: "Format", value: formatWords[set.format] },
    { key: "epoch", label: "Epoch", value: formatAbsolute(new Date(set.epoch)), mono: true },
    { key: "age", label: "Age", value: epochAge(set, now), mono: true },
    { key: "source", label: "Source", value: sourceLine(set) },
    {
      key: "object",
      label: "Object name",
      value: set.object_name?.trim() || "Not in the element set",
    },
    {
      key: "norad",
      label: "NORAD id",
      value: set.norad_id === null ? "Not in the element set" : String(set.norad_id),
      mono: set.norad_id !== null,
    },
  ];
}

/** A pass's station: `Svalbard · SVA`; a station that's gone reads so, never as an id. */
export function stationLine(p: PredictedPass): string {
  const name = p.station.display_name?.trim() || "Unknown station";
  const code = p.station.code?.trim();
  return code ? `${name} · ${code}` : name;
}

/** `38.2°`: maximum elevation at TCA, one decimal. */
export const elevation = (deg: number) => `${deg.toFixed(1)}°`;

/** AOS, TCA and LOS as the table shows them (`11-27 00:41:12Z`). */
export const passTime = (iso: string) => formatDayTime(new Date(iso));

export type CoverageLine = Readonly<{ key: string; tone: "info" | "caution"; text: string }>;

/**
 * Why the week shows fewer passes than the geometry has (predicted-passes.md §Coverage), in plain
 * words, from the spacecraft's own coverage. A spacecraft without an element set is said by the
 * current set's empty state, so it isn't repeated here.
 */
export function coverageLines(c: Coverage, to: string): readonly CoverageLine[] {
  const lines: CoverageLine[] = [];
  const u = c.unpredicted;
  if (u.spacecraft_deep_space > 0)
    lines.push({
      key: "deep-space",
      tone: "info",
      text: "This spacecraft's orbit is deep space (a period of 225 minutes or more). Cadence doesn't predict passes for deep-space orbits yet.",
    });
  if (c.horizon_end === null)
    lines.push({
      key: "not-run",
      tone: "info",
      text: "Passes haven't been predicted for this mission yet.",
    });
  else if (Date.parse(c.horizon_end) < Date.parse(to))
    lines.push({
      key: "partial",
      tone: "info",
      text: `Passes are predicted up to ${formatShort(new Date(c.horizon_end))}. Later passes aren't computed yet, so none are shown after it.`,
    });
  if (u.stations_without_location > 0) {
    const n = u.stations_without_location;
    lines.push({
      key: "stations",
      tone: "caution",
      text: `${plural(n, "station")} ${n === 1 ? "has" : "have"} no location, so ${n === 1 ? "its" : "their"} passes aren't predicted.`,
    });
  }
  if (u.passes_not_bracketed > 0) {
    const n = u.passes_not_bracketed;
    lines.push({
      key: "bracketed",
      tone: "caution",
      text: `${plural(n, "pass", "passes")} couldn't be timed, so ${n === 1 ? "it wasn't" : "they weren't"} stored. The element set may be wrong; check its epoch.`,
    });
  }
  return lines;
}

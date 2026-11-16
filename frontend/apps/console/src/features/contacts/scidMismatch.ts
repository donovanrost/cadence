import { scidWords } from "@/features/now/index.ts";
import { formatCount } from "@/ui";
import type { Pass } from "./api.ts";

type Mismatch = Pass["scid_mismatch"];
type MismatchPath = NonNullable<Mismatch>["paths"][number];
type Station = MismatchPath["station"];

/** One record line: a station's paths (the same station, or none) with their frames summed. */
interface Group {
  station: Station;
  frames: number;
  /** The observed SCIDs, sorted, when the list is complete; else null. */
  scids: number[] | null;
  /** The distinct count; `atLeast` when paths were merged from incomplete lists. */
  count: number;
  atLeast: boolean;
}

const stationKey = (s: Station) => (s ? (s.ref ?? s.id ?? s.name ?? s.code ?? "") : "");

/**
 * ux U81 §2 part 2: entries group by station. One entry is exact (`scid_count` is uncapped);
 * several merge their SCIDs only when every list is complete, else "at least N".
 */
function groups(m: NonNullable<Mismatch>): Group[] {
  const byStation = new Map<string, MismatchPath[]>();
  for (const p of m.paths.filter((p) => p.frames > 0)) {
    const k = stationKey(p.station);
    byStation.set(k, [...(byStation.get(k) ?? []), p]);
  }
  return [...byStation.values()].map((ps) => {
    const union = [...new Set(ps.flatMap((p) => p.scids))].sort((a, b) => a - b);
    const complete = ps.every((p) => p.scid_count === p.scids.length);
    const one = ps.length === 1;
    const count = one
      ? Math.max(ps[0]?.scid_count ?? 0, union.length)
      : complete
        ? union.length
        : Math.max(union.length, ...ps.map((p) => p.scid_count));
    return {
      station: ps[0]?.station ?? null,
      frames: ps.reduce((n, p) => n + p.frames, 0),
      scids: count === union.length ? union : null,
      count,
      atLeast: !one && !complete,
    };
  });
}

/**
 * ux U81 §2 (director, 11-16): frames on a pass whose header SCID wasn't the pass's, refused
 * before decoding. The station clause (name, else code) shows only when two or more stations
 * remain, and a path is never named by an id (U25). Never a guess at whose the other SCID is.
 */
export function scidMismatchLines(m: Mismatch, spacecraft: string | null): string[] {
  if (!m) return [];
  const whose = spacecraft
    ? `which is ${spacecraft}'s (SCID ${m.expected_scid})`
    : `which is for SCID ${m.expected_scid}`;
  const gs = groups(m);
  return gs.map((g) => {
    const one = g.frames === 1;
    const station = gs.length > 1 ? (g.station?.name ?? g.station?.code ?? null) : null;
    const through = station ? ` through ${station}` : "";
    const them = one ? "it" : "them";
    return (
      `${one ? "1 frame" : `${formatCount(g.frames)} frames`} with ${scidWords(g.scids ?? [], g.count, g.atLeast)} arrived` +
      `${through} during this pass, ${whose}. Cadence kept ${them} as raw evidence and made no ` +
      `telemetry from ${them}.`
    );
  });
}

/** Technical details: each path's ids and its observed SCIDs (the list stops at 8). */
export function scidMismatchIds(m: Mismatch): string[] {
  if (!m) return [];
  return m.paths.map((p) => {
    const binding = p.provider_binding_id ? ` · provider binding ${p.provider_binding_id}` : "";
    const more = p.scid_count > p.scids.length ? ` (${p.scids.length} of ${p.scid_count})` : "";
    return `Path ${p.path_id}${binding} · SCIDs ${p.scids.join(", ")}${more}`;
  });
}

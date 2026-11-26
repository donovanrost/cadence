/**
 * The pure half of the `/passes` scale fixture (#909). The seeded demo books few or no passes, so
 * a window at fleet scale is built here: the real passes, each again for every clone of its craft,
 * plus a booked schedule for every craft of the scaled fleet (about 15 passes a day, as a LEO craft
 * gets over a global network: some 15,000 a day at 1,000 craft). It is served back in cursor pages
 * of 500 as the server does (api #845). No Playwright here, so the unit tests can load it.
 */
import { isJson, type Json } from "./scale-fleet.ts";

/** The server's page size for GET /passes (api #845: `limit` up to 500). */
export const PASS_PAGE = 500;
/** One craft's booked passes per day. */
export const PASSES_PER_DAY = 15;
const PASS_MINUTES = 9;
const STATIONS = [
  "BRS",
  "SVB",
  "HBK",
  "PFA",
  "ATH",
  "KRN",
  "PUN",
  "SGO",
  "MLD",
  "AWR",
  "TRL",
  "USH",
];
const MINUTE = 60_000;

/** Clone rows of the scaled fleet by the seeded craft they were cloned from (`<id>-scale-<n>`). */
export function clonesBySource(fleetRows: readonly Json[]): Map<string, Json[]> {
  const bySource = new Map<string, Json[]>();
  for (const row of fleetRows) {
    const id = String(row["id"]);
    const at = id.lastIndexOf("-scale-");
    if (at < 0) continue;
    const source = id.slice(0, at);
    bySource.set(source, [...(bySource.get(source) ?? []), row]);
  }
  return bySource;
}

/**
 * Every real pass of a seeded craft, once more for each of its clones: the clone's id, name and
 * SCID, the pass id suffixed so ids stay unique. Passes without a craft stay as they are.
 */
export function scalePasses(passes: readonly Json[], fleetRows: readonly Json[]): Json[] {
  const clones = clonesBySource(fleetRows);
  const extra = passes.flatMap((pass) => {
    const craft = pass["spacecraft_id"];
    if (typeof craft !== "string") return [];
    return (clones.get(craft) ?? []).map((clone) => ({
      ...pass,
      id: `${String(pass["id"])}${String(clone["id"]).slice(craft.length)}`,
      spacecraft_id: clone["id"],
      spacecraft: { id: clone["id"], name: clone["name"], scid: clone["scid"] },
    }));
  });
  return [...passes, ...extra];
}

/** Where a booked pass is at `now`: done, under way, or ahead. */
function progress(starts: number, ends: number, now: number) {
  if (ends <= now) return { state: "completed", pass_phase: "closed", delivery_state: "ended" };
  if (starts <= now) return { state: "active", pass_phase: "pass", delivery_state: "flowing" };
  return { state: "confirmed", pass_phase: "scheduled", delivery_state: "pending" };
}

/**
 * A booked schedule for every craft in `[from, to)`: PASSES_PER_DAY evenly spaced passes each,
 * staggered by craft so stations and the timeline fill evenly, PASS_MINUTES long, stations in turn.
 */
export function schedulePasses(
  fleetRows: readonly Json[],
  from: number,
  to: number,
  now: number,
): Json[] {
  const period = (24 * 60 * MINUTE) / PASSES_PER_DAY;
  return fleetRows.flatMap((craft, i) => {
    const offset = (i * 7 * MINUTE) % period;
    const first = Math.ceil((from - offset) / period) * period + offset;
    const passes: Json[] = [];
    for (let starts = first, k = 0; starts < to; starts += period, k += 1) {
      const ends = starts + PASS_MINUTES * MINUTE;
      const code = STATIONS[(i + k) % STATIONS.length] ?? "BRS";
      passes.push({
        id: `scale-pass-${String(craft["id"])}-${Math.round(starts / MINUTE)}`,
        kind: "contact",
        booked: true,
        ...progress(starts, ends, now),
        spacecraft_id: craft["id"],
        spacecraft: { id: craft["id"], name: craft["name"], scid: craft["scid"] },
        station: { ref: code.toLowerCase(), id: null, code, name: `Station ${code}` },
        antenna: null,
        starts_at: new Date(starts).toISOString(),
        ends_at: new Date(ends).toISOString(),
        uplink_capable: true,
        source: { provider: "scale", provider_name: "Scale network", synthetic: false },
        max_elevation_deg: 10 + ((i + k) % 70),
        plan: null,
        attention: null,
      });
    }
    return passes;
  });
}

/** The whole window's counts over its passes, as the server counts them (contacts.md, #845). */
export function countsOf(passes: readonly Json[], now: number): Json {
  const live = passes.filter((p) => p["state"] === "active" || p["state"] === "confirmed");
  const starts = (p: Json) => Date.parse(String(p["starts_at"]));
  const ends = (p: Json) => Date.parse(String(p["ends_at"]));
  return {
    total: passes.length,
    booked: passes.filter((p) => p["booked"] === true).length,
    hand_started: passes.filter((p) => p["booked"] !== true).length,
    in_contact: new Set(
      live.filter((p) => starts(p) <= now && now < ends(p)).map((p) => p["spacecraft_id"]),
    ).size,
    upcoming: live.filter((p) => starts(p) > now).length,
    synthetic: passes.filter((p) => isJson(p["source"]) && p["source"]["synthetic"] === true)
      .length,
  };
}

/** One page of a window: `cursor` is the offset this fixture handed out (null: the first). */
export function passPage(
  window: Readonly<{ from: unknown; to: unknown; counts: Json; passes: readonly Json[] }>,
  cursor: string | null,
  limit = PASS_PAGE,
): Json {
  const start = cursor === null ? 0 : Number(cursor.replace(/^scale:/, ""));
  const end = Math.min(window.passes.length, start + Math.min(limit, PASS_PAGE));
  return {
    data: {
      from: window.from,
      to: window.to,
      counts: window.counts,
      passes: window.passes.slice(start, end),
    },
    meta: { next_cursor: end < window.passes.length ? `scale:${end}` : null },
  };
}

/** The passes of a GET /passes `data` object, as JSON rows. */
export function passesOf(data: Json): Json[] {
  const passes = data["passes"];
  if (!Array.isArray(passes)) throw new Error("scale fixture: data.passes is not an array");
  return passes.filter(isJson);
}

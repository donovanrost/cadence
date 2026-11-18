import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  spacecraftRef,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { formatShort, plural } from "@/ui";

/**
 * A16b (api 7a0cce7a5; ux Contacts.md §Book a pass, 13cefdbc3 + 4fc86bfba): the spacecraft's ready
 * routes and the search's limits. A route names a station only when its rule pins one; otherwise
 * the provider picks one per offer.
 */
export const routesReader = d.object({
  spacecraft: spacecraftRef,
  routes: d.array(
    d.object({
      key: d.string,
      // free-text: the routing rule's display name, the path label ('S-band')
      name: d.string,
      provider: d.object({ id: d.token, name: d.nullable(d.string) }),
      transport: d.object({
        id: d.token,
        version: d.nullable(d.integer),
        name: d.nullable(d.string),
      }),
      // free-text: the service profile's name, shown as said
      service_name: d.nullable(d.string),
      station: d.nullable(
        d.object({
          ref: d.nullable(d.string),
          id: d.nullable(d.token),
          // free-text: a station call sign (SVA), not a vocabulary
          code: d.nullable(d.string),
          name: d.nullable(d.string),
        }),
      ),
      /** true / false at a pinned station; null = it depends on the station (unpinned). */
      uplink: d.nullable(d.boolean),
    }),
    500,
  ),
  not_ready: d.array(
    d.object({
      // free-text: a key only, never shown or compared; the message below is what's shown.
      code: d.token,
      // free-text: the server's own sentence, shown as said (as in the search).
      message: d.string,
    }),
    50,
  ),
  limits: d.object({ max_window_s: d.integer, max_reach_s: d.integer, reach_until: d.timestamp }),
});
export type Routes = Decoded<typeof routesReader>;
export type Route = Routes["routes"][number];

export function fetchRoutes(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Routes>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/single-bookings/routes?spacecraft_id=${encodeURIComponent(spacecraftId)}`,
    routesReader,
    signal ? { signal } : {},
  );
}

const stationOf = (r: Route) => r.station?.code ?? r.station?.name ?? null;
const providerOf = (r: Route) => r.provider.name ?? "The provider";

/**
 * The chip's words: 'SVA · Northlight', with the path only when a station has several
 * ('SVA · Northlight · S-band'); unpinned 'Northlight · any of its stations'.
 */
export function routeLabel(r: Route, all: readonly Route[]): string {
  const station = stationOf(r);
  if (!station) return `${providerOf(r)} · any of its stations`;
  const several = all.filter((x) => stationOf(x) === station).length > 1;
  return [station, providerOf(r), several ? r.name : null].filter(Boolean).join(" · ");
}

/** Pinned routes grouped by station (in station order), then unpinned ones by provider. */
export function orderedRoutes(routes: readonly Route[]): Route[] {
  const key = (r: Route) => `${stationOf(r) === null ? "1" : "0"}${stationOf(r) ?? providerOf(r)}`;
  return [...routes].sort((a, b) => key(a).localeCompare(key(b)) || a.name.localeCompare(b.name));
}

/** The text-3 note beside a chip: none for an uplink route (it carries the UP tag). */
export function uplinkNote(r: Route): string | null {
  if (r.uplink === false) return "downlink only";
  if (r.uplink === null) return "uplink varies by station";
  return null;
}

/**
 * With uplink: downlink-only routes hide unless chosen ('2 routes hidden: no uplink path to
 * EARENDIL-312.'); unpinned ones stay (offers are filtered after the search) and don't count.
 */
export function visibleRoutes(
  routes: readonly Route[],
  withUplink: boolean,
  chosen: readonly string[],
): { shown: Route[]; hidden: number } {
  if (!withUplink) return { shown: orderedRoutes(routes), hidden: 0 };
  const hide = (r: Route) => r.uplink === false && !chosen.includes(r.key);
  return {
    shown: orderedRoutes(routes.filter((r) => !hide(r))),
    hidden: routes.filter(hide).length,
  };
}

export const hiddenLine = (n: number, spacecraft: string) =>
  `${plural(n, "route")} hidden: no uplink path to ${spacecraft}.`;

/** Search is refused when every chosen route is downlink-only under With uplink (ux). */
export function uplinkBlock(
  routes: readonly Route[],
  chosen: readonly string[],
  withUplink: boolean,
  spacecraft: string,
): string | null {
  if (!withUplink || chosen.length === 0) return null;
  const picked = routes.filter((r) => chosen.includes(r.key));
  if (!picked.length || picked.some((r) => r.uplink !== false)) return null;
  const names = picked.map((r) => routeLabel(r, routes)).join(", ");
  return `${names} ${picked.length === 1 ? "has" : "have"} no uplink path to ${spacecraft}. Choose Downlink or another route.`;
}

const DAY = 86_400;
/** ux: the window's problem, or null: past the reach, a past start, or past the length cap. */
export function windowProblem(
  range: Readonly<{ from: number; to: number }>,
  limits: Routes["limits"] | null,
  now: number,
): string | null {
  if (range.from < now - 60_000) return "Start from now or later.";
  if (!limits) return null;
  if (range.to > Date.parse(limits.reach_until)) {
    const days = Math.round(limits.max_reach_s / DAY);
    return `Search up to ${plural(days, "day")} ahead (until ${formatShort(new Date(limits.reach_until))}).`;
  }
  if (range.to - range.from > limits.max_window_s * 1000)
    return `Search a window of up to ${plural(Math.round(limits.max_window_s / DAY), "day")}.`;
  return null;
}

const HOUR = 3_600_000;
/** Next 6 h · Next 24 h · Next 48 h · Next 7 days, leaving out any past the reach. */
export function rangePresets(now: number, reachUntil: string | null) {
  const until = reachUntil ? Date.parse(reachUntil) : Number.POSITIVE_INFINITY;
  return [
    { id: "6h", label: "Next 6 h", h: 6 },
    { id: "24h", label: "Next 24 h", h: 24 },
    { id: "48h", label: "Next 48 h", h: 48 },
    { id: "7d", label: "Next 7 days", h: 168 },
  ]
    .filter((p) => now + p.h * HOUR <= until)
    .map((p) => ({ id: p.id, label: p.label, from: now, to: now + p.h * HOUR }));
}

/** 'via SVA · Northlight' for the empty sentence: one route by name, several counted. */
export function viaWords(routes: readonly Route[], chosen: readonly string[]): string {
  const picked = routes.filter((r) => chosen.includes(r.key));
  if (picked.length === 0) return "";
  const first = picked[0];
  return picked.length === 1 && first
    ? ` via ${routeLabel(first, routes)}`
    : ` via ${plural(picked.length, "route")}`;
}

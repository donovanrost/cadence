import type { LocationQuery, LocationQueryRaw } from "vue-router";
import { fleetStates, type FleetSpacecraft, type FleetState } from "./api.ts";
import { fleetStateWord } from "./matrix.ts";

/**
 * Fleet list filters (OpsLists.md §Fleet), kept in the URL:
 * ?plane=7&state=critical,caution&profile=…&contact=1&q=31
 */
export type FleetFilter = Readonly<{
  plane: number | null;
  states: readonly FleetState[];
  profile: string | null;
  /** In contact now (`in_contact`; unknown never matches). */
  contact: boolean;
  q: string;
}>;

export const NO_FILTER: FleetFilter = {
  plane: null,
  states: [],
  profile: null,
  contact: false,
  q: "",
};

const one = (value: LocationQuery[string] | undefined) =>
  typeof value === "string" ? value : null;
const isState = (value: string): value is FleetState =>
  (fleetStates as readonly string[]).includes(value);

export function parseFilter(query: LocationQuery): FleetFilter {
  const plane = Number(one(query.plane));
  return {
    plane: Number.isInteger(plane) && plane > 0 ? plane : null,
    states: (one(query.state) ?? "").split(",").filter(isState),
    profile: one(query.profile) || null,
    contact: one(query.contact) === "1",
    q: (one(query.q) ?? "").trim(),
  };
}

/** Query for `filter`, keeping unrelated keys (e.g. `view`). Empty filters leave no key behind. */
export function filterQuery(filter: FleetFilter, base: LocationQuery): LocationQueryRaw {
  const { plane: _p, state: _s, profile: _r, contact: _c, q: _q, ...rest } = base;
  return {
    ...rest,
    ...(filter.plane === null ? {} : { plane: String(filter.plane) }),
    ...(filter.states.length === 0 ? {} : { state: filter.states.join(",") }),
    ...(filter.profile === null ? {} : { profile: filter.profile }),
    ...(filter.contact ? { contact: "1" } : {}),
    ...(filter.q === "" ? {} : { q: filter.q }),
  };
}

export const isFiltered = (filter: FleetFilter) =>
  filter.plane !== null ||
  filter.states.length > 0 ||
  filter.profile !== null ||
  filter.contact ||
  filter.q !== "";

/** Name substring or SCID prefix, case-insensitive. */
export function matches(sc: FleetSpacecraft, filter: FleetFilter): boolean {
  if (filter.plane !== null && sc.plane !== filter.plane) return false;
  if (filter.states.length > 0 && !filter.states.includes(sc.state)) return false;
  if (filter.profile !== null && sc.profile?.id !== filter.profile) return false;
  if (filter.contact && sc.in_contact !== true) return false;
  if (filter.q !== "") {
    const q = filter.q.toLowerCase();
    if (!sc.name.toLowerCase().includes(q) && !String(sc.scid).startsWith(q)) return false;
  }
  return true;
}

/** "plane 07 + critical", for the empty-result sentence. */
export function describeFilter(filter: FleetFilter, profileName: (id: string) => string): string {
  return [
    filter.plane === null ? null : `plane ${String(filter.plane).padStart(2, "0")}`,
    filter.states.length
      ? filter.states.map((s) => fleetStateWord(s).toLowerCase()).join(" or ")
      : null,
    filter.profile === null ? null : profileName(filter.profile),
    filter.contact ? "in contact" : null,
    filter.q === "" ? null : `“${filter.q}”`,
  ]
    .filter((part): part is string => part !== null)
    .join(" + ");
}

const PRECEDENCE: Readonly<Record<FleetState, number>> = {
  critical: 0,
  caution: 1,
  stale: 2,
  nominal: 3,
  never_heard: 4,
};

/** Table order: state precedence, then name. */
export const byStateThenName = (a: FleetSpacecraft, b: FleetSpacecraft) =>
  PRECEDENCE[a.state] - PRECEDENCE[b.state] || a.name.localeCompare(b.name);

/**
 * Next contact (OpsLists §Fleet/Alarms): `In contact`, `T−38m`, `T−3h 10m`; null when nothing is
 * booked or it's unknown. No station code: the fleet read doesn't carry one.
 */
export function nextContact(sc: FleetSpacecraft, now: Date): string | null {
  if (sc.in_contact) return "In contact";
  if (!sc.next_aos_at) return null;
  const min = Math.round((Date.parse(sc.next_aos_at) - now.getTime()) / 60_000);
  if (min < 0) return null;
  return min < 60 ? `T−${min}m` : `T−${Math.floor(min / 60)}h ${min % 60}m`;
}

import type { LocationQuery } from "vue-router";
import type { FleetSpacecraft, FleetState } from "@/features/fleet/index.ts";

/**
 * Compose targets (Command.md C1, CommandFlow R02 "target by query, not by card"): a live query of
 * chips plus explicit spacecraft, resolved against the fleet. The server re-resolves at submit
 * (group-requests.md §2 target_query); this is the operator's view of the same query.
 */
export type TargetQuery = Readonly<{
  plane: number | null;
  profile: string | null;
  states: readonly FleetState[];
  explicit: readonly string[];
}>;

export const EMPTY_QUERY: TargetQuery = { plane: null, profile: null, states: [], explicit: [] };

/** `?targets=sc:<id>,sc:<id>` from Investigate / ⌘K / the queue. */
export function queryFromRoute(query: LocationQuery): TargetQuery {
  const raw = typeof query.targets === "string" ? query.targets.split(",") : [];
  return {
    ...EMPTY_QUERY,
    explicit: raw.flatMap((t) => (t.startsWith("sc:") ? [t.slice(3)] : [])),
  };
}

export const hasChips = (q: TargetQuery) =>
  q.plane !== null || q.profile !== null || q.states.length > 0;

/** Explicit spacecraft always count; chips narrow the fleet (AND); no chips and no ids = nobody. */
export function resolveTargets(
  fleet: readonly FleetSpacecraft[],
  q: TargetQuery,
): FleetSpacecraft[] {
  const explicit = new Set(q.explicit);
  const chips = hasChips(q);
  return fleet.filter(
    (sc) =>
      explicit.has(sc.id) ||
      (chips &&
        (q.plane === null || sc.plane === q.plane) &&
        (q.profile === null || sc.profile?.id === q.profile) &&
        (q.states.length === 0 || q.states.includes(sc.state))),
  );
}

/** Chip words for the query line and the group's `matched_by` (e.g. `plane 07`, `state caution`). */
export function chipWords(q: TargetQuery, profileName: (id: string) => string): string[] {
  return [
    ...(q.plane === null ? [] : [`plane ${String(q.plane).padStart(2, "0")}`]),
    ...(q.profile === null ? [] : [`profile ${profileName(q.profile)}`]),
    ...(q.states.length ? [`state ${q.states.join("+")}`] : []),
  ];
}

/** DECISIONS #31: a fleet-reach request (this many targets or more) needs a second GO. */
export const FLEET_REACH = 10;

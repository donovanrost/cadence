import type { RouteLocationRaw } from "vue-router";
import type { Availability, PlanState } from "@/features/scheduling/index.ts";

/** A plan the landing offers (the day's base plans, as K1 lists them). */
export type PlanRow = Readonly<{ id: string; version: number; state: PlanState }>;
export type ReplanSource = Readonly<{ key: string; label: string; to: RouteLocationRaw }>;

const planWord: Partial<Record<PlanState, string>> = {
  failed: "booking failed",
  partially_reserved: "partly booked",
};

/**
 * ux §7 #6: the Re-plan landing lists what can be re-planned: the days' plans with rejected or
 * failed bookings, then stations that are down, each linking to its re-plan.
 */
export function replanSources(
  days: readonly Readonly<{ day: string; plans: readonly PlanRow[] }>[],
  availability: Availability | null,
  nameOf: (stationId: string) => string,
): ReplanSource[] {
  const plans = days.flatMap(({ day, plans }) =>
    plans.flatMap((p): ReplanSource[] => {
      const word = planWord[p.state];
      return word
        ? [
            {
              key: `plan-${p.id}`,
              label: `${day.slice(5)} plan v${p.version} · ${word}`,
              to: { name: "ops.contacts.replan", query: { plan: p.id } },
            },
          ]
        : [];
    }),
  );
  const stations = (availability?.stations ?? [])
    .filter((s) => s.state === "down")
    .map((s): ReplanSource => ({
      key: `station-${s.ground_station_id}`,
      label: `${nameOf(s.ground_station_id)} is down${s.since ? ` since ${s.since.slice(5, 10)} ${s.since.slice(11, 16)}Z` : ""}`,
      to: { name: "ops.contacts.replan.station", params: { stationId: s.ground_station_id } },
    }));
  return [...plans, ...stations];
}

/** Today and tomorrow (UTC), the days a re-plan can still change. */
export function replanDays(now: Date): [string, string] {
  const day = (d: Date) => d.toISOString().slice(0, 10);
  return [day(now), day(new Date(now.getTime() + 86_400_000))];
}

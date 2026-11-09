import type { RemoteState } from "@/api";
import type { Availability, AvailabilityWindow, PlanDetail, PlanIssue } from "./api.ts";

/**
 * Drafted passes the server flags against station availability (ux U26, scheduling.md):
 * `station_unavailable` conflicts block; `station_degraded` at-risk entries warn. The availability
 * read only adds the window's times and "reported after this draft" for D.
 */
export type UnavailablePass = Readonly<{
  snapshotId: string;
  windowId: string | null;
  kind: string;
  window: AvailabilityWindow | null;
}>;
export type StationHits = Readonly<{ blocking: UnavailablePass[]; atRisk: UnavailablePass[] }>;

export const isStationConflict = (c: PlanIssue) => c.code === "station_unavailable";

export function stationHits(
  plan: Pick<PlanDetail, "conflicts" | "at_risk">,
  availability: RemoteState<Availability> | null | undefined,
): StationHits {
  const windows = new Map<string, AvailabilityWindow>();
  if (availability?.status === "ready")
    for (const s of availability.value.stations) for (const w of s.windows) windows.set(w.id, w);
  const toHits = (issues: readonly PlanIssue[]) =>
    issues.flatMap((i) =>
      i.snapshot_ids.map((snapshotId) => ({
        snapshotId,
        windowId: i.window_id ?? null,
        kind: i.kind ?? "",
        window: (i.window_id && windows.get(i.window_id)) || null,
      })),
    );
  return {
    blocking: toHits(plan.conflicts.filter(isStationConflict)),
    atRisk: toHits(plan.at_risk),
  };
}

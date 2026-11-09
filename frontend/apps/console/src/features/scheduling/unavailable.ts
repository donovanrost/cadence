import type { RemoteState } from "@/api";
import type { Availability, AvailabilityWindow, PlanDetail } from "./api.ts";

/** A drafted pass that falls inside one of its station's availability windows (ux U26). */
export type UnavailablePass = Readonly<{ snapshotId: string; window: AvailabilityWindow }>;
export type StationHits = Readonly<{ blocking: UnavailablePass[]; atRisk: UnavailablePass[] }>;

const BLOCKING = new Set(["outage", "maintenance"]);

/**
 * Passes on a station that's down for part of them. Treated like a conflict: dashed caution, counted,
 * listed with Remove, and Submit is blocked. Degraded windows don't block. Until the server's
 * conflict check covers availability (asked of api), this client check is what blocks.
 */
export function unavailablePasses(
  plan: Pick<PlanDetail, "passes">,
  availability: RemoteState<Availability> | null | undefined,
): UnavailablePass[] {
  return stationHits(plan, availability).blocking;
}

/** U26: outage/maintenance block (conflict); degraded is a warning (passes may lose data). */
export function stationHits(
  plan: Pick<PlanDetail, "passes">,
  availability: RemoteState<Availability> | null | undefined,
): StationHits {
  const all = hits(plan, availability, (k) => BLOCKING.has(k));
  const risky = hits(plan, availability, (k) => k === "degraded");
  const blocked = new Set(all.map((h) => h.snapshotId));
  return { blocking: all, atRisk: risky.filter((h) => !blocked.has(h.snapshotId)) };
}

function hits(
  plan: Pick<PlanDetail, "passes">,
  availability: RemoteState<Availability> | null | undefined,
  kind: (k: AvailabilityWindow["kind"]) => boolean,
): UnavailablePass[] {
  if (availability?.status !== "ready") return [];
  const windows = availability.value.stations.flatMap((s) =>
    s.windows.filter((w) => kind(w.kind) && w.cleared_at === null),
  );
  return plan.passes.flatMap((p) => {
    const id = p.station?.id;
    if (!id) return [];
    const from = Date.parse(p.starts_at);
    const to = Date.parse(p.ends_at);
    const hit = windows.find(
      (w) =>
        w.ground_station_id === id &&
        Date.parse(w.from) < to &&
        (w.to === null || Date.parse(w.to) > from),
    );
    return hit ? [{ snapshotId: p.snapshot_id, window: hit }] : [];
  });
}

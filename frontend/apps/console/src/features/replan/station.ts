import { decoders, request, type ApiResult, type Decoded } from "@/api";
import type { OpState } from "@/ui";

/** Contract: docs/apogee/api/contacts.md "Station availability (S7)". */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

// Provider/simulator reports may carry an actor without a name.
const actor = nullable(object({ name: decoders.optional(nullable(string)) }));
const window = object({
  id: token,
  ground_station_id: token,
  kind: oneOf(["outage", "maintenance", "degraded"]),
  from: timestamp,
  to: nullable(timestamp),
  eta: nullable(timestamp),
  source: oneOf(["operator", "provider", "simulator"]),
  reported_by: actor,
  reason: nullable(string),
  cleared_at: nullable(timestamp),
});
const status = object({
  ground_station_id: token,
  state: oneOf(["up", "degraded", "down"]),
  since: nullable(timestamp),
  eta: nullable(timestamp),
  source: nullable(oneOf(["operator", "provider", "simulator"])),
  basis: nullable(string),
  windows: array(window, 200),
});
export const availabilityReader = object({
  status,
  from: timestamp,
  to: timestamp,
  windows: array(window, 500),
});
export const impactReader = object({
  ground_station_id: token,
  from: timestamp,
  to: timestamp,
  passes_hit: integer,
  reservation_ids: array(token, 5000),
  spacecraft_ids: array(token, 5000),
  /** The plan revisions that booked the hit passes (api-ops fecd8245): K2 repairs from these. */
  plans: array(object({ id: token, version: nullable(integer) }), 100),
  truncated: boolean,
});
export type StationAvailability = Decoded<typeof availabilityReader>;
export type StationWindow = Decoded<typeof window>;
export type StationImpact = Decoded<typeof impactReader>;

const base = (missionId: string, stationId: string) =>
  `/missions/${encodeURIComponent(missionId)}/station-availability/${encodeURIComponent(stationId)}`;

export function fetchAvailability(
  key: Readonly<{ missionId: string; stationId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<StationAvailability>> {
  return request(base(key.missionId, key.stationId), availabilityReader, { signal });
}

export function fetchStationImpact(
  key: Readonly<{ missionId: string; stationId: string; from: string; to: string }>,
  signal: AbortSignal,
): Promise<ApiResult<StationImpact>> {
  const q = new URLSearchParams({ from: key.from, to: key.to });
  return request(`${base(key.missionId, key.stationId)}/impact?${q.toString()}`, impactReader, {
    signal,
  });
}

/** The window K2 re-plans around: the active outage/maintenance one, else the next upcoming. */
export function outageWindow(a: StationAvailability, now: Date): StationWindow | null {
  const open = a.windows.filter((w) => w.cleared_at === null && w.kind !== "degraded");
  const active = open.find(
    (w) =>
      Date.parse(w.from) <= now.getTime() && (w.to === null || Date.parse(w.to) > now.getTime()),
  );
  return (
    active ??
    open
      .sort((x, y) => Date.parse(x.from) - Date.parse(y.from))
      .find((w) => Date.parse(w.from) > now.getTime()) ??
    null
  );
}

export function stationTag(
  state: StationAvailability["status"]["state"],
): Readonly<{ state: OpState; label: string }> {
  switch (state) {
    case "down":
      return { state: "crit", label: "Down" };
    case "degraded":
      return { state: "caution", label: "Degraded" };
    case "up":
      // S7: "up" means nothing is reported, not live telemetry (say so).
      return { state: "neutral", label: "Nothing reported" };
  }
}

export function sourceText(w: StationWindow): string {
  const who =
    w.source === "operator"
      ? (w.reported_by?.name ?? "an operator")
      : w.source === "provider"
        ? "the provider"
        : "the simulator";
  return `Reported by ${who}`;
}

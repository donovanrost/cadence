import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  decoders,
  orNull,
  request,
  type ApiResult,
  type Decoded,
} from "@/api";
import type { OpState } from "@/ui";

/** Contract: docs/apogee/api/contacts.md "Station availability (S7)". */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

// The shared entity (typing §12 A5); provider/simulator reports may carry an actor without a name.
const actor = orNull(sharedActor);
const window = object({
  id: token,
  ground_station_id: token,
  kind: oneOf(["outage", "maintenance", "degraded"]),
  from: timestamp,
  to: nullable(timestamp),
  eta: nullable(timestamp),
  source: oneOf(["operator", "provider", "simulator"]),
  reported_by: actor,
  // free-text: the provider's or operator's reason for the outage.
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
  /** Bookings at the station in the window that already ended canceled / rejected / failed. */
  lost: object({
    count: integer,
    reservation_ids: array(token, 5000),
    spacecraft_ids: array(token, 5000),
    plans: array(object({ id: token, version: nullable(integer) }), 100),
  }),
  truncated: boolean,
});
export type StationAvailability = Decoded<typeof availabilityReader>;
export type StationWindow = Decoded<typeof window>;
export type StationImpact = Decoded<typeof impactReader>;

const base = (missionId: MissionId, stationId: string) =>
  `/missions/${encodeURIComponent(missionId)}/station-availability/${encodeURIComponent(stationId)}`;

export function fetchAvailability(
  key: Readonly<{ missionId: MissionId; stationId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<StationAvailability>> {
  return request(base(key.missionId, key.stationId), availabilityReader, { signal });
}

export function fetchStationImpact(
  key: Readonly<{ missionId: MissionId; stationId: string; from: string; to: string }>,
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
  upcoming = false,
): Readonly<{ state: OpState; label: string }> {
  switch (state) {
    case "down":
      return { state: "crit", label: "Down" };
    case "degraded":
      return { state: "caution", label: "Degraded" };
    case "up":
      // S7: "up" means nothing is reported, not live telemetry (say so). With an upcoming
      // window it's "up now" (qa: "nothing reported" beside a listed outage read as a contradiction).
      return { state: "neutral", label: upcoming ? "Up now" : "Nothing reported" };
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

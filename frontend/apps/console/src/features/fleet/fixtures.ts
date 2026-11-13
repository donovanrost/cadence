import { scid as scidReader, spacecraftId as spacecraftIdReader } from "@/api/index.ts";
import type { Fleet, FleetSpacecraft } from "./api.ts";

/** Typed test builders (code standard: fixtures through typed values, not assertions). */

export function spacecraftRow(
  scid: number,
  overrides: Partial<FleetSpacecraft> = {},
): FleetSpacecraft {
  const name = `EARENDIL-${String(scid).padStart(3, "0")}`;
  return {
    id: spacecraftIdReader(`spacecraft-${name.toLowerCase()}`),
    name,
    scid: scidReader(scid),
    profile: { id: "profile-earendil-block-1", name: "Earendil Block 1", version: 1 },
    plane: Math.floor((scid - 1) / 25) + 1,
    slot: ((scid - 1) % 25) + 1,
    phase_deg: ((scid - 1) % 25) * 14.4,
    operational_phase: "routine",
    state: "nominal",
    limit_state: "nominal",
    violating_points: 0,
    worst_point: null,
    last_received_at: "2026-11-08T02:41:15Z",
    stale: false,
    in_contact: null,
    next_aos_at: null,
    last_los_at: null,
    ...overrides,
  };
}

/** A fleet whose counts are computed from the rows, so it always satisfies the decoder. */
export function fleetOf(rows: readonly FleetSpacecraft[], overrides: Partial<Fleet> = {}): Fleet {
  const n = (state: FleetSpacecraft["state"]) => rows.filter((sc) => sc.state === state).length;
  return {
    telemetry: undefined,
    observed_at: "2026-11-08T02:41:17Z",
    stale_after_s: 900,
    last_received_at: "2026-11-08T02:41:15Z",
    counts: {
      total: rows.length,
      critical: n("critical"),
      caution: n("caution"),
      stale: n("stale"),
      nominal: n("nominal"),
      never_heard: n("never_heard"),
      fresh: rows.filter((sc) => !sc.stale && sc.state !== "never_heard").length,
      in_contact: null,
      passes_next_2h: null,
      critical_delta_1h: null,
    },
    commands: { queued: 0, in_flight: 0, failed: 0, approval_pending: 0, awaiting_viewer: 0 },
    limits: { configured: true },
    spacecraft: rows,
    ...overrides,
  };
}

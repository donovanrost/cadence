import {
  decoders as d,
  spacecraftId as spacecraftIdReader,
  spacecraftIdParam,
} from "@/api/index.ts";
import { countsPartition, fleetFields, type Fleet, type FleetSpacecraft } from "./api.ts";

/**
 * The opt-in `fleet` push (docs/apogee/api/realtime.md, "Event fleet"): a full snapshot (seq 1),
 * then deltas with full changed rows, a `heard` map (last_received_at only) and `removed` ids.
 * Pure logic here; the subscription lifecycle lives with the owner.
 */

const heardMap: d.Reader<Readonly<Record<string, string>>> = (value, path = "") => {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    throw new d.DecodeError(path, "object of id → timestamp");
  const out: Record<string, string> = {};
  for (const [id, at] of Object.entries(value)) out[id] = d.timestamp(at, `${path}.${id}`);
  return out;
};

/** GET /fleet's fields (rows partial on deltas) plus seq/full/heard/removed. */
export const fleetPushReader = d.object({
  ...fleetFields,
  seq: d.integer,
  full: d.boolean,
  heard: heardMap,
  removed: d.array(spacecraftIdReader, 20_000),
});
export type FleetPush = d.Decoded<typeof fleetPushReader>;

export type ApplyResult =
  | { ok: true; fleet: Fleet; seq: number }
  | { ok: false; reason: "gap" | "inconsistent" };

/** Server row order (contract: plane, slot, scid, name; nulls last). */
const order = (a: FleetSpacecraft, b: FleetSpacecraft) =>
  (a.plane ?? Infinity) - (b.plane ?? Infinity) ||
  (a.slot ?? Infinity) - (b.slot ?? Infinity) ||
  a.scid - b.scid ||
  a.name.localeCompare(b.name);

const fleetOf = (push: FleetPush, spacecraft: readonly FleetSpacecraft[]): Fleet => ({
  // Pushes carry live values only; the degraded flag belongs to GET /fleet.
  telemetry: undefined,
  observed_at: push.observed_at,
  stale_after_s: push.stale_after_s,
  last_received_at: push.last_received_at,
  counts: push.counts,
  commands: push.commands,
  limits: push.limits,
  spacecraft,
});

/**
 * Applies a push to the current snapshot. Envelope fields are replaced wholesale; changed rows by
 * id; `heard` sets last_received_at; `removed` drops rows. A seq gap or a result whose counts no
 * longer partition the rows asks the owner to resubscribe (fresh full snapshot).
 */
export function applyFleetPush(
  current: Fleet | null,
  lastSeq: number,
  push: FleetPush,
): ApplyResult {
  if (push.full) {
    const fleet = fleetOf(push, push.spacecraft);
    return countsPartition(fleet)
      ? { ok: true, fleet, seq: push.seq }
      : { ok: false, reason: "inconsistent" };
  }
  if (current === null || push.seq !== lastSeq + 1) return { ok: false, reason: "gap" };
  const rows = new Map(current.spacecraft.map((sc) => [sc.id, sc]));
  for (const id of push.removed) rows.delete(id);
  for (const row of push.spacecraft) rows.set(row.id, row);
  for (const [key, at] of Object.entries(push.heard)) {
    const id = spacecraftIdParam(key);
    const row = id ? rows.get(id) : undefined;
    if (row) rows.set(row.id, { ...row, last_received_at: at });
  }
  const fleet = fleetOf(push, [...rows.values()].sort(order));
  return countsPartition(fleet)
    ? { ok: true, fleet, seq: push.seq }
    : { ok: false, reason: "inconsistent" };
}

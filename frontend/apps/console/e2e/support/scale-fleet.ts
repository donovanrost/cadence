/**
 * The pure half of the fleet-scale fixture (#176): grow a real `/fleet` `data` object to N rows and
 * make a full push in which every row changed. No Playwright here, so the unit tests can load it.
 */

export type Json = Record<string, unknown>;

export function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function numberOf(value: unknown): number {
  return typeof value === "number" ? value : 0;
}

const STATES = ["critical", "caution", "stale", "nominal", "never_heard"] as const;
/** Slots per plane for the clones (the demo's planes stay as seeded). */
const SLOTS = 40;

function rowsOf(data: Json): Json[] {
  const rows = data["spacecraft"];
  if (!Array.isArray(rows)) throw new Error("scale fixture: data.spacecraft is not an array");
  return rows.filter(isJson);
}

/** Recomputes the state counts so they partition the rows again (fleetReader's invariant). */
function withCounts(data: Json, rows: Json[]): Json {
  const counts = isJson(data["counts"]) ? data["counts"] : {};
  const tally = Object.fromEntries(
    STATES.map((s) => [s, rows.filter((r) => r["state"] === s).length]),
  );
  return {
    ...data,
    spacecraft: rows,
    counts: {
      ...counts,
      ...tally,
      total: rows.length,
      fresh: rows.filter((r) => r["stale"] === false && r["last_received_at"] !== null).length,
      in_contact: counts["in_contact"] === null ? null : rows.filter((r) => r["in_contact"]).length,
    },
  };
}

/**
 * The real fleet `data` grown to `size` rows: the seeded rows first, unchanged, then clones of them
 * on new planes after the highest seeded one. A size at or below the seeded count keeps the
 * seeded rows only (the demo's 500 is the floor).
 */
export function scaleFleet(data: Json, size: number): Json {
  const seeded = rowsOf(data);
  if (seeded.length === 0) throw new Error("scale fixture: the seeded fleet is empty");
  const maxScid = Math.max(...seeded.map((r) => numberOf(r["scid"])));
  const maxPlane = Math.max(0, ...seeded.map((r) => numberOf(r["plane"])));
  const clones = Array.from({ length: Math.max(0, size - seeded.length) }, (_, i) => {
    const from = seeded[i % seeded.length] ?? {};
    const n = String(i + 1).padStart(4, "0");
    return {
      ...from,
      id: `${String(from["id"])}-scale-${n}`,
      name: `Scale ${n}`,
      scid: maxScid + i + 1,
      plane: maxPlane + 1 + Math.floor(i / SLOTS),
      slot: (i % SLOTS) + 1,
    };
  });
  return withCounts(data, [...seeded, ...clones]);
}

/**
 * A full snapshot in which every row changed: each row's violating-point count and value move,
 * the state rotates through the five states. That is the largest push the server can send.
 */
export function changedFleet(data: Json, round: number): Json {
  const rows = rowsOf(data).map((row, i) => {
    const state = STATES[(i + round) % STATES.length] ?? "nominal";
    const point = isJson(row["worst_point"]) ? row["worst_point"] : null;
    return {
      ...row,
      state,
      stale: state === "stale",
      limit_state: state === "critical" || state === "caution" ? state : "nominal",
      violating_points: state === "critical" || state === "caution" ? 1 + (round % 3) : 0,
      worst_point:
        point && typeof point["value"] === "number"
          ? { ...point, value: point["value"] + round }
          : point,
    };
  });
  return withCounts(data, rows);
}

/** The median of an odd-or-even list (mean of the middle two). */
export function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length === 0) return Number.NaN;
  return sorted.length % 2 === 1
    ? (sorted[mid] ?? Number.NaN)
    : ((sorted[mid - 1] ?? 0) + (sorted[mid] ?? 0)) / 2;
}

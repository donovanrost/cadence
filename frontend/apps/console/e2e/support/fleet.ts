import type { Page } from "@playwright/test";
import { missionApi } from "./console.ts";

/**
 * Fleet fixtures for Now / Fleet / Alarms specs. Contract: docs/apogee/api/ops.md (`/fleet`).
 * We fetch the real response and degrade chosen spacecraft, so identities, planes and slots stay
 * the seeded ones; only the operational state is synthetic.
 */

type Json = Record<string, unknown>;

export type LimitWord = "red_low" | "red_high" | "yellow_low" | "yellow_high";

export interface Degradation {
  /** SCID → violating point. */
  readonly critical?: Readonly<Record<number, { point: string; value: number; raw: LimitWord }>>;
  readonly caution?: Readonly<Record<number, { point: string; value: number; raw: LimitWord }>>;
  readonly stale?: readonly number[];
  /** Everyone else becomes nominal and fresh, except these. */
  readonly neverHeard?: readonly number[];
  readonly awaitingViewer?: number;
  readonly limitsConfigured?: boolean;
}

const STATES = ["critical", "caution", "stale", "nominal", "never_heard"] as const;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function rowsOf(data: Json): Json[] {
  const rows = data["spacecraft"];
  if (!Array.isArray(rows)) throw new Error("fleet fixture: data.spacecraft is not an array");
  return rows.filter(isJson);
}

function violating(
  state: "critical" | "caution",
  at: string,
  spec: { point: string; value: number; raw: LimitWord },
) {
  return {
    state,
    limit_state: state,
    violating_points: 1,
    worst_point: {
      point_id: `point-qa-${spec.point.toLowerCase()}`,
      point_name: spec.point,
      value: spec.value,
      limit_state: state,
      raw_limit_state: spec.raw,
      received_at: at,
    },
    last_received_at: at,
    stale: false,
  };
}

/** Applies a degradation to a real `/fleet` `data` object and recomputes every count. */
export function degradeFleet(data: Json, d: Degradation, now = new Date()): Json {
  const fresh = now.toISOString();
  const old = new Date(now.getTime() - 3 * 3600_000).toISOString();
  const rows = rowsOf(data).map((row): Json => {
    const scid = row["scid"];
    const critical = typeof scid === "number" ? d.critical?.[scid] : undefined;
    const caution = typeof scid === "number" ? d.caution?.[scid] : undefined;
    const base = { ...row, worst_point: null, violating_points: 0 };
    if (critical) return { ...base, ...violating("critical", fresh, critical) };
    if (caution) return { ...base, ...violating("caution", fresh, caution) };
    if (typeof scid === "number" && d.stale?.includes(scid))
      return {
        ...base,
        state: "stale",
        limit_state: "nominal",
        last_received_at: old,
        stale: true,
      };
    if (typeof scid === "number" && d.neverHeard?.includes(scid))
      return {
        ...base,
        state: "never_heard",
        limit_state: "no_data",
        last_received_at: null,
        stale: false,
      };
    return {
      ...base,
      state: "nominal",
      limit_state: "nominal",
      last_received_at: fresh,
      stale: false,
    };
  });
  const count = (state: string) => rows.filter((row) => row["state"] === state).length;
  const counts: Json = isJson(data["counts"]) ? { ...data["counts"] } : {};
  for (const state of STATES) counts[state] = count(state);
  counts["total"] = rows.length;
  counts["fresh"] = rows.filter(
    (row) => row["stale"] === false && row["state"] !== "never_heard",
  ).length;
  const commands: Json = isJson(data["commands"]) ? { ...data["commands"] } : {};
  const waiting = d.awaitingViewer ?? 0;
  commands["awaiting_viewer"] = waiting;
  commands["approval_pending"] = Math.max(Number(commands["approval_pending"] ?? 0), waiting);
  commands["queued"] = Math.max(Number(commands["queued"] ?? 0), waiting);
  return {
    ...data,
    observed_at: fresh,
    last_received_at: rows.some((row) => row["last_received_at"] === fresh)
      ? fresh
      : data["last_received_at"],
    counts,
    commands,
    limits: { configured: d.limitsConfigured ?? true },
    spacecraft: rows,
  };
}

/** Routes the mission's `/fleet` read through `degradeFleet` (real response, synthetic state). */
export async function routeDegradedFleet(page: Page, d: Degradation): Promise<void> {
  await page.route(missionApi("fleet"), async (route) => {
    try {
      const response = await route.fetch();
      const body: unknown = await response.json();
      if (!isJson(body) || !isJson(body["data"])) throw new Error("fleet fixture: unexpected body");
      await route.fulfill({ response, json: { data: degradeFleet(body["data"], d) } });
    } catch {
      // A refetch still in flight when the test ends or the page navigates away. If the fixture
      // itself were broken, the screen would show its error state and the test would fail there.
      await route.abort().catch(() => undefined);
    }
  });
}

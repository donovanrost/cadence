import type { Page } from "@playwright/test";
import { missionApi } from "./console.ts";
import { DEMO } from "./env.ts";

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

type Row = Json;

function member(row: Row) {
  const worst = isJson(row["worst_point"]) ? row["worst_point"] : null;
  return {
    id: row["id"],
    name: row["name"],
    scid: row["scid"],
    plane: row["plane"],
    stale: row["stale"],
    last_received_at: row["last_received_at"],
    violating_points: row["violating_points"],
    value: worst ? worst["value"] : null,
    first_crossed_at: worst ? worst["received_at"] : null,
    // Alarm episode fields (null outside alarm items; alarm items set status below).
    episode_id: null,
    status: null,
    assignee: null,
    acknowledged_by: null,
  };
}

function item(fields: Json): Json {
  return {
    source: null,
    acknowledged: null,
    since: null,
    due_at: null,
    count: 0,
    spacecraft: [],
    point: null,
    condition: null,
    plane: null,
    command: null,
    outcome: null,
    command_requests: [],
    finding: null,
    ...fields,
  };
}

/**
 * The `/action-queue` (M6, ops.md) a server would rank for a degraded fleet: alarm groups by
 * {severity, point, condition}, one approval item, stale per plane, then P3 setup items.
 */
export function actionQueueFor(fleet: Json, awaitingViewer = 0): Json {
  const rows = rowsOf(fleet);
  const items: Json[] = [];
  for (const severity of ["critical", "caution"] as const) {
    const groups = new Map<string, Row[]>();
    for (const row of rows.filter((r) => r["state"] === severity)) {
      const worst = isJson(row["worst_point"]) ? row["worst_point"] : {};
      const key = `${String(worst["point_name"])}:${String(worst["raw_limit_state"])}`;
      groups.set(key, [...(groups.get(key) ?? []), row]);
    }
    for (const [key, group] of groups) {
      const [pointName = "", condition = ""] = key.split(":");
      const worst = isJson(group[0]?.["worst_point"]) ? group[0]["worst_point"] : {};
      items.push(
        item({
          id: `alarm:${severity}:${String(worst["point_id"])}:${condition}`,
          priority: severity === "critical" ? 1 : 2,
          kind: "alarm",
          state: severity,
          since: worst["received_at"] ?? null,
          count: group.length,
          source: "ground_limit",
          acknowledged: 0,
          spacecraft: group.map((row, i) => ({
            ...member(row),
            episode_id: `alarm_episode_qa_${severity}_${i}`,
            status: "new",
          })),
          point: { id: worst["point_id"], name: pointName, subsystem: "QA", unit: null },
          condition,
        }),
      );
    }
  }
  if (awaitingViewer > 0) {
    const requests = Array.from({ length: awaitingViewer }, (_, i) => ({
      id: `command_request_qa_${i + 1}`,
      command_name: "SET_HEATER_SETPOINT",
      target: { id: `spacecraft-earendil-00${i + 1}`, name: `EARENDIL-00${i + 1}` },
      spacecraft_id: `spacecraft-earendil-00${i + 1}`,
      requested_by: "QA Second Operator",
      requested_at: new Date().toISOString(),
      status: "approval_pending",
      occurred_at: new Date().toISOString(),
    }));
    items.push(
      item({
        id: "approval",
        priority: 2,
        kind: "approval",
        state: "caution",
        count: awaitingViewer,
        command_requests: requests,
      }),
    );
  }
  const stale = rows.filter((r) => r["state"] === "stale");
  const planes = new Map<unknown, Row[]>();
  for (const row of stale) planes.set(row["plane"], [...(planes.get(row["plane"]) ?? []), row]);
  for (const [plane, group] of planes)
    items.push(
      item({
        id: `stale:${String(plane)}`,
        priority: 2,
        kind: "stale",
        state: "stale",
        since: group[0]?.["last_received_at"] ?? null,
        count: group.length,
        plane,
        spacecraft: group.map(member),
      }),
    );
  if (isJson(fleet["limits"]) && fleet["limits"]["configured"] === false)
    items.push(
      item({
        id: "limits_not_configured",
        priority: 3,
        kind: "limits_not_configured",
        state: "off",
      }),
    );
  const never = rows.filter((r) => r["state"] === "never_heard");
  if (never.length > 0)
    items.push(
      item({
        id: "never_heard",
        priority: 3,
        kind: "never_heard",
        state: "off",
        count: never.length,
        spacecraft: never.map(member),
      }),
    );
  const rank = (a: Json) => Number(a["priority"]);
  items.sort((a, b) => rank(a) - rank(b));
  const p1 = items.filter((i) => i["priority"] === 1);
  return {
    observed_at: new Date().toISOString(),
    stale_after_s: fleet["stale_after_s"] ?? 900,
    failure_lookback_s: 86400,
    counts: {
      p1: p1.length,
      p2: items.filter((i) => i["priority"] === 2).length,
      p3: items.filter((i) => i["priority"] === 3).length,
      spacecraft_p1: new Set(
        p1.flatMap((i) =>
          (Array.isArray(i["spacecraft"]) ? i["spacecraft"] : []).map((s: Json) => s["id"]),
        ),
      ).size,
    },
    items,
  };
}

/**
 * Refuses the console socket, so a routed `/fleet` (data or failure) isn't overwritten by the live
 * `fleet` push. Specs using this must allow `/socket\/console/` diagnostics.
 */
export async function refuseLiveSocket(page: Page): Promise<void> {
  await page.routeWebSocket(/\/socket\/console\//, (ws) => {
    void ws.close({ code: 1011, reason: "qa fixture: live socket disabled" });
  });
}

/**
 * Routes `/fleet` and `/action-queue` from one degraded fleet, so Now's panels agree.
 *
 * The fleet normally arrives over the live `fleet` push (realtime.md), which would overwrite the
 * fixture with real data, so the console socket is refused here and the app falls back to polling
 * GET /fleet. These specs therefore test presentation over the polling fallback; specs using this
 * must allow `/socket\/console/` diagnostics.
 */
export async function routeDegradedNow(page: Page, d: Degradation): Promise<void> {
  await refuseLiveSocket(page);
  let degraded: Json | null = null;
  const fleetOnce = async (): Promise<Json> => {
    if (degraded) return degraded;
    const response = await page.request.get(`/api/v1/missions/${DEMO.missionId}/fleet`);
    const body: unknown = await response.json();
    if (!isJson(body) || !isJson(body["data"])) throw new Error("fleet fixture: unexpected body");
    degraded = degradeFleet(body["data"], d);
    return degraded;
  };
  await page.route(missionApi("fleet"), async (route) => {
    await route.fulfill({ json: { data: await fleetOnce() } }).catch(() => undefined);
  });
  await page.route(missionApi("action-queue"), async (route) => {
    const fleet = await fleetOnce();
    await route
      .fulfill({ json: { data: actionQueueFor(fleet, d.awaitingViewer ?? 0) } })
      .catch(() => undefined);
  });
}

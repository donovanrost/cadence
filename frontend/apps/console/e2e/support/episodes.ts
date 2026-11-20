import type { Page, Request } from "@playwright/test";
import { jsonProblem, missionApi } from "./console.ts";

/**
 * A stateful alarm-episode fixture (contract: docs/apogee/api/alarms-console.md). The dev seed has
 * no limits, so specs route the episode reads and apply lifecycle commands here like the server
 * would. `failNext(status, code)` makes the next command answer with that error instead.
 */
type Json = Record<string, unknown>;

export interface EpisodeServer {
  /** POST bodies received, in order: `{ command, body }`. */
  readonly commands: { command: string; body: Json }[];
  failNext(status: number, code: string): void;
  state(): Json;
}

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const ADMIN = { kind: "user", id: "env-admin", name: "Cadence Administrator" };

export async function routeEpisodes(
  page: Page,
  options: { permissions?: readonly string[] } = {},
): Promise<EpisodeServer> {
  const opened = "2026-11-08T22:55:20Z";
  const episode: Json = {
    id: "alarm_episode_qa_1",
    source: "ground_limit",
    status: "new",
    cleared_unacknowledged: false,
    severity: "critical",
    peak_severity: "critical",
    source_state: "red_low",
    spacecraft_id: "spacecraft-earendil-001",
    spacecraft: { id: "spacecraft-earendil-001", name: "EARENDIL-001", scid: 1 },
    point: { id: "EPS.sa1_current", name: "sa1_current", unit: "A" },
    thresholds: { red_low: -5.5, yellow_low: -5, yellow_high: 5, red_high: 6 },
    context: {
      limit_set_name: "DEFAULT",
      limit_definition_id: "limit_qa",
      limit_definition_version: 1,
    },
    opened_at: opened,
    cleared_at: null,
    first_value: -5.8,
    last_value: -6.1,
    last_observed_at: "2026-11-08T22:55:57Z",
    last_evaluated_at: new Date(Date.now() - 120_000).toISOString(),
    acknowledged_at: null,
    acknowledged_by: null,
    assignee: null,
    assigned_at: null,
  };
  const events: Json[] = [
    { id: "event_qa_1", kind: "raised", actor: null, at: opened, payload: {} },
  ];
  const commands: { command: string; body: Json }[] = [];
  let failure: { status: number; code: string } | null = null;
  const permissions = options.permissions ?? ["alarm.acknowledge", "alarm.assign"];
  const show = () => ({ data: { ...episode, events } });

  await page.route(`${missionApi("alarm-episodes")}**`, async (route) => {
    const request: Request = route.request();
    const url = new URL(request.url());
    const rest = url.pathname.split("/alarm-episodes")[1] ?? "";
    if (request.method() === "GET" && (rest === "" || rest === "/")) {
      const sc = url.searchParams.get("spacecraft_id");
      const active = episode["status"] !== "cleared";
      const match = (!sc || sc === episode["spacecraft_id"]) && active;
      const status = episode["status"] === "new" ? "new" : "acknowledged";
      await route.fulfill({
        json: {
          data: {
            summary: {
              active: active ? 1 : 0,
              critical: { new: status === "new" ? 1 : 0, acknowledged: status === "new" ? 0 : 1 },
              caution: { new: 0, acknowledged: 0 },
            },
            permissions,
            episodes: match ? [episode] : [],
          },
        },
      });
      return;
    }
    if (request.method() === "GET") {
      await route.fulfill({ json: show() });
      return;
    }
    const command = rest.split("/").pop() ?? "";
    const raw: unknown = request.postDataJSON();
    const body: Json = isJson(raw) ? raw : {};
    commands.push({ command, body });
    if (failure) {
      const { status, code } = failure;
      failure = null;
      await route.fulfill(jsonProblem(status, code));
      return;
    }
    const at = new Date().toISOString();
    if (command === "acknowledge" && episode["status"] === "new") {
      Object.assign(episode, {
        status: "acknowledged",
        acknowledged_at: at,
        acknowledged_by: ADMIN,
      });
      events.push({
        id: `event_qa_${events.length + 1}`,
        kind: "acknowledged",
        actor: ADMIN,
        at,
        payload: {},
      });
    }
    if (command === "assign") {
      const userId = body["user_id"];
      Object.assign(episode, {
        assignee: typeof userId === "string" ? { id: userId, name: "QA Operator" } : null,
        assigned_at: typeof userId === "string" ? at : null,
      });
      events.push({
        id: `event_qa_${events.length + 1}`,
        kind: typeof userId === "string" ? "assigned" : "unassigned",
        actor: ADMIN,
        at,
        payload: body["note"] ? { note: body["note"] } : {},
      });
    }
    await route.fulfill({ json: show() });
  });

  return {
    commands,
    failNext(status, code) {
      failure = { status, code };
    },
    state: () => ({ ...episode }),
  };
}

export interface EpisodeSeed {
  readonly scid: number;
  readonly severity: "critical" | "caution";
  readonly status: "new" | "acknowledged" | "cleared";
  readonly point: string;
  /** U25 (#646): the spacecraft has no readable name, so the console must say Unknown spacecraft. */
  readonly nameless?: boolean;
}

function seeded(seed: EpisodeSeed, index: number): Json {
  const name = `EARENDIL-${String(seed.scid).padStart(3, "0")}`;
  const opened = new Date(Date.now() - (index + 1) * 600_000).toISOString();
  const cleared =
    seed.status === "cleared" ? new Date(Date.now() - index * 60_000).toISOString() : null;
  return {
    id: `alarm_episode_qa_list_${index + 1}`,
    source: "ground_limit",
    status: seed.status,
    cleared_unacknowledged: seed.status === "cleared",
    severity: seed.severity,
    peak_severity: seed.severity,
    source_state: seed.severity === "critical" ? "red_low" : "yellow_high",
    spacecraft_id: `spacecraft-earendil-${String(seed.scid).padStart(3, "0")}`,
    spacecraft: {
      id: `spacecraft-earendil-${String(seed.scid).padStart(3, "0")}`,
      name: seed.nameless ? null : name,
      scid: seed.scid,
    },
    point: { id: seed.point, name: seed.point.split(".").pop() ?? seed.point, unit: "A" },
    thresholds: { red_low: -5.5, yellow_low: -5, yellow_high: 5, red_high: 6 },
    context: {
      limit_set_name: "DEFAULT",
      limit_definition_id: "limit_qa",
      limit_definition_version: 1,
    },
    opened_at: opened,
    cleared_at: cleared,
    first_value: -5.8,
    last_value: -6.1,
    last_observed_at: opened,
    last_evaluated_at: new Date(Date.now() - 120_000).toISOString(),
    acknowledged_at: seed.status === "acknowledged" ? opened : null,
    acknowledged_by: seed.status === "acknowledged" ? ADMIN : null,
    assignee: null,
    assigned_at: null,
  };
}

/** Read-only episode list for the Alarms screen; honours `state` and `spacecraft_id`. */
export async function routeEpisodeList(page: Page, seeds: readonly EpisodeSeed[]): Promise<void> {
  const all = seeds.map(seeded);
  const active = all.filter((e) => e["status"] !== "cleared");
  const count = (severity: string, status: string) =>
    active.filter((e) => e["severity"] === severity && e["status"] === status).length;
  await page.route(`${missionApi("alarm-episodes")}**`, async (route) => {
    const url = new URL(route.request().url());
    const state = url.searchParams.get("state") ?? "active";
    const sc = url.searchParams.get("spacecraft_id");
    const episodes = all.filter(
      (e) =>
        (state === "all" ||
          (state === "cleared" ? e["status"] === "cleared" : e["status"] !== "cleared")) &&
        (!sc || e["spacecraft_id"] === sc),
    );
    await route.fulfill({
      json: {
        data: {
          summary: {
            active: active.length,
            critical: {
              new: count("critical", "new"),
              acknowledged: count("critical", "acknowledged"),
            },
            caution: {
              new: count("caution", "new"),
              acknowledged: count("caution", "acknowledged"),
            },
          },
          permissions: ["alarm.acknowledge", "alarm.assign"],
          episodes,
        },
      },
    });
  });
}

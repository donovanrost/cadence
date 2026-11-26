import type { Page, WebSocketRoute } from "@playwright/test";
import { missionApi } from "./console.ts";
import { DEMO } from "./env.ts";

/**
 * Fleet-scale fixtures and probes (#176). The seeded demo mission has 500 spacecraft; a larger
 * fleet clones its real rows with new ids, SCIDs, names and slots, so profiles, states and values
 * stay the seeded ones. Both GET /fleet and the live `fleet` push are scaled, so a screen sees one
 * consistent fleet whichever arrives first.
 */

type Json = Record<string, unknown>;

const STATES = ["critical", "caution", "stale", "nominal", "never_heard"] as const;
/** Slots per plane for the clones (the demo's planes stay as seeded). */
const SLOTS = 40;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function rowsOf(data: Json): Json[] {
  const rows = data["spacecraft"];
  if (!Array.isArray(rows)) throw new Error("scale fixture: data.spacecraft is not an array");
  return rows.filter(isJson);
}

function numberOf(value: unknown): number {
  return typeof value === "number" ? value : 0;
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

/** A Phoenix V2 frame: [join_ref, ref, topic, event, payload]. */
type Frame = [string | null, string | null, string, string, unknown];

function frameOf(message: string | Buffer): Frame | null {
  if (typeof message !== "string") return null;
  try {
    const parsed: unknown = JSON.parse(message);
    if (Array.isArray(parsed) && parsed.length === 5 && typeof parsed[3] === "string")
      return parsed as Frame;
  } catch {
    // Not a channel frame.
  }
  return null;
}

export interface ScaledFleet {
  /** The scaled fleet as the screen got it (GET /fleet). */
  readonly fleet: () => Json;
  /** Sends one full-fleet push in which every row changed; resolves once it is on the wire. */
  readonly pushAll: (round: number) => Promise<void>;
}

/**
 * Serves `size` spacecraft to the page: GET /fleet is fulfilled from the real response scaled up,
 * and on the live socket every server `fleet` full snapshot is replaced by the scaled one while
 * server deltas are dropped (they would carry the seeded counts and break the partition). Other
 * frames pass unchanged both ways.
 */
export async function serveScaledFleet(page: Page, size: number): Promise<ScaledFleet> {
  let scaled: Json | null = null;
  const fleet = async (): Promise<Json> => {
    if (scaled) return scaled;
    const response = await page.request.get(`/api/v1/missions/${DEMO.missionId}/fleet`);
    const body: unknown = await response.json();
    if (!isJson(body) || !isJson(body["data"])) throw new Error("scale fixture: unexpected body");
    scaled = scaleFleet(body["data"], size);
    return scaled;
  };
  await page.route(missionApi("fleet"), async (route) => {
    await route.fulfill({ json: { data: await fleet() } }).catch(() => undefined);
  });

  const topic = `mission:${DEMO.missionId}`;
  let socket: WebSocketRoute | null = null;
  let joinRef: string | null = null;
  let seq = 0;
  await page.routeWebSocket(
    (url) => url.pathname.endsWith("/websocket"),
    (ws) => {
      socket = ws;
      const server = ws.connectToServer();
      ws.onMessage((message) => server.send(message));
      server.onMessage((message) => {
        const frame = frameOf(message);
        const push = frame?.[4];
        if (!frame || frame[2] !== topic || frame[3] !== "fleet" || !isJson(push))
          return ws.send(message);
        if (push["full"] !== true) return; // a server delta: dropped
        const [ref, msgRef] = frame;
        joinRef = ref;
        seq = numberOf(push["seq"]);
        void fleet().then((data) => {
          ws.send(JSON.stringify([ref, msgRef, topic, "fleet", { ...push, ...data }]));
        });
      });
    },
  );

  return {
    fleet: () => {
      if (!scaled) throw new Error("scale fixture: the fleet hasn't been served yet");
      return scaled;
    },
    pushAll: async (round) => {
      if (!socket) throw new Error("scale fixture: no live socket to push on");
      const data = changedFleet(await fleet(), round);
      seq += 1;
      const payload = { ...data, seq, full: true, heard: {}, removed: [] };
      socket.send(JSON.stringify([joinRef, null, topic, "fleet", payload]));
    },
  };
}

/**
 * Installs the in-page probes before the app loads:
 * - long tasks (PerformanceObserver, buffered);
 * - "ready": the first frame where the shell is ready, the fleet read has finished, and no
 *   loading status is left in <main>; checked once per frame on a handful of elements only;
 * - push cost: for each `fleet` frame from the socket, from its arrival to the end of the next
 *   frame's style and layout (forced), so Vue's patch and the layout it causes are both counted.
 */
export async function installScaleProbes(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const probe = {
      tasks: [] as number[],
      readyAt: null as number | null,
      pushes: [] as number[],
    };
    Object.assign(window, { __scale: probe });

    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) probe.tasks.push(entry.duration);
    }).observe({ type: "longtask", buffered: true });

    const fleetDone = () =>
      performance
        .getEntriesByType("resource")
        .some(
          (e) => /\/fleet(\?|$)/.test(e.name) && (e as PerformanceResourceTiming).responseEnd > 0,
        );
    const loading = (main: Element) =>
      Array.from(main.querySelectorAll('[role="status"]')).some((s) =>
        /loading/i.test(s.textContent ?? ""),
      );
    const watch = () => {
      const main = document.querySelector("main");
      if (document.body?.hasAttribute("data-shell-ready") && main && fleetDone() && !loading(main))
        probe.readyAt = performance.now();
      else requestAnimationFrame(watch);
    };
    requestAnimationFrame(watch);

    const handlers = new WeakMap<object, unknown>();
    const descriptor = Object.getOwnPropertyDescriptor(WebSocket.prototype, "onmessage");
    Object.defineProperty(WebSocket.prototype, "onmessage", {
      configurable: true,
      get(this: WebSocket) {
        return handlers.get(this) ?? null;
      },
      set(this: WebSocket, handler: ((event: MessageEvent) => void) | null) {
        handlers.set(this, handler);
        descriptor?.set?.call(this, (event: MessageEvent) => {
          const fleet = typeof event.data === "string" && event.data.includes('"fleet",{');
          const start = performance.now();
          handler?.call(this, event);
          if (!fleet) return;
          requestAnimationFrame(() => {
            document.body.getBoundingClientRect();
            probe.pushes.push(performance.now() - start);
          });
        });
      },
    });
  });
}

export interface LoadMetrics {
  readonly readyMs: number;
  readonly longestTaskMs: number;
  readonly tasksOver50: number;
  readonly pushMs: number;
  readonly heapMb: number;
}

/** Waits for the probe's ready mark (ms since navigation start); throws on timeout. */
export async function readyAt(page: Page, timeoutMs = 30_000): Promise<number> {
  const handle = await page.waitForFunction(
    () => (window as unknown as { __scale: { readyAt: number | null } }).__scale.readyAt,
    undefined,
    { timeout: timeoutMs, polling: 100 },
  );
  const value: unknown = await handle.jsonValue();
  if (typeof value !== "number") throw new Error("scale probe: no ready time");
  return value;
}

/** The pushes the probe has timed so far. */
export async function pushTimes(page: Page): Promise<number[]> {
  return page.evaluate(() => [
    ...(window as unknown as { __scale: { pushes: number[] } }).__scale.pushes,
  ]);
}

/** Long-task durations so far. */
export async function longTasks(page: Page): Promise<number[]> {
  return page.evaluate(() => [
    ...(window as unknown as { __scale: { tasks: number[] } }).__scale.tasks,
  ]);
}

/** JS heap in use after a forced garbage collection, in MB (Chromium, via CDP). */
export async function heapMb(page: Page): Promise<number> {
  const cdp = await page.context().newCDPSession(page);
  try {
    await cdp.send("HeapProfiler.collectGarbage");
    await cdp.send("Performance.enable");
    const { metrics } = await cdp.send("Performance.getMetrics");
    const used = metrics.find((m) => m.name === "JSHeapUsedSize")?.value ?? 0;
    return used / (1024 * 1024);
  } finally {
    await cdp.detach();
  }
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

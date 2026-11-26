import type { Page, WebSocketRoute } from "@playwright/test";
import { missionApi } from "./console.ts";
import { DEMO } from "./env.ts";
import { changedFleet, isJson, numberOf, scaleFleet, type Json } from "./scale-fleet.ts";
import {
  countsOf,
  PASS_PAGE,
  passPage,
  passesOf,
  scalePasses,
  schedulePasses,
} from "./scale-passes.ts";

/**
 * Fleet-scale fixtures and probes (#176). The seeded demo mission has 500 spacecraft; a larger
 * fleet clones its real rows with new ids, SCIDs, names and slots, so profiles, states and values
 * stay the seeded ones. Both GET /fleet and the live `fleet` push are scaled, so a screen sees one
 * consistent fleet whichever arrives first. GET /passes is scaled with it (#909): each clone gets
 * its seeded craft's passes, served in cursor pages of 500.
 */

/** What the in-page probe records (installScaleProbes). */
export interface ScaleProbe {
  tasks: number[];
  readyAt: number | null;
  pushes: number[];
}

declare global {
  interface Window {
    __scale?: ScaleProbe;
  }
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
  await servePasses(page, fleet);

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

type PassWindow = Readonly<{ from: unknown; to: unknown; counts: Json; passes: Json[] }>;

/** The most pages of the real window the fixture walks (as fetchPasses' ceiling). */
const MAX_PASS_PAGES = 100;

/**
 * #909: GET /passes at fleet scale. Each window (its query without cursor and limit) is read from
 * the server once, every page; its passes are repeated for the fleet's clones and a booked
 * schedule for every craft is added (`schedulePasses`); and it is served in pages of 500 with an
 * offset cursor, so the console walks it as it walks the server's. GET /passes/:id isn't routed.
 */
async function servePasses(page: Page, fleet: () => Promise<Json>): Promise<void> {
  const windows = new Map<string, Promise<PassWindow>>();
  const windowOf = async (query: URLSearchParams): Promise<PassWindow> => {
    const path = `/api/v1/missions/${DEMO.missionId}/passes`;
    const passes: Json[] = [];
    let first: Json | null = null;
    let cursor: string | null = null;
    for (let pages = 0; pages < MAX_PASS_PAGES; pages += 1) {
      const q = new URLSearchParams(query);
      q.set("limit", String(PASS_PAGE));
      if (cursor !== null) q.set("cursor", cursor);
      const body: unknown = await (await page.request.get(`${path}?${q.toString()}`)).json();
      if (!isJson(body) || !isJson(body["data"]))
        throw new Error("scale fixture: unexpected passes");
      first ??= body["data"];
      passes.push(...passesOf(body["data"]));
      const meta = isJson(body["meta"]) ? body["meta"] : {};
      cursor = typeof meta["next_cursor"] === "string" ? meta["next_cursor"] : null;
      if (cursor === null) break;
    }
    if (first === null) throw new Error("scale fixture: no passes page");
    const fleetRows = (await fleet())["spacecraft"];
    const rows = Array.isArray(fleetRows) ? fleetRows.filter(isJson) : [];
    const now = Date.now();
    const from = Date.parse(String(first["from"]));
    const to = Date.parse(String(first["to"]));
    // The window's own filters apply to the schedule too (Investigate reads one craft's passes).
    const craft = query.get("spacecraft_id");
    const station = query.get("station");
    const grown = [...scalePasses(passes, rows), ...schedulePasses(rows, from, to, now)]
      .filter((p) => craft === null || p["spacecraft_id"] === craft)
      .filter((p) => station === null || !isJson(p["station"]) || p["station"]["ref"] === station)
      .sort((a, b) => String(a["starts_at"]).localeCompare(String(b["starts_at"])));
    return { from: first["from"], to: first["to"], counts: countsOf(grown, now), passes: grown };
  };
  await page.route(new RegExp(`/api/v1/missions/${DEMO.missionId}/passes\\?`), async (route) => {
    const url = new URL(route.request().url());
    const cursor = url.searchParams.get("cursor");
    const limit = Number(url.searchParams.get("limit") ?? PASS_PAGE);
    const query = new URLSearchParams(url.searchParams);
    query.delete("cursor");
    query.delete("limit");
    const key = query.toString();
    const window = windows.get(key) ?? windowOf(query);
    windows.set(key, window);
    await route.fulfill({ json: passPage(await window, cursor, limit) }).catch(() => undefined);
  });
}

/**
 * Installs the in-page probes before the app loads:
 * - long tasks (PerformanceObserver, buffered);
 * - "ready": the first frame where the shell is ready, the app's GET /fleet body has arrived, and
 *   no loading status is left in <main>; checked once per frame on a handful of elements only;
 * - push cost: for each `fleet` frame from the socket, from its arrival to the end of the next
 *   frame's style and layout (forced), so Vue's patch and the layout it causes are both counted.
 *   It includes the wait for that frame (up to ~16 ms at 60 Hz), so it errs high.
 */
export async function installScaleProbes(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const probe: ScaleProbe = { tasks: [], readyAt: null, pushes: [] };
    window.__scale = probe;

    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) probe.tasks.push(entry.duration);
    }).observe({ type: "longtask", buffered: true });

    // A response fulfilled by page.route gets no Resource Timing entry, so the probe watches the
    // app's own fetch of GET /fleet and marks it once the body has arrived.
    let fleetRead = false;
    const fetchOriginal = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const response = await fetchOriginal(input, init);
      const url = input instanceof Request ? input.url : String(input);
      if (/\/missions\/[^/]+\/fleet(\?|$)/.test(url))
        void response
          .clone()
          .text()
          .then(() => (fleetRead = true));
      return response;
    };
    const fleetDone = () => fleetRead;
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
  const handle = await page.waitForFunction(() => window.__scale?.readyAt ?? null, undefined, {
    timeout: timeoutMs,
    polling: 100,
  });
  const value: unknown = await handle.jsonValue();
  if (typeof value !== "number") throw new Error("scale probe: no ready time");
  return value;
}

/** The pushes the probe has timed so far. */
export async function pushTimes(page: Page): Promise<number[]> {
  return page.evaluate(() => [...(window.__scale?.pushes ?? [])]);
}

/** Long-task durations so far. */
export async function longTasks(page: Page): Promise<number[]> {
  return page.evaluate(() => [...(window.__scale?.tasks ?? [])]);
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

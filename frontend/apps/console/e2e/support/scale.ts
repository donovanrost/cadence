import type { Page, WebSocketRoute } from "@playwright/test";
import { missionApi } from "./console.ts";
import { DEMO } from "./env.ts";
import { changedFleet, isJson, numberOf, scaleFleet, type Json } from "./scale-fleet.ts";

/**
 * Fleet-scale fixtures and probes (#176). The seeded demo mission has 500 spacecraft; a larger
 * fleet clones its real rows with new ids, SCIDs, names and slots, so profiles, states and values
 * stay the seeded ones. Both GET /fleet and the live `fleet` push are scaled, so a screen sees one
 * consistent fleet whichever arrives first.
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
 *   It includes the wait for that frame (up to ~16 ms at 60 Hz), so it errs high.
 */
export async function installScaleProbes(page: Page): Promise<void> {
  await page.addInitScript(() => {
    const probe: ScaleProbe = { tasks: [], readyAt: null, pushes: [] };
    window.__scale = probe;

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

import type { Page } from "@playwright/test";

/**
 * Request cost per screen (CTO, #1037): every `/api/v1` request and socket channel join a screen
 * makes while it loads, timed from the test's side. The rule being measured: a request's query
 * count must not grow with fleet size, so a screen that reads once per spacecraft, or waits on a
 * long chain of reads, is a finding.
 */

export interface ApiCall {
  readonly method: string;
  /** Path and query, as sent. */
  readonly url: string;
  /** The path with ids replaced by `:id` and no query, so repeated per-row reads group. */
  readonly endpoint: string;
  readonly start: number;
  end: number | null;
  bytes: number;
  status: number | null;
}

export interface Join {
  readonly topic: string;
  readonly at: number;
}

export interface Recorder {
  readonly calls: ApiCall[];
  readonly joins: Join[];
  /** A join the socket fixture saw (a routed socket raises no frame events to listen to). */
  join(topic: string): void;
  /** Waits for every response body started so far, so byte counts are complete. */
  settle(): Promise<void>;
}

/** A path segment that names one thing (an id, a SCID, a slug with digits), never a route word. */
const ID = /\d|:|^[0-9a-f]{8}-/i;

export function endpointOf(url: string): string {
  const path = new URL(url, "http://x").pathname.replace(/^\/api\/v1/, "");
  return path
    .split("/")
    .map((seg, i, all) => (i > 0 && (ID.test(seg) || all[i - 1] === "missions") ? ":id" : seg))
    .join("/");
}

/** Records the page's `/api/v1` requests and channel joins from now on. */
export function recordRequests(page: Page): Recorder {
  const calls: ApiCall[] = [];
  const joins: Join[] = [];
  const pending: Promise<unknown>[] = [];
  const byRequest = new Map<object, ApiCall>();
  page.on("request", (request) => {
    const url = request.url();
    if (!new URL(url).pathname.startsWith("/api/v1/")) return;
    const call: ApiCall = {
      method: request.method(),
      url: url.replace(/^https?:\/\/[^/]+/, ""),
      endpoint: endpointOf(url),
      start: Date.now(),
      end: null,
      bytes: 0,
      status: null,
    };
    calls.push(call);
    byRequest.set(request, call);
  });
  page.on("requestfinished", (request) => {
    const call = byRequest.get(request);
    if (!call) return;
    call.end = Date.now();
    pending.push(
      request
        .response()
        .then(async (response) => {
          call.status = response?.status() ?? null;
          call.bytes = (await response?.body())?.length ?? 0;
        })
        .catch(() => undefined),
    );
  });
  page.on("requestfailed", (request) => {
    const call = byRequest.get(request);
    if (call) call.end = Date.now();
  });
  return {
    calls,
    joins,
    join: (topic) => joins.push({ topic, at: Date.now() }),
    settle: async () => {
      await Promise.all(pending);
    },
  };
}

export interface RequestCost {
  /** `/api/v1` requests started before the screen was usable. */
  readonly requests: number;
  /** Channel joins (`phx_join`) during the whole load: the screen's live subscriptions. */
  readonly joins: number;
  /**
   * The longest chain of requests where each starts only after an earlier one's response has
   * arrived (a waterfall). 1 = everything in parallel. Measured from timings, so two reads that
   * merely start late count as a chain too; `chain` names it so a reader can judge.
   */
  readonly serialDepth: number;
  readonly chain: readonly string[];
  /** Response bodies of those requests, in bytes. */
  readonly bytes: number;
  /** Endpoints read more than once with different ids: per-row reads, the finding the rule names. */
  readonly repeated: readonly Readonly<{ endpoint: string; count: number }>[];
  /** Cursor pages after a read's first (`?cursor=`): they grow with the data, not per spacecraft. */
  readonly pages: readonly Readonly<{ endpoint: string; count: number }>[];
}

/** The URL without its cursor: pages of one read are one read. */
const withoutCursor = (url: string) => {
  const u = new URL(url, "http://x");
  u.searchParams.delete("cursor");
  return `${u.pathname}?${u.searchParams.toString()}`;
};

/** An endpoint read this many times or more with different ids counts as per-row reads. */
const PER_ROW = 5;

/** The cost of a load: what started before `readyAt` (epoch ms). */
export function costOf(recorder: Recorder, readyAt: number): RequestCost {
  const before = recorder.calls.filter((c) => c.start <= readyAt);
  const depth = new Map<ApiCall, { n: number; prev: ApiCall | null }>();
  const sorted = [...before].sort((a, b) => a.start - b.start);
  for (const c of sorted) {
    let best: { n: number; prev: ApiCall | null } = { n: 1, prev: null };
    for (const p of sorted) {
      if (p === c || p.end === null || p.end > c.start) continue;
      const d = depth.get(p);
      if (d && d.n + 1 > best.n) best = { n: d.n + 1, prev: p };
    }
    depth.set(c, best);
  }
  let deepest: ApiCall | null = null;
  for (const c of sorted)
    if (!deepest || (depth.get(c)?.n ?? 0) > (depth.get(deepest)?.n ?? 0)) deepest = c;
  const chain: string[] = [];
  for (let c = deepest; c; c = depth.get(c)?.prev ?? null)
    chain.unshift(`${c.method} ${c.endpoint}`);
  const urls = new Map<string, Set<string>>();
  const pages = new Map<string, number>();
  for (const c of before) {
    const key = `${c.method} ${c.endpoint}`;
    urls.set(key, (urls.get(key) ?? new Set()).add(withoutCursor(c.url)));
    if (new URL(c.url, "http://x").searchParams.has("cursor"))
      pages.set(key, (pages.get(key) ?? 0) + 1);
  }
  return {
    requests: before.length,
    joins: recorder.joins.length,
    serialDepth: deepest ? (depth.get(deepest)?.n ?? 0) : 0,
    chain,
    bytes: before.reduce((n, c) => n + c.bytes, 0),
    repeated: [...urls]
      .filter(([, set]) => set.size >= PER_ROW)
      .map(([endpoint, set]) => ({ endpoint, count: set.size })),
    pages: [...pages].map(([endpoint, count]) => ({ endpoint, count })),
  };
}

import { effectScope, nextTick, ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { useAlarmPages } from "./useAlarmPages.ts";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));

const wireAlarm = (n: number) => ({
  id: `alarm-${n}`,
  spacecraft_id: `sc-${n}`,
  point: { id: "EPS.VBAT", name: "VBAT", subsystem: "EPS", unit: "V", description: null },
  severity: "caution",
  active: true,
  condition: "yellow_high",
  value: 30,
  limit_set_name: "DEFAULT",
  thresholds: { red_low: null, yellow_low: null, yellow_high: 20, red_high: null },
  first_crossed_at: "2026-11-26T12:00:00Z",
  generation_time: "2026-11-26T12:00:00Z",
  received_at: "2026-11-26T12:00:01Z",
});

/** A server holding `total` alarms, `size` to a page, answering by cursor (the page's first index). */
function server(total: number, size: number) {
  const urls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      urls.push(input);
      const cursor = new URL(input, "http://x").searchParams.get("cursor");
      const from = cursor === null ? 0 : Number(cursor);
      const to = Math.min(from + size, total);
      const body = {
        data: {
          observed_at: "2026-11-26T12:00:02Z",
          summary: { active: total, critical: 0, caution: total, latest_transition_at: null },
          total,
          alarms: Array.from({ length: to - from }, (_, i) => wireAlarm(from + i)),
        },
        meta: { next_cursor: to < total ? String(to) : null },
      };
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }),
  );
  return urls;
}

const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
  await nextTick();
};

function start(query: ReturnType<typeof ref<Record<string, unknown> | null>>) {
  const scope = effectScope();
  const pages = scope.run(() =>
    useAlarmPages(ref(missionIdReader("m")), () => query.value as never),
  );
  if (!pages) throw new Error("no pages");
  return { scope, pages };
}

afterEach(() => vi.unstubAllGlobals());

describe("useAlarmPages (#827)", () => {
  it("holds a page, says how many match, and appends the next page on Load more", async () => {
    const urls = server(450, 200);
    const t = start(ref({ state: "active", limit: 200 }));
    await flush();

    const first = t.pages.state.value;
    if (first.status !== "ready") throw new Error("not ready");
    expect(first.value.alarms).toHaveLength(200);
    // It never looks complete when it isn't: the total is the server's, and there is a next page.
    expect(first.value.total).toBe(450);
    expect(first.value.next).toBe("200");

    await t.pages.more();
    await flush();
    const second = t.pages.state.value;
    if (second.status !== "ready") throw new Error("not ready");
    expect(second.value.alarms).toHaveLength(400);
    expect(second.value.next).toBe("400");

    await t.pages.more();
    await flush();
    const last = t.pages.state.value;
    if (last.status !== "ready") throw new Error("not ready");
    expect(last.value.alarms).toHaveLength(450);
    expect(last.value.next).toBeNull();
    expect(new Set(last.value.alarms.map((a) => a.id)).size).toBe(450);

    expect(urls[0]).toContain("state=active");
    expect(urls[0]).toContain("limit=200");
    expect(urls[1]).toContain("cursor=200");
    t.scope.stop();
  });

  it("a short list is one page with no next", async () => {
    server(3, 200);
    const t = start(ref({ state: "active" }));
    await flush();
    const s = t.pages.state.value;
    if (s.status !== "ready") throw new Error("not ready");
    expect(s.value.alarms).toHaveLength(3);
    expect(s.value.next).toBeNull();
    expect(s.value.total).toBe(3);
    t.scope.stop();
  });

  it("asks nothing while its query is null, and starts over when it changes", async () => {
    const urls = server(5, 200);
    const query = ref<Record<string, unknown> | null>(null);
    const t = start(query);
    await flush();
    expect(urls).toEqual([]);
    expect(t.pages.state.value.status).toBe("loading");

    query.value = { state: "active", q: "vbat" };
    await flush();
    expect(urls).toHaveLength(1);
    expect(urls[0]).toContain("q=vbat");
    expect(t.pages.state.value.status).toBe("ready");
    t.scope.stop();
  });
});

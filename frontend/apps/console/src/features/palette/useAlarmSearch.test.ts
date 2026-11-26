import { effectScope, nextTick, ref } from "vue";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { useAlarmSearch } from "./useAlarmSearch.ts";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));

const fleet = [spacecraftRow(312), spacecraftRow(31)];
/** The first spacecraft's id (312). */
const CRAFT = spacecraftRow(312).id;

const wire = (id: string, spacecraft: string, point: string) => ({
  id,
  spacecraft_id: spacecraft,
  point: { id: `pt-${point}`, name: point, subsystem: null, unit: "V", description: null },
  severity: "critical",
  active: true,
  condition: "red_low",
  value: 23,
  limit_set_name: null,
  thresholds: { red_low: 24, yellow_low: null, yellow_high: null, red_high: null },
  first_crossed_at: null,
  generation_time: null,
  received_at: null,
});

type Answer = Readonly<{ alarms: ReturnType<typeof wire>[]; total: number; next: string | null }>;

/** The server, answering by what the request asks: a point's text (`q`) or one spacecraft. */
function server(by: { q?: Answer; spacecraft?: Record<string, Answer> }) {
  const urls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      urls.push(input);
      const params = new URL(input, "http://x").searchParams;
      const answer =
        params.get("q") !== null ? by.q : by.spacecraft?.[params.get("spacecraft_id") ?? ""];
      const a = answer ?? { alarms: [], total: 0, next: null };
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: {
              observed_at: "2026-11-26T12:00:00Z",
              summary: {
                active: a.total,
                critical: a.total,
                caution: 0,
                latest_transition_at: null,
              },
              total: a.total,
              alarms: a.alarms,
            },
            meta: { next_cursor: a.next },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }),
  );
  return urls;
}

const settle = async () => {
  await vi.advanceTimersByTimeAsync(300);
  for (let i = 0; i < 12; i++) await Promise.resolve();
  await nextTick();
};

function start(text = "") {
  const raw = ref(text);
  const scope = effectScope();
  const search = scope.run(() => useAlarmSearch(ref(missionIdReader("m")), raw, ref(fleet)));
  if (!search) throw new Error("no search");
  return { raw, scope, search };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("the phone sheet's alarm search (#827)", () => {
  it("asks nothing until there is text, and not until typing settles", async () => {
    const urls = server({});
    const t = start();
    await settle();
    expect(urls).toEqual([]);
    expect(t.search.state.value).toBe("ready");

    t.raw.value = "vb";
    await nextTick();
    expect(t.search.state.value).toBe("loading");
    expect(urls).toEqual([]);
    t.raw.value = "vbat";
    await settle();
    expect(urls).toHaveLength(1);
    expect(urls[0]).toContain("q=vbat");
    expect(t.search.state.value).toBe("ready");
    t.scope.stop();
  });

  it("sends the text to the server as q, so an alarm beyond the first 200 is found", async () => {
    server({
      q: { alarms: [wire("deep-1", CRAFT, "VBAT")], total: 1, next: null },
    });
    const t = start("vbat");
    await settle();
    expect(t.search.alarms.value.map((a) => a.id)).toEqual(["deep-1"]);
    expect(t.search.truncated.value).toBe(false);
    t.scope.stop();
  });

  it("a spacecraft the text names is asked for its own alarms, merged and deduped", async () => {
    const urls = server({
      q: { alarms: [wire("a-1", CRAFT, "VBAT")], total: 1, next: null },
      spacecraft: {
        [CRAFT]: {
          alarms: [wire("a-1", CRAFT, "VBAT"), wire("a-2", CRAFT, "TEMP")],
          total: 2,
          next: null,
        },
      },
    });
    const t = start("312");
    await settle();
    expect(urls.some((u) => u.includes(`spacecraft_id=${CRAFT}`))).toBe(true);
    expect(t.search.alarms.value.map((a) => a.id).sort()).toEqual(["a-1", "a-2"]);
    t.scope.stop();
  });

  it("says when more match than were read, so the sheet never looks complete", async () => {
    server({
      q: { alarms: [wire("a-1", CRAFT, "VBAT")], total: 400, next: "50" },
    });
    const t = start("vbat");
    await settle();
    expect(t.search.truncated.value).toBe(true);
    t.scope.stop();
  });
});

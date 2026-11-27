import { flushPromises, mount } from "@vue/test-utils";
import { ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId, spacecraftId } from "@/api";
import { coverageWire, elementSetWire, passWire } from "./fixtures.ts";
import OrbitSection from "./OrbitSection.vue";

const connection = ref<"connecting" | "live" | "offline">("live");
vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useMissionInvalidation: () => undefined,
  useConnection: () => connection,
}));
afterEach(() => {
  vi.unstubAllGlobals();
  connection.value = "live";
});

type Wire = Readonly<{
  current: unknown;
  history?: unknown[];
  passes?: unknown[];
  coverage?: unknown;
}>;

/** A server answering the three Orbit reads; returns the paths asked for. */
function server(w: Wire) {
  const asked: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      const url = new URL(input, "http://x");
      asked.push(url.pathname);
      const body = url.pathname.endsWith("/element-sets/current")
        ? { data: w.current }
        : url.pathname.endsWith("/element-sets")
          ? { data: w.history ?? [], meta: { next_cursor: null } }
          : {
              data: w.passes ?? [],
              meta: { next_cursor: null, coverage: w.coverage ?? coverageWire() },
            };
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }),
  );
  return asked;
}

async function mountSection() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { template: "<div />" } },
      { path: "/stations/:stationId?", name: "setup.stations", component: { template: "<div />" } },
    ],
  });
  const w = mount(OrbitSection, {
    props: { missionId: missionId("m-1"), spacecraftId: spacecraftId("sc-312") },
    global: { plugins: [router] },
  });
  await flushPromises();
  return w;
}

describe("OrbitSection (#895)", () => {
  it("says no orbit is stored when the current set is null, and reads no history", async () => {
    const asked = server({ current: null });
    const w = await mountSection();
    expect(w.text()).toContain("No orbit stored");
    expect(asked.filter((p) => p.endsWith("/element-sets"))).toEqual([]);
    w.unmount();
  });

  it("shows the current set, its history, and the week's passes with their coverage", async () => {
    const older = elementSetWire({ id: "elset_1", epoch: "2026-11-20T00:00:00Z" });
    server({
      current: elementSetWire(),
      history: [elementSetWire(), older],
      passes: [passWire()],
      coverage: coverageWire(
        { horizon_end: "2026-11-30T00:00:00Z" },
        { stations_without_location: 1 },
      ),
    });
    const w = await mountSection();
    const text = w.text();
    expect(text).toContain("Manual · Mira K.");
    expect(w.findAll("table")[0]?.findAll("tbody tr")).toHaveLength(2);
    expect(text).toContain("Current");
    const station = w.get('a[href="/stations/ground_station_sva"]');
    expect(station.text()).toBe("Svalbard · SVA");
    expect(text).toContain("11-27 00:41:12Z");
    expect(text).toContain("38.2°");
    expect(text).toContain("Passes are predicted up to 11-30 00:00Z.");
    expect(text).toContain("1 station has no location, so its passes aren't predicted.");
    w.unmount();
  });

  it("says a deep-space orbit isn't predicted, with no passes", async () => {
    server({ current: elementSetWire(), coverage: coverageWire({}, { spacecraft_deep_space: 1 }) });
    const w = await mountSection();
    expect(w.text()).toContain("Cadence doesn't predict passes for deep-space orbits yet.");
    expect(w.text()).toContain("No predicted passes in the next 7 days");
    w.unmount();
  });

  it("asks the spacecraft's predicted passes for now to now + 7 days", async () => {
    server({ current: null });
    const stubbed = vi.mocked(globalThis.fetch);
    const w = await mountSection();
    const passes = stubbed.mock.calls
      .map((c) => new URL(typeof c[0] === "string" ? c[0] : "", "http://x"))
      .find((u) => u.pathname.endsWith("/predicted-passes"));
    const from = Date.parse(passes?.searchParams.get("from") ?? "");
    const to = Date.parse(passes?.searchParams.get("to") ?? "");
    expect(passes?.pathname).toContain("/missions/m-1/spacecraft/sc-312/predicted-passes");
    expect(to - from).toBe(7 * 86_400_000);
    w.unmount();
  });

  it("says the orbit may be out of date while the live link is down", async () => {
    connection.value = "offline";
    server({ current: null });
    const w = await mountSection();
    expect(w.text()).toContain("Live connection lost.");
    w.unmount();
  });
});

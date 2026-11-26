import { defineComponent, h, nextTick, ref } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import {
  missionId as missionIdReader,
  spacecraftId as spacecraftIdReader,
  pointId as pointIdReader,
} from "@/api/index.ts";
import type { PointId, RemoteState } from "@/api/index.ts";
import type { SampleRead } from "./api.ts";
import { readySample, statusOnly } from "./fixtures.ts";
import SampleAside from "./SampleAside.vue";
import { useSample } from "./useSample.ts";

const fetchSample = vi.hoisted(() => vi.fn());
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  fetchSample,
}));

const ready = (value: SampleRead): RemoteState<SampleRead> => ({
  status: "ready",
  value,
  receivedAt: new Date(),
});
const mounted: { unmount: () => void }[] = [];
afterEach(() => mounted.splice(0).forEach((w) => w.unmount()));
function aside(state: RemoteState<SampleRead>) {
  const w = mount(SampleAside, {
    props: {
      state,
      title: "Sample · Battery voltage",
      atLabel: "02:08:11Z",
      today: "2026-11-08",
      wide: true,
      returnFocus: () => null,
    },
    attachTo: document.body,
  });
  mounted.push(w);
  return w;
}

describe("ux U80: the Sample aside in T1's column", () => {
  it("takes focus on its heading and shows the rows", async () => {
    const w = aside(ready(readySample()));
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("Sample · Battery voltage");
    expect(w.text()).toContain("Fairbanks · binding Earendil telemetry v3");
    expect(w.text()).toContain("Technical details");
  });

  it("closes on Esc and on its named ✕", async () => {
    const w = aside(ready(readySample()));
    await w.get("section").trigger("keydown", { key: "Escape" });
    await w.get('button[aria-label="Close sample"]').trigger("click");
    expect(w.emitted("close")).toHaveLength(2);
  });

  it("offers the plot for an ambiguous match, and Try again for a timeout", async () => {
    const amb = aside(ready(statusOnly("ambiguous")));
    const show = amb.findAll("button").find((b) => b.text() === "Show 02:08:11Z on the plot");
    await show?.trigger("click");
    expect(amb.emitted("close")).toHaveLength(1);
    const slow = aside(ready(statusOnly("timeout")));
    await slow
      .findAll("button")
      .find((b) => b.text() === "Try again")
      ?.trigger("click");
    expect(slow.emitted("retry")).toHaveLength(1);
  });

  it("shows not_found in the body, never a blank", () => {
    expect(aside(ready(statusOnly("not_found"))).text()).toContain(
      "Cadence couldn't find this sample in the history store.",
    );
  });
});

describe("lead: ?sample= is a permalink", () => {
  async function harness(path: string) {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/t", component: { render: () => null } }],
    });
    await router.push(path);
    let api: ReturnType<typeof useSample> | null = null;
    const Host = defineComponent(() => {
      api = useSample(
        ref(missionIdReader("m-1")),
        ref(spacecraftIdReader("sc-312")),
        ref<PointId | null>(pointIdReader("EPS.VBAT")),
      );
      return () => h("div");
    });
    mounted.push(mount(Host, { global: { plugins: [router] } }));
    await flushPromises();
    return { router, api: () => api };
  }

  it("reads the sample exactly on a cold load, with no alarm context", async () => {
    fetchSample.mockResolvedValue({ ok: true, value: readySample() });
    const { api } = await harness(
      "/t?points=EPS.VBAT&sample=s-1&received=2026-11-08T02%3A08%3A12.880Z",
    );
    expect(fetchSample).toHaveBeenLastCalledWith(
      "m-1",
      {
        sampleId: "s-1",
        pointId: pointIdReader("EPS.VBAT"),
        spacecraftId: "sc-312",
        receiptTime: "2026-11-08T02:08:12.880Z",
        at: null,
      },
      expect.anything(),
    );
    expect(api()?.open.value).toBe(true);
  });

  it("without received passes at, so api searches ±60 s (it may answer ambiguous)", async () => {
    fetchSample.mockResolvedValue({ ok: true, value: statusOnly("ambiguous") });
    await harness("/t?sample=s-1&at=2026-11-08T02%3A08%3A11Z");
    expect(fetchSample.mock.lastCall?.[1]).toMatchObject({
      receiptTime: null,
      at: "2026-11-08T02:08:11Z",
    });
  });

  it("closing drops both keys and keeps the rest", async () => {
    fetchSample.mockResolvedValue({ ok: true, value: readySample() });
    const { router, api } = await harness(
      "/t?points=EPS.VBAT&at=x&sample=s-1&received=2026-11-08T02%3A08%3A12Z",
    );
    await api()?.close();
    expect(router.currentRoute.value.query).toEqual({ points: "EPS.VBAT", at: "x" });
  });
});

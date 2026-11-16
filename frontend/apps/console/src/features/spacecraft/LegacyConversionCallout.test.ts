import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId as missionIdReader } from "@/api";
import { conversionReader } from "./legacy-conversion.ts";
import LegacyConversionCallout from "./LegacyConversionCallout.vue";

/** TEMPORARY with the conversion (9ac6dc8ee): ux U79's flow, against api v3.2 fixtures. */
const api = vi.hoisted(() => ({
  read: { ok: true, value: null } as unknown,
  staged: { ok: true, value: null } as unknown,
  push: vi.fn(() => Promise.resolve()),
}));
vi.mock("./legacy-conversion.ts", async (original) => ({
  ...(await original<typeof import("./legacy-conversion.ts")>()),
  fetchConversion: () => Promise.resolve(api.read),
  stageNextBatch: () => Promise.resolve(api.staged),
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  useRouter: () => ({ push: api.push }),
}));

function read(extra: Record<string, unknown> = {}) {
  const r = decode(conversionReader, {
    routes_converted: 450,
    routes_total: 1500,
    batch_size: 50,
    batches_total: 10,
    next_batch: 2,
    staged_batch: null,
    unmappable: { count: 0, routes: [] },
    can_stage: true,
    ...extra,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return { ok: true, value: r.value };
}
const staged = (unmappable: readonly object[]) => ({
  ok: true,
  value: {
    change_set_id: "cs9",
    batch: 2,
    batches_total: 10,
    route_count: 150,
    spacecraft_count: 50,
    remaining_route_count: 900,
    unmappable,
  },
});
let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
  api.push.mockClear();
});
async function mounted() {
  wrapper = mount(LegacyConversionCallout, {
    props: { missionId: missionIdReader("m1") },
    global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
  });
  await flushPromises();
  return wrapper;
}
const button = (w: ReturnType<typeof mount>, label: string) =>
  w.findAll("button").find((b) => b.text() === label);

describe("legacy route conversion callout (ux U79)", () => {
  it("shows the progress and stages the next batch, opening the change set when none were skipped", async () => {
    api.read = read();
    api.staged = staged([]);
    const w = await mounted();
    expect(w.text()).toContain("450 of 1,500 routes converted.");
    await button(w, "Stage batch 2 of 10")?.trigger("click");
    await flushPromises();
    expect(api.push).toHaveBeenCalledWith({ name: "setup.changes" });
  });

  it("stays and says which routes were skipped, with Open change set", async () => {
    api.read = read();
    api.staged = staged([
      {
        routing_rule_id: "rr_1",
        reason: "transport_has_no_station",
        spacecraft: { id: "sc_389", name: "EARENDIL-389" },
      },
    ]);
    const w = await mounted();
    await button(w, "Stage batch 2 of 10")?.trigger("click");
    await flushPromises();
    expect(api.push).not.toHaveBeenCalled();
    expect(w.text()).toContain("Batch 2 is staged. 1 route wasn't converted: EARENDIL-389's");
    // ux: even one skipped route links its spacecraft's routing page.
    expect(w.findAll("li a").map((a) => a.text())).toEqual(["EARENDIL-389"]);
    expect(w.text()).toContain("Open change set");
  });

  it("offers no button to a viewer who can't stage, nor while a batch is staged", async () => {
    api.read = read({ can_stage: false });
    let w = await mounted();
    expect(w.text()).toContain("Mission admins and organization admins can stage the conversion.");
    expect(button(w, "Stage batch 2 of 10")).toBeUndefined();
    w.unmount();
    api.read = read({
      staged_batch: { change_set_id: "cs9", batch: 3, author: { id: "u1", name: "Mira K." } },
    });
    w = await mounted();
    expect(w.text()).toContain("Batch 3 is staged in Mira K.'s change set.");
    expect(button(w, "Stage batch 2 of 10")).toBeUndefined();
    expect(w.text()).toContain("Open change set");
  });
});

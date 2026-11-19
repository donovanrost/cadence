import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import ObservablePicker from "./editor/ObservablePicker.vue";
import PlaylistOrder from "./playlists/PlaylistOrder.vue";

/** #245: the points picker and the playlist order keep focus (A5) and say outcomes (B6). */
const api = vi.hoisted(() => ({
  points: { ok: true, value: { observables: [] } } as unknown,
  dashboards: { ok: true, value: { dashboards: [] } } as unknown,
}));
vi.mock("./editor/observables.ts", async (original) => ({
  ...(await original<typeof import("./editor/observables.ts")>()),
  searchObservables: () => Promise.resolve(api.points),
}));
vi.mock("./directory/api.ts", async (original) => ({
  ...(await original<typeof import("./directory/api.ts")>()),
  fetchDirectory: () => Promise.resolve(api.dashboards),
}));

afterEach(() => {
  document.body.innerHTML = "";
  vi.useRealTimers();
});
const live = (w: { find: (s: string) => { text: () => string } }) =>
  w.find('[aria-live="polite"]').text();
const typeSearch = async (
  w: { find: (s: string) => { setValue: (v: string) => Promise<void> } },
  text: string,
) => {
  await w.find('input[type="search"]').setValue(text);
  await flushPromises();
};

describe("points picker (ObservablePicker)", () => {
  const picker = (model: readonly string[] = []) =>
    mount(ObservablePicker, {
      props: {
        missionId: missionId("m1"),
        dashboardId: "d1",
        baseVersion: 1,
        fields: {} as never,
        limit: 4,
        modelValue: model,
        "onUpdate:modelValue": (v: readonly string[]) => void w.setProps({ modelValue: v }),
      },
      attachTo: document.body,
    });
  let w: ReturnType<typeof picker>;

  it("focuses the next result after a pick, then the one before", async () => {
    api.points = {
      ok: true,
      value: { observables: [{ id: "a.v" }, { id: "b.v" }, { id: "c.v" }] },
    };
    w = picker();
    await typeSearch(w, "vo");
    const picks = () => Array.from(document.querySelectorAll<HTMLElement>("[data-pick]"));
    picks()[1]?.focus();
    picks()[1]?.click();
    await flushPromises();
    expect(document.activeElement?.textContent).toContain("c.v");
    picks()[1]?.click();
    await flushPromises();
    expect(document.activeElement?.textContent).toContain("a.v");
  });

  it("says a search with no match, and a failed one", async () => {
    api.points = { ok: true, value: { observables: [] } };
    w = picker();
    await typeSearch(w, "zz");
    expect(live(w)).toBe("No points to add match “zz”.");
    api.points = { ok: false, error: { kind: "network", message: "offline" } };
    await typeSearch(w, "zzz");
    expect(live(w)).toBe("Couldn't search points. Change the search to try again.");
  });
});

describe("playlist order (PlaylistOrder)", () => {
  const items = [
    { id: "d1", name: "Power", archived: false },
    { id: "d2", name: "Thermal", archived: false },
    { id: "d3", name: "Comms", archived: false },
  ];
  const order = () => {
    const w = mount(PlaylistOrder, {
      props: {
        missionId: missionId("m1"),
        modelValue: items,
        "onUpdate:modelValue": (v: readonly (typeof items)[number][]) =>
          void w.setProps({ modelValue: v }),
      },
      attachTo: document.body,
    });
    return w;
  };
  const byLabel = (label: string) =>
    document.querySelector<HTMLElement>(`button[aria-label="${label}"]`);

  it("keeps focus on the moved row's arrow and announces where it went", async () => {
    vi.useFakeTimers();
    order();
    byLabel("Move Thermal up")?.focus();
    byLabel("Move Thermal up")?.click();
    await flushPromises();
    expect(document.activeElement).toBe(byLabel("Move Thermal up"));
    await vi.advanceTimersByTimeAsync(500); // past the kit announcer's delay
    expect(document.querySelector("[data-ap-announcer]")?.textContent).toBe(
      "Thermal moved to 1 of 3.",
    );
  });

  it("sends focus to the next row's Remove, else the one before", async () => {
    order();
    byLabel("Remove Thermal")?.focus();
    byLabel("Remove Thermal")?.click();
    await flushPromises();
    expect(document.activeElement).toBe(byLabel("Remove Comms"));
    byLabel("Remove Comms")?.click();
    await flushPromises();
    expect(document.activeElement).toBe(byLabel("Remove Power"));
  });

  it("says a search with no match", async () => {
    api.dashboards = { ok: true, value: { dashboards: [] } };
    const w = order();
    await typeSearch(w, "ops");
    expect(live(w)).toBe("No dashboards to add match “ops”.");
  });
});

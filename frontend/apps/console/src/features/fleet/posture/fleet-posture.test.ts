import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { computed, nextTick, ref } from "vue";
import FleetPosture from "./FleetPosture.vue";

const live = vi.hoisted(() => ({
  status: "ready" as "ready" | "loading",
  counts: { critical: 2, caution: 1, stale: 3 },
}));
const connection = ref<"online" | "offline">("online");
const tick = ref(0);
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useMissionScope: () => computed(() => ({ mission: { id: "m1" } })),
}));
vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useConnection: () => connection,
}));
vi.mock("../useFleet.ts", () => ({
  useFleet: () => ({
    state: computed(() => {
      void tick.value;
      return live.status === "ready"
        ? {
            status: "ready",
            value: {
              counts: { never_heard: 0, total: 99, ...live.counts },
              limits: { configured: true },
              observed_at: "2026-11-15T23:52:10Z",
            },
          }
        : { status: "loading" };
    }),
  }),
}));

const posture = () => mount(FleetPosture, { global: { stubs: { RouterLink: RouterLinkStub } } });

describe("top bar fleet posture (ux IA §Top bar)", () => {
  it("renders nothing until the fleet loads (never a placeholder nominal)", () => {
    live.status = "loading";
    expect(posture().html()).toBe("<!--v-if-->");
    live.status = "ready";
  });
  it("is hidden on phones and keeps the words in each link's name and title", () => {
    connection.value = "online";
    const w = posture();
    expect(w.get("[data-fleet-posture]").classes()).toContain("max-md:hidden");
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.attributes("aria-label"))).toEqual([
      "2 spacecraft critical",
      "1 spacecraft in caution",
      "3 spacecraft stale",
    ]);
    expect(links[0]?.attributes("title")).toBe("2 spacecraft critical");
    // Below 1600 (the test viewport) it's compact; the words stay in the name and title.
    expect(links[0]?.text()).toBe("2");
    expect(w.text()).not.toContain("UTC");
  });
  it("from 1600 shows the words beside the counts", () => {
    vi.stubGlobal("matchMedia", () => ({
      matches: true,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    }));
    const w = posture();
    expect(w.get("[data-fleet-posture]").attributes("data-compact")).toBeUndefined();
    expect(w.findAllComponents(RouterLinkStub)[0]?.text().replace(/\s+/g, "")).toBe("2crit");
    vi.unstubAllGlobals();
  });
  it("below 1600 is compact: counts only, the words in each name and title", () => {
    vi.stubGlobal("matchMedia", () => ({
      matches: false,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    }));
    const w = posture();
    expect(w.get("[data-fleet-posture]").attributes("data-compact")).toBe("true");
    const links = w.findAllComponents(RouterLinkStub);
    expect(links[0]?.text()).toBe("2");
    expect(links[0]?.attributes("aria-label")).toBe("2 spacecraft critical");
    vi.unstubAllGlobals();
  });
  it("keeps the counts when the live link drops, stale-tinted with 'as of'", async () => {
    const w = posture();
    connection.value = "offline";
    await nextTick();
    expect(w.text()).toContain("as of 23:52Z");
    expect(w.findAllComponents(RouterLinkStub)[0]?.classes()).toContain("text-stale-text");
    connection.value = "online";
  });
  it("flashes the crit chip once when crit rises, never on a fall", async () => {
    vi.useFakeTimers();
    const w = posture();
    const crit = () => w.findAllComponents(RouterLinkStub)[0];
    live.counts = { critical: 3, caution: 1, stale: 3 };
    tick.value++;
    await nextTick();
    expect(crit()?.classes()).toContain("motion-safe:animate-pulse");
    vi.advanceTimersByTime(2_000);
    await nextTick();
    expect(crit()?.classes()).not.toContain("motion-safe:animate-pulse");
    live.counts = { critical: 2, caution: 1, stale: 3 };
    tick.value++;
    await nextTick();
    expect(crit()?.classes()).not.toContain("motion-safe:animate-pulse");
    vi.useRealTimers();
  });
});

import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { computed, nextTick, ref } from "vue";
import FleetPosture from "./FleetPosture.vue";

type Counts = { critical: number; caution: number; stale: number; never_heard?: number };
type Live = { status: "ready" | "loading"; counts: Counts; telemetry: "ok" | "degraded" };
const live = vi.hoisted((): Live => ({
  status: "ready",
  counts: { critical: 2, caution: 1, stale: 3 },
  telemetry: "ok",
}));
const connection = ref<"online" | "offline">("online");
const tick = ref(0);
/** The shell's /counts posture (api-ops 64b16a90e); undefined until the read lands. */
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useFleetPosture: () =>
    computed(() => {
      void tick.value;
      return live.status === "ready"
        ? {
            nominal: 0,
            never_heard: 0,
            total: 99,
            ...live.counts,
            limits_configured: true,
            telemetry: live.telemetry,
            observed_at: "2026-11-15T23:52:10Z",
          }
        : undefined;
    }),
}));
vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useConnection: () => connection,
}));

const posture = () => mount(FleetPosture, { global: { stubs: { RouterLink: RouterLinkStub } } });

describe("top bar fleet posture (ux IA §Top bar)", () => {
  it("renders nothing until /counts has its posture (never a placeholder nominal)", () => {
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
  it("merges stale and never heard when telemetry history didn't answer (ux fb5e5ded0)", () => {
    live.telemetry = "degraded";
    live.counts = { critical: 2, caution: 1, stale: 3, never_heard: 6 };
    const w = posture();
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.props("to"))).toEqual([
      { name: "ops.alarms" },
      { name: "ops.alarms" },
      { name: "ops.fleet", query: { state: "stale,never_heard" } },
    ]);
    expect(links[2]?.attributes("aria-label")).toContain("9 spacecraft not heard recently.");
    expect(links[2]?.attributes("title")).toContain("couldn't read telemetry history");
    live.telemetry = "ok";
    live.counts = { critical: 2, caution: 1, stale: 3 };
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

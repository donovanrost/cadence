import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import { computed } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { stripDays, type PlanDay } from "./day-strip.ts";
import DayStrip from "./DayStrip.vue";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useMissionScope: () => computed(() => ({ mission: { id: "m-1" } })),
}));
/** Synthetic plan days (#1027's REST seed showed the shape), not captured from a server. */
vi.mock("./day-strip.ts", async (original) => {
  const real = await original<typeof import("./day-strip.ts")>();
  return {
    ...real,
    fetchPlanDays: (_m: string, from: string) => {
      const days: PlanDay[] = real.stripDays(new Date(`${from}T12:00:00Z`)).map((day, i) => ({
        day,
        plan: i === 0 ? { id: "p", version: 1, state: "reserved" } : null,
        sent_back: false,
        requirements_count: 10,
        booked_count: i === 0 ? 10 : null,
        unconfirmed_count: null,
        requested_count: i === 0 ? 10 : null,
        first_window_at: `${day}T00:00:00Z`,
      }));
      return Promise.resolve({ ok: true, value: { days } });
    },
  };
});

describe("K1 day strip names (#1027, WCAG 2.5.3)", () => {
  it("names each day starting with exactly what it shows, a day with windows included", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/", component: { template: "<div />" } }],
    });
    await router.push("/");
    const today = stripDays(new Date())[0] ?? "";
    const w = mount(DayStrip, { props: { day: today }, global: { plugins: [router] } });
    await flushPromises();
    const links = w.findAll("a");
    expect(links.length).toBe(7);
    for (const a of links) {
      // The label and the word are separate text, never run together ("Mon 30No plan").
      // What it shows, less the decorative mark (aria-hidden, outside the name by design).
      const copy = a.element.cloneNode(true) as HTMLElement;
      for (const mark of copy.querySelectorAll("[aria-hidden='true']")) mark.remove();
      const shown = (copy.textContent ?? "").replace(/\s+/g, " ").trim();
      expect(shown).toMatch(/^\w{3} \d{1,2} \S/);
      expect(a.attributes("aria-label")?.startsWith(shown)).toBe(true);
    }
    expect(links[1]?.attributes("aria-label")).toMatch(
      /^\w{3} \d{1,2} No plan, .+, first window 00:00Z$/,
    );
  });
});

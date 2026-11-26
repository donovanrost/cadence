import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import ActivityTab from "./ActivityTab.vue";
import { activityWire } from "./fixtures.test-support.ts";

/** #245: Activity's Older says when it fails (B6), and focus survives Older leaving (A5). */
const api = vi.hoisted(() => ({ pages: [] as unknown[] }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  fetchActivity: () => Promise.resolve(api.pages.shift()),
}));

afterEach(() => {
  document.body.innerHTML = "";
});
const older = () =>
  Array.from(document.querySelectorAll("button")).find((b) => b.textContent?.trim() === "Older");
const lastPage = {
  events: [
    {
      id: "e0",
      kind: "exported",
      at: "2026-11-12T20:00:00Z",
      actor: { id: "u1", name: "Mira K." },
      version: null,
    },
  ],
  next: null,
};

describe("Activity › Older", () => {
  it("says a failed Older in the live line, then focuses the first older event once Older is gone", async () => {
    api.pages.push(
      { ok: true, value: activityWire },
      { ok: false, error: { kind: "network", message: "offline" } },
      { ok: true, value: lastPage },
    );
    mount(ActivityTab, {
      props: { settingsKey: { missionId: missionId("m1"), dashboardId: "d1" } },
      attachTo: document.body,
    });
    await flushPromises();
    // B6: a failed Older after the person asked for it is an alert, in a line that's always there.
    const live = () => document.querySelector('[role="alert"]')?.textContent?.trim();
    expect(live()).toBe("");

    older()?.focus();
    older()?.click();
    await flushPromises();
    expect(live()).toBe("Couldn't load older activity. Try Older again.");
    expect(document.activeElement).toBe(older());

    older()?.click();
    await flushPromises();
    expect(older()).toBeUndefined();
    expect(document.activeElement?.getAttribute("data-activity")).toBe("e0");
  });
});

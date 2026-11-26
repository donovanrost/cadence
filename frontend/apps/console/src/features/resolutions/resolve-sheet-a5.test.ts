import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import ResolveBookingActions from "./ResolveBookingActions.vue";

/**
 * #244 (A5): the parent's refresh removes this pass's row and the sheet with it, so a successful
 * resolve shows its outcome in the sheet and asks for that refresh only when the sheet closes.
 */
afterEach(() => vi.unstubAllGlobals());

describe("ResolveBookingActions' sheet", () => {
  it("keeps the outcome on screen and emits resolved only on close", async () => {
    const fetch = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            data: { outcome: "provider_answered", provider_answer: "booked", resolution: null },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    );
    vi.stubGlobal("fetch", fetch);
    const w = mount(ResolveBookingActions, {
      props: {
        missionId: missionId("m-1"),
        planId: "plan_1",
        pass: {
          snapshot_id: "s1",
          provider: { name: "Northlight" },
          text: "EARENDIL-1 · KIR · 03:00Z",
        },
      },
      attachTo: document.body,
    });
    try {
      await w
        .findAll("button")
        .find((b) => b.text() === "Mark not booked")
        ?.trigger("click");
      await flushPromises();
      const note = document.querySelector<HTMLTextAreaElement>("textarea");
      if (!note) throw new Error("no note field");
      note.value = "Called the ops desk.";
      note.dispatchEvent(new Event("input"));
      document.querySelector("form")?.dispatchEvent(new Event("submit", { cancelable: true }));
      await flushPromises();
      expect(fetch).toHaveBeenCalledOnce();
      expect(document.body.textContent).toContain("Northlight answered: booked.");
      // The primary that had focus is gone, so the outcome takes it and is read (ux on #590).
      expect(document.activeElement?.textContent).toContain("Northlight answered: booked.");
      expect(w.emitted("resolved")).toBeUndefined();
      const close = [...document.querySelectorAll("button")].find((b) =>
        /^(Done|Close)$/.test(b.textContent?.trim() ?? ""),
      );
      close?.click();
      await flushPromises();
      expect(w.emitted("resolved")).toHaveLength(1);
    } finally {
      w.unmount();
    }
  });
});

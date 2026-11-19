import { flushPromises, mount } from "@vue/test-utils";
import { computed } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { groupOf } from "../groups/fixtures.ts";
import AbortPanel from "./AbortPanel.vue";

vi.mock("@/shell/index.ts", async (original) => ({
  ...(await original<typeof import("@/shell/index.ts")>()),
  useMissionScope: () => computed(() => ({ mission: { id: missionId("m-1"), name: "EARENDIL" } })),
}));
afterEach(() => {
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

/** a11y A1/A5 for Abort's inline confirm: focus never falls to <body> when its button goes. */
describe("Abort remaining focus", () => {
  it("opens on 'Why abort' (ux §7: the field first), and Keep running returns to 'Abort remaining'", async () => {
    const w = mount(AbortPanel, { props: { group: groupOf() }, attachTo: document.body });
    await w.get("button[aria-controls]").trigger("click");
    await flushPromises();
    expect(document.activeElement?.tagName).toBe("TEXTAREA");
    await w
      .findAll("button")
      .find((b) => b.text() === "Keep running")
      ?.trigger("click");
    await flushPromises();
    expect(document.activeElement?.textContent?.trim()).toBe("Abort remaining");
    w.unmount();
  });
});

// a11y B6 (#243): a refused or unclear abort is an alert (its callout is caution or crit).
describe("Abort remaining outcome", () => {
  it("announces a failed abort as an alert", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: { code: "internal", message: "boom" } }), {
          status: 500,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
    const w = mount(AbortPanel, { props: { group: groupOf() }, attachTo: document.body });
    await w.get("button[aria-controls]").trigger("click");
    await flushPromises();
    await w.get("textarea").setValue("wrong target");
    await w
      .findAll("button")
      .find((b) => b.text() === "Abort remaining uplinks")
      ?.trigger("click");
    await flushPromises();
    const said = w.findAll('[role="alert"]').map((e) => e.text());
    expect(said.some((t) => t.includes("abort"))).toBe(true);
    w.unmount();
  });
});

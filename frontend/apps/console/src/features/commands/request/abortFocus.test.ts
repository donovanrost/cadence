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

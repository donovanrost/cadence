import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId, spacecraftId } from "@/api/index.ts";
import AddPointSearch from "./AddPointSearch.vue";

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

/** a11y A5: closing the point search returns focus to '+ Add point', never <body>. */
describe("Add point focus", () => {
  it("opens into the field and Cancel returns to '+ Add point'", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify({ data: { points: [] } }), { status: 200 })),
    );
    const w = mount(AddPointSearch, {
      props: {
        missionId: missionId("m-1"),
        spacecraftId: spacecraftId("sc-1"),
        exclude: [],
        full: false,
      },
      attachTo: document.body,
    });
    await w.get("button").trigger("click");
    await nextTick();
    await nextTick();
    expect(document.activeElement?.tagName).toBe("INPUT");
    const cancel = w.findAll("button").find((b) => b.text() === "Cancel");
    await cancel?.trigger("click");
    await nextTick();
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("+ Add point");
    w.unmount();
  });
});

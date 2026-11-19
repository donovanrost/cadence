import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import IdCell from "./IdCell.vue";

/** a11y B6 (#243): copying says how it went; a failed copy is an alert, a copy a status. */
describe("IdCell copy", () => {
  afterEach(() => vi.unstubAllGlobals());
  const copyWith = async (writeText: () => Promise<void>) => {
    vi.stubGlobal("navigator", { clipboard: { writeText } });
    const w = mount(IdCell, {
      props: { id: "reservation-0123456789abcdef", label: "reservation id" },
    });
    await w.get("button").trigger("click");
    await flushPromises();
    return w;
  };

  it("a failed copy is an alert", async () => {
    const w = await copyWith(() => Promise.reject(new Error("denied")));
    expect(w.get('[role="alert"]').text()).toBe("Couldn't copy.");
    expect(w.get('[role="status"]').text()).toBe("");
  });

  it("a copy is a status", async () => {
    const w = await copyWith(() => Promise.resolve());
    expect(w.get('[role="status"]').text()).toBe("Copied.");
    expect(w.get('[role="alert"]').text()).toBe("");
  });
});

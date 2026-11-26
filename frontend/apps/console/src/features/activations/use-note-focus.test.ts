import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { defineComponent, h, nextTick, ref } from "vue";
import { useNoteFocus } from "./useNoteFocus.ts";

/**
 * #244 (A5, B4; ux on #584): the Decide panel outlives decided() and leaves only with the refetch,
 * so focus moves to the note then, and only if it was lost.
 */
function harness() {
  const settled = ref(false);
  const decided = ref(false);
  let arm: () => Promise<void> = async () => undefined;
  const C = defineComponent(() => {
    const box = ref<HTMLElement | null>(null);
    arm = useNoteFocus(box, () => settled.value);
    return () =>
      h("div", [
        decided.value ? h("div", { ref: box, tabindex: -1, "data-note": "" }, "Approved.") : null,
        settled.value ? null : h("button", { "data-approve": "" }, "Approve"),
      ]);
  });
  const w = mount(C, { attachTo: document.body });
  return { w, settled, decided, arm: () => arm() };
}

describe("useNoteFocus", () => {
  it("waits while the panel still holds focus, then moves to the note when the refetch removes it", async () => {
    const { w, settled, decided, arm } = harness();
    try {
      w.get<HTMLButtonElement>("[data-approve]").element.focus();
      decided.value = true;
      await arm();
      // decided()'s nextTick: Approve is still there and focused, so nothing moves yet.
      expect(document.activeElement).toBe(w.get("[data-approve]").element);
      settled.value = true;
      await nextTick();
      await nextTick();
      expect(document.activeElement).toBe(w.get("[data-note]").element);
    } finally {
      w.unmount();
    }
  });

  it("leaves focus where the person moved it", async () => {
    const elsewhere = document.createElement("button");
    document.body.append(elsewhere);
    const { w, settled, decided, arm } = harness();
    try {
      decided.value = true;
      await arm();
      elsewhere.focus();
      settled.value = true;
      await nextTick();
      await nextTick();
      expect(document.activeElement).toBe(elsewhere);
    } finally {
      w.unmount();
      elsewhere.remove();
    }
  });
});

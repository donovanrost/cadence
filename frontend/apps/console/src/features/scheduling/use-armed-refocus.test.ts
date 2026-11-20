import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { defineComponent, h, nextTick, ref } from "vue";
import { useArmedRefocus } from "./useArmedRefocus.ts";

/** #244 (A5, B4; fe-ops on #590): only the person's own act arms a focus move. */
function harness() {
  const count = ref(2);
  let arm: () => void = () => undefined;
  const C = defineComponent(() => {
    const box = ref<HTMLElement | null>(null);
    arm = useArmedRefocus(
      () => count.value,
      () => box.value,
    ).arm;
    return () => h("div", { ref: box, tabindex: -1, "data-box": "" }, `${count.value} left`);
  });
  const w = mount(C, { attachTo: document.body });
  return { w, count, arm: () => arm() };
}
const settle = async () => {
  await nextTick();
  await nextTick();
};

describe("useArmedRefocus", () => {
  it("leaves focus on <body> alone when a background refetch changes the list", async () => {
    const { w, count } = harness();
    try {
      const active = document.activeElement;
      if (active instanceof HTMLElement) active.blur();
      count.value = 1;
      await settle();
      expect(document.activeElement).toBe(document.body);
    } finally {
      w.unmount();
    }
  });

  it("moves lost focus to the target after the person's own act", async () => {
    const { w, count, arm } = harness();
    try {
      arm();
      count.value = 1;
      await settle();
      expect(document.activeElement).toBe(w.get("[data-box]").element);
    } finally {
      w.unmount();
    }
  });
});

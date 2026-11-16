import { mount } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref } from "vue";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { useInPlaceSwap } from "./in-place-swap.ts";

/** Edit swaps for an editor whose field is there at once, or only once `ready` (a schema read). */
const Host = defineComponent({
  props: { late: { type: Boolean, default: false } },
  setup(props) {
    const root = ref<HTMLElement | null>(null);
    const swap = useInPlaceSwap(root);
    const ready = ref(!props.late);
    return { root, swap, ready };
  },
  render() {
    return h("main", { ref: "root" }, [
      h("h1", "Page"),
      this.swap.open.value
        ? h("div", { "data-swap-editor": "" }, this.ready ? [h("input", { id: "field" })] : [])
        : h("button", { "data-swap-opener": "", id: "edit" }, "Edit"),
    ]);
  },
});

const active = () => document.activeElement?.id ?? document.activeElement?.tagName;

afterEach(() => {
  document.body.innerHTML = "";
});

describe("useInPlaceSwap", () => {
  it("focuses the editor's first field on show, and the opener again on hide", async () => {
    const w = mount(Host, { attachTo: document.body });
    await w.vm.swap.show();
    expect(active()).toBe("field");
    await w.vm.swap.hide();
    expect(active()).toBe("edit");
  });

  it("holds focus on the editor until a late field renders, then moves to it", async () => {
    const w = mount(Host, { props: { late: true }, attachTo: document.body });
    document.querySelector<HTMLElement>("#edit")?.focus();
    await w.vm.swap.show();
    expect(document.activeElement?.hasAttribute("data-swap-editor")).toBe(true);
    w.vm.ready = true;
    await nextTick();
    await Promise.resolve();
    expect(active()).toBe("field");
  });
});

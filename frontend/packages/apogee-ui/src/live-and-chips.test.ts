import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { defineComponent, h, nextTick, ref } from "vue";
import ApChip from "./ApChip.vue";
import ApEmptyState from "./ApEmptyState.vue";

afterEach(() => {
  document.body.innerHTML = "";
});

/** Chips as screens lay them out: a search field, then one removable chip per id. */
function chipHost(initial: readonly string[], options: { field?: boolean; inLi?: boolean } = {}) {
  const ids = ref([...initial]);
  const Host = defineComponent({
    setup() {
      const chip = (id: string) =>
        h(
          ApChip,
          {
            key: id,
            removable: true,
            removeLabel: `Remove ${id}`,
            onRemove: () => (ids.value = ids.value.filter((x) => x !== id)),
          },
          () => id,
        );
      return () =>
        h("main", [
          h("h1", "Telemetry"),
          h("div", [
            options.field === false ? null : h("input", { "aria-label": "Search points" }),
            options.inLi
              ? h(
                  "ul",
                  ids.value.map((id) => h("li", { key: id }, [chip(id)])),
                )
              : h("div", ids.value.map(chip)),
          ]),
        ]);
    },
  });
  const wrapper = mount(Host, { attachTo: document.body });
  const button = (id: string) => wrapper.get<HTMLButtonElement>(`[aria-label="Remove ${id}"]`);
  return { wrapper, button };
}

const focusedLabel = () => document.activeElement?.getAttribute("aria-label");

describe("ApChip focus handoff (a11y A5)", () => {
  it("moves focus to the next chip's × when a focused chip leaves", async () => {
    const { button } = chipHost(["A", "B", "C"]);
    button("B").element.focus();
    await button("B").trigger("click");
    await nextTick();
    expect(focusedLabel()).toBe("Remove C");
  });

  it("takes the previous chip's × after the last one, also when each chip sits in an <li>", async () => {
    const { button } = chipHost(["A", "B"], { inLi: true });
    button("B").element.focus();
    await button("B").trigger("click");
    await nextTick();
    expect(focusedLabel()).toBe("Remove A");
  });

  it("falls back to the group's field once no chip is left", async () => {
    const { button } = chipHost(["A"]);
    button("A").element.focus();
    await button("A").trigger("click");
    await nextTick();
    expect(focusedLabel()).toBe("Search points");
  });

  it("falls back to the page h1, never <body>, with no field nearby", async () => {
    const { button } = chipHost(["A"], { field: false });
    button("A").element.focus();
    await button("A").trigger("click");
    await nextTick();
    expect(document.activeElement?.tagName).toBe("H1");
  });

  it("leaves focus alone when the × wasn't focused", async () => {
    const { wrapper, button } = chipHost(["A", "B"]);
    const field = wrapper.get<HTMLInputElement>("input").element;
    field.focus();
    await button("A").trigger("click");
    await nextTick();
    expect(document.activeElement).toBe(field);
  });
});

describe("ApEmptyState", () => {
  it("puts its words in a polite status region and its actions outside it", () => {
    const wrapper = mount(ApEmptyState, {
      props: { headline: "No points match", sentence: "Try another name." },
      slots: { default: () => h("button", "Clear search") },
    });
    const status = wrapper.get('[role="status"]');
    expect(status.text()).toContain("No points match");
    expect(status.text()).toContain("Try another name.");
    expect(status.find("button").exists()).toBe(false);
  });
});

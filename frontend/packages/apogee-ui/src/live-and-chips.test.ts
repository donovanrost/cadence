import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { defineComponent, h, nextTick, ref } from "vue";
import ApChip from "./ApChip.vue";
import ApEmptyState from "./ApEmptyState.vue";
import { ANNOUNCE_DELAY_MS, announcePolite } from "./lib/announce.ts";

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

describe("ApEmptyState announce (B6)", () => {
  const announcer = () => document.querySelector("[data-ap-announcer]");

  it("reads a search's empty result through the page's one live region, after a beat", async () => {
    vi.useFakeTimers();
    try {
      const wrapper = mount(ApEmptyState, {
        props: { headline: "No points match", sentence: "Try another name.", announce: true },
        slots: { default: () => h("button", "Clear search") },
      });
      expect(wrapper.find('[role="status"]').exists()).toBe(false);
      expect(announcer()?.getAttribute("role")).toBe("status");
      expect(announcer()?.textContent).toBe("");
      vi.advanceTimersByTime(ANNOUNCE_DELAY_MS);
      expect(announcer()?.textContent).toBe("No points match Try another name.");

      await wrapper.setProps({ headline: "No spacecraft match" });
      expect(announcer()?.textContent).toBe("");
      vi.advanceTimersByTime(ANNOUNCE_DELAY_MS);
      expect(announcer()?.textContent).toBe("No spacecraft match Try another name.");
    } finally {
      vi.useRealTimers();
    }
  });

  it("says nothing without announce: an empty list on first load is read with the page", () => {
    vi.useFakeTimers();
    try {
      mount(ApEmptyState, { props: { headline: "No alarms" } });
      vi.advanceTimersByTime(ANNOUNCE_DELAY_MS);
      expect(announcer()?.textContent ?? "").toBe("");
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("announcePolite inside an open sheet", () => {
  it("speaks from a region inside the topmost open dialog, which a modal doesn't hide", () => {
    vi.useFakeTimers();
    try {
      document.body.innerHTML = `<main><h1>Now</h1></main><dialog open aria-label="Search"><input></dialog>`;
      announcePolite("No matches");
      vi.advanceTimersByTime(ANNOUNCE_DELAY_MS);
      const region = document.querySelector("dialog [data-ap-announcer]");
      expect(region?.textContent).toBe("No matches");
      expect(document.querySelectorAll("[data-ap-announcer]")).toHaveLength(1);

      document.querySelector("dialog")?.remove();
      announcePolite("No points match");
      vi.advanceTimersByTime(ANNOUNCE_DELAY_MS);
      expect(document.querySelector("body > [data-ap-announcer]")?.textContent).toBe(
        "No points match",
      );
    } finally {
      vi.useRealTimers();
    }
  });
});

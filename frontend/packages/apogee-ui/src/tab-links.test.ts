import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import ApTabLinks from "./ApTabLinks.vue";

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: "/:tab?", component: { render: () => null } }],
});
const links = ["overview", "catalog", "communications", "changes"].map((key) => ({
  key,
  label: key,
  to: `/${key}`,
}));
const rect = (left: number, right: number) => new DOMRect(left, 0, right - left, 36);

afterEach(() => vi.restoreAllMocks());

/** ux U94: on a narrow screen the strip scrolls sideways, keeping the active link in view. */
describe("ApTabLinks on a narrow screen", () => {
  it("scrolls only the strip to the active link, never the page (lead)", async () => {
    const pageScroll = vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(
      function (this: HTMLElement) {
        if (this.tagName === "NAV") return rect(0, 390);
        if (this.getAttribute("aria-current") === "page") return rect(420, 520);
        return rect(0, 100);
      },
    );
    const w = mount(ApTabLinks, {
      props: { links, active: "changes", label: "Sections" },
      global: { plugins: [router] },
      attachTo: document.body,
    });
    await flushPromises();
    expect(w.find("nav").element.scrollLeft).toBe(130);
    expect(pageScroll).not.toHaveBeenCalled();
    w.unmount();
  });

  it("keeps each link on one line", () => {
    const w = mount(ApTabLinks, {
      props: { links, active: "overview", label: "Sections" },
      global: { plugins: [router] },
    });
    expect(w.find("nav").classes()).toContain("overflow-x-auto");
    expect(w.findAll("a").every((a) => a.classes().includes("whitespace-nowrap"))).toBe(true);
  });

  it("fades the edge that has more links behind it, and only while it does (ux #349)", async () => {
    const w = mount(ApTabLinks, {
      props: { links, active: "overview", label: "Sections" },
      global: { plugins: [router] },
    });
    const nav = w.find("nav");
    const size = (scrollLeft: number) => {
      Object.defineProperty(nav.element, "scrollWidth", { configurable: true, value: 600 });
      Object.defineProperty(nav.element, "clientWidth", { configurable: true, value: 390 });
      nav.element.scrollLeft = scrollLeft;
    };
    const fades = () => nav.classes().filter((c) => c.startsWith("[mask-image"));
    size(0);
    await nav.trigger("scroll");
    expect(fades()).toEqual([
      "[mask-image:linear-gradient(to_right,#000_calc(100%-24px),transparent)]",
    ]);
    size(100);
    await nav.trigger("scroll");
    expect(fades()[0]).toContain("transparent,#000_24px,#000_calc(100%-24px),transparent");
    size(210);
    await nav.trigger("scroll");
    expect(fades()).toEqual(["[mask-image:linear-gradient(to_right,transparent,#000_24px)]"]);
    Object.defineProperty(nav.element, "scrollWidth", { configurable: true, value: 390 });
    nav.element.scrollLeft = 0;
    await nav.trigger("scroll");
    expect(fades()).toEqual([]);
  });
});

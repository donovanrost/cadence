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
});

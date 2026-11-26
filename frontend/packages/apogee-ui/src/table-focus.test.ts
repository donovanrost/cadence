import { mount } from "@vue/test-utils";
import { h, nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import ApTable from "./ApTable.vue";

/** #189: Tab on a link cut off by a table that scrolls sideways at 390 brings it into view. */
type Row = Readonly<{ id: string; name: string; file: string }>;
const rows: Row[] = [{ id: "r1", name: "rev 1", file: "demo_spacecraft.yaml" }];
const columns = [
  { key: "name", label: "Revision" },
  { key: "label", label: "Label" },
  { key: "file", label: "Source file" },
];

/** The wrapper is 356 wide; the file link sits at 346..515, the Name link at 0..60. */
function mountTable(scrollBox: boolean) {
  vi.spyOn(HTMLElement.prototype, "scrollWidth", "get").mockReturnValue(700);
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(356);
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(120);
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(
    function (this: HTMLElement) {
      if (this.getAttribute("role") === "region") return new DOMRect(0, 0, 356, 400);
      if (this.textContent === "demo_spacecraft.yaml") return new DOMRect(346, 0, 169, 15);
      return new DOMRect(0, 0, 60, 15);
    },
  );
  return mount(ApTable<Row>, {
    attachTo: document.body,
    props: { columns, rows, rowKey: (r: Row) => r.id, caption: "Catalog revisions", scrollBox },
    slots: {
      "cell-name": ({ row }: { row: Row }) => h("a", { href: "#rev" }, row.name),
      "cell-file": ({ row }: { row: Row }) => h("a", { href: "#file" }, row.file),
    },
  });
}

/** Focuses the attached element a selector names, as Tab would. */
function focus(selector: string): HTMLElement {
  const el = document.querySelector(selector);
  if (!(el instanceof HTMLElement)) throw Error(`No element at ${selector}`);
  el.focus();
  return el;
}

afterEach(() => {
  vi.restoreAllMocks();
  document.body.replaceChildren();
});

describe("ApTable focus in a table that scrolls sideways", () => {
  it("scrolls the table, not the page, to the focused link", async () => {
    const page = vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    const w = mountTable(false);
    await nextTick();
    const region = w.get("[role=region]").element;
    focus("a[href='#file']");
    expect(region.scrollLeft).toBe(515 - 356);
    expect(page).not.toHaveBeenCalled();
    w.unmount();
  });

  it("in a scrollBox, never scrolls for the sticky Name column", async () => {
    const w = mountTable(true);
    await nextTick();
    const region = w.get("[role=region]").element;
    region.scrollLeft = 200;
    focus("a[href='#rev']");
    expect(region.scrollLeft).toBe(200);
    w.unmount();
  });

  it("ignores focus on the region itself", async () => {
    const w = mountTable(false);
    await nextTick();
    const region = focus("[role=region]");
    expect(region.scrollLeft).toBe(0);
    w.unmount();
  });
});

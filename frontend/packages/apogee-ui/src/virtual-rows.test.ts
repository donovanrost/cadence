import { mount } from "@vue/test-utils";
import { h } from "vue";
import { describe, expect, it } from "vite-plus/test";
import ApTable from "./ApTable.vue";
import { rowWindow } from "./lib/virtualRows.ts";

/** ApTable's opt-in windowing (lead's kit, 11-15). */
describe("rowWindow", () => {
  const base = { count: 1000, rowHeight: 40, overscan: 5, viewport: 400, offset: 40 };
  it("at the top renders the first screen plus overscan", () => {
    expect(rowWindow({ ...base, scrollTop: 0 })).toEqual({
      start: 0,
      end: 16,
      before: 0,
      after: 984 * 40,
    });
  });
  it("in the middle renders the rows in view plus overscan either side", () => {
    const w = rowWindow({ ...base, scrollTop: 20_040 });
    expect(w.start).toBe(495);
    expect(w.end).toBe(516);
    expect(w.before).toBe(495 * 40);
    expect(w.after).toBe((1000 - 516) * 40);
  });
  it("at the bottom ends at the last row", () => {
    const w = rowWindow({ ...base, scrollTop: 1000 * 40 + 40 - 400 });
    expect(w.end).toBe(1000);
    expect(w.after).toBe(0);
  });
  it("keeps a focused row and its neighbours rendered, wherever the scroll is", () => {
    const w = rowWindow({ ...base, scrollTop: 0, focused: 15 });
    expect(w.end).toBe(21);
    const far = rowWindow({ ...base, scrollTop: 20_040, focused: 3 });
    expect(far.start).toBe(0);
  });
  it("handles an empty table", () => {
    expect(rowWindow({ ...base, count: 0, scrollTop: 0 })).toEqual({
      start: 0,
      end: 0,
      before: 0,
      after: 0,
    });
  });
});

type Row = Readonly<{ id: string; name: string }>;
const rows: Row[] = Array.from({ length: 1000 }, (_, i) => ({ id: `r${i}`, name: `Row ${i}` }));
const frame = () => new Promise((r) => setTimeout(r, 40));

/** A scroller with a known height; the body sits 40 px (the header) below its top. */
function scrollerOf(height: number) {
  const el = document.createElement("div");
  Object.defineProperty(el, "clientHeight", { configurable: true, get: () => height });
  el.getBoundingClientRect = () => new DOMRect(0, 0, 800, height);
  document.body.appendChild(el);
  return el;
}

function mountTable(scroller: HTMLElement) {
  const w = mount(ApTable<Row>, {
    attachTo: scroller,
    props: {
      columns: [{ key: "name", label: "Name" }],
      rows,
      rowKey: (r: Row) => r.id,
      virtual: { rowHeight: 40, overscan: 5 },
      scroller,
    },
    slots: { "cell-name": ({ row }: { row: Row }) => h("a", { href: `#${row.id}` }, row.name) },
  });
  const body = w.find("tbody").element;
  body.getBoundingClientRect = () => new DOMRect(0, 40 - scroller.scrollTop, 800, 0);
  return w;
}
const indexes = (w: ReturnType<typeof mountTable>) =>
  w.findAll("tbody tr[aria-rowindex]").map((r) => Number(r.attributes("aria-rowindex")));

describe("ApTable virtual", () => {
  it("never wraps a virtual row's cells (every row must be rowHeight tall)", () => {
    const scroller = scrollerOf(400);
    const virtual = mountTable(scroller);
    expect(virtual.find("tbody tr[aria-rowindex] td").classes()).toContain("whitespace-nowrap");
    virtual.unmount();
    scroller.remove();
    const plain = mount(ApTable<Row>, {
      props: {
        columns: [{ key: "name", label: "Name" }],
        rows: rows.slice(0, 3),
        rowKey: (r: Row) => r.id,
      },
    });
    expect(plain.find("tbody td").classes()).not.toContain("whitespace-nowrap");
    plain.unmount();
  });

  it("is off by default: every row, no aria counts", () => {
    const w = mount(ApTable<Row>, {
      props: {
        columns: [{ key: "name", label: "Name" }],
        rows: rows.slice(0, 50),
        rowKey: (r: Row) => r.id,
      },
    });
    expect(w.findAll("tbody tr")).toHaveLength(50);
    expect(w.find("table").attributes("aria-rowcount")).toBeUndefined();
    w.unmount();
  });

  it("before the first measurement renders only the first 50 rows, not all of them", () => {
    const scroller = scrollerOf(400);
    const w = mountTable(scroller);
    expect(indexes(w).length).toBeLessThanOrEqual(50);
    w.unmount();
    scroller.remove();
  });

  it("renders a window with aria-rowcount and aria-rowindex, and follows the scroll", async () => {
    const scroller = scrollerOf(400);
    const w = mountTable(scroller);
    await frame();
    scroller.dispatchEvent(new Event("scroll"));
    await frame();
    expect(w.find("table").attributes("aria-rowcount")).toBe("1001");
    expect(indexes(w)[0]).toBe(2);
    expect(indexes(w)).toHaveLength(16);
    scroller.scrollTop = 20_040;
    scroller.dispatchEvent(new Event("scroll"));
    await frame();
    expect(indexes(w)[0]).toBe(495 + 2);
    expect(w.findAll("tbody tr[aria-hidden]")).toHaveLength(2);
    w.unmount();
    scroller.remove();
  });

  it("keeps focus through a re-window, and renders the next row after the focused last one", async () => {
    const scroller = scrollerOf(400);
    const w = mountTable(scroller);
    scroller.dispatchEvent(new Event("scroll"));
    await frame();
    const last = w.findAll("tbody tr[aria-rowindex]").at(-1);
    if (!last) throw new Error("no rows");
    const link = last.find("a").element;
    link.focus();
    link.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await frame();
    expect(document.activeElement).toBe(link);
    const lastIndex = Number(last.attributes("aria-rowindex"));
    expect(indexes(w)).toContain(lastIndex + 1);
    w.unmount();
    scroller.remove();
  });

  it("without a scroller prop, finds the scrolling ancestor above the table's own wrapper", async () => {
    const pane = scrollerOf(400);
    pane.style.overflowY = "auto";
    const w = mount(ApTable<Row>, {
      attachTo: pane,
      props: {
        columns: [{ key: "name", label: "Name" }],
        rows,
        rowKey: (r: Row) => r.id,
        virtual: { rowHeight: 40, overscan: 5 },
      },
    });
    w.find("tbody").element.getBoundingClientRect = () =>
      new DOMRect(0, 40 - pane.scrollTop, 800, 0);
    // In a browser the wrapper's overflow-x: auto makes overflow-y compute auto; say so here, and
    // re-run the scroller search (a new options object re-attaches).
    if (!(w.element instanceof HTMLElement)) throw new Error("wrapper");
    w.element.style.overflowY = "auto";
    await w.setProps({ virtual: { rowHeight: 40, overscan: 5 } });
    pane.dispatchEvent(new Event("scroll"));
    await frame();
    // The wrapper must not be taken as the scroller (its 0 px height would render ~6 rows).
    expect(indexes(w)).toHaveLength(16);
    w.unmount();
    pane.remove();
  });

  it("re-windows when the scroller changes", async () => {
    const small = scrollerOf(400);
    const w = mountTable(small);
    small.dispatchEvent(new Event("scroll"));
    await frame();
    expect(indexes(w)).toHaveLength(16);
    const tall = scrollerOf(800);
    await w.setProps({ scroller: tall });
    w.find("tbody").element.getBoundingClientRect = () => new DOMRect(0, 40, 800, 0);
    tall.dispatchEvent(new Event("scroll"));
    await frame();
    expect(indexes(w)).toHaveLength(26);
    w.unmount();
    small.remove();
    tall.remove();
  });
});

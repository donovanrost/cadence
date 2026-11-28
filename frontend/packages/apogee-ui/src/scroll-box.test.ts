import { mount } from "@vue/test-utils";
import { h, nextTick } from "vue";
import { describe, expect, it } from "vite-plus/test";
import ApTable from "./ApTable.vue";

/** ApTable scrollBox (OpsLists.md › Fleet, option A; lead's kit review). */
type Row = Readonly<{ id: string; name: string; state: "crit" | null }>;
const rows: Row[] = Array.from({ length: 1000 }, (_, i) => ({
  id: `r${i}`,
  name: `Row ${i}`,
  state: i === 0 ? "crit" : null,
}));
const columns = [
  { key: "name", label: "Name" },
  { key: "state", label: "State" },
];
const frame = () => new Promise((r) => setTimeout(r, 40));

function mountBox(scrollBox: boolean, virtual = true) {
  return mount(ApTable<Row>, {
    attachTo: document.body,
    props: {
      columns,
      rows,
      rowKey: (r: Row) => r.id,
      caption: "Fleet table",
      rowState: (r: Row) => r.state,
      virtual: virtual ? { rowHeight: 40, overscan: 5 } : undefined,
      scrollBox,
    },
    slots: { "cell-name": ({ row }: { row: Row }) => h("a", { href: `#${row.id}` }, row.name) },
  });
}

describe("ApTable scrollBox", () => {
  it("is a focusable region named by the caption that scrolls both ways", () => {
    const w = mountBox(true);
    const box = w.find("div");
    expect(box.attributes()).toMatchObject({
      role: "region",
      "aria-label": "Fleet table",
      tabindex: "0",
    });
    expect(box.classes()).toEqual(expect.arrayContaining(["h-full", "overflow-auto"]));
    w.unmount();
  });

  it("keeps the heading row at the top and the Name column at the left, opaque", () => {
    const w = mountBox(true);
    const [corner, head] = w.findAll("th");
    expect(corner?.classes()).toEqual(
      expect.arrayContaining(["sticky", "top-0", "left-0", "bg-panel"]),
    );
    expect(head?.classes()).toEqual(expect.arrayContaining(["sticky", "top-0", "bg-panel"]));
    expect(head?.classes()).not.toContain("left-0");
    const [critRow, calmRow] = w.findAll("tbody tr[aria-rowindex]");
    const [critName, critState] = critRow?.findAll("td") ?? [];
    // The crit wash stays on the sticky Name cell as a layer over the panel fill.
    expect(critName?.classes()).toEqual(expect.arrayContaining(["sticky", "left-0", "bg-panel"]));
    expect(critName?.classes().some((c) => c.includes("--apogee-wash-crit"))).toBe(true);
    expect(critState?.classes()).not.toContain("sticky");
    expect(
      calmRow
        ?.find("td")
        .classes()
        .some((c) => c.includes("wash")),
    ).toBe(false);
    w.unmount();
  });

  it("is off by default: nothing sticky, the wrapper only scrolls sideways", () => {
    const w = mountBox(false);
    expect(w.find("div").classes()).toEqual(["relative", "overflow-x-auto"]);
    expect(w.findAll(".sticky")).toHaveLength(0);
    w.unmount();
  });

  it("windows against its own box", async () => {
    const w = mountBox(true);
    const box = w.find("div").element;
    Object.defineProperty(box, "clientHeight", { configurable: true, get: () => 400 });
    box.getBoundingClientRect = () => new DOMRect(0, 0, 800, 400);
    const body = w.find("tbody").element;
    body.getBoundingClientRect = () => new DOMRect(0, 40 - box.scrollTop, 800, 0);
    box.scrollTop = 20_040;
    box.dispatchEvent(new Event("scroll"));
    await frame();
    await nextTick();
    const first = Number(w.find("tbody tr[aria-rowindex]").attributes("aria-rowindex"));
    expect(first).toBe(495 + 2);
    w.unmount();
  });
});

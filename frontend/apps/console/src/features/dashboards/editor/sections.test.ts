import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import EditSectionHead from "./EditSectionHead.vue";

const section = {
  id: "dash_section_power",
  title: "Power",
  description: "Batteries and buses.",
  collapsed_by_default: false,
};
const head = (count: number, first = false, last = false) =>
  mount(EditSectionHead, { props: { section, count, first, last, position: 1 } });
const menuItem = (w: ReturnType<typeof head>, text: string) =>
  w.findAll("button").find((b) => b.text().startsWith(text));
async function choose(w: ReturnType<typeof head>, text: string) {
  await w.get('button[aria-label^="More actions for section"]').trigger("click");
  await menuItem(w, text)?.trigger("click");
}

describe("section heading in edit mode (ux, Sections in edit mode)", () => {
  it("moves a section, and says why it can't at the ends", async () => {
    const w = head(2, true, false);
    await choose(w, "Move up");
    // A disabled item does nothing and leaves the menu open, saying why.
    expect(w.emitted("stage")).toBeUndefined();
    expect(menuItem(w, "Move up")?.text()).toContain("It's already first.");
    await menuItem(w, "Move down")?.trigger("click");
    expect(w.emitted("stage")?.[0]).toEqual([
      { event: "move_section", input: { section_id: "dash_section_power", direction: "down" } },
    ]);
  });
  it("removes an empty section at once", async () => {
    const w = head(0);
    await choose(w, "Remove section");
    expect(w.emitted("stage")?.[0]).toEqual([
      { event: "remove_section", input: { section_id: "dash_section_power" } },
    ]);
  });
  it("confirms a non-empty one in place, saying its widgets stay", async () => {
    const w = head(3);
    await choose(w, "Remove section");
    expect(w.emitted("stage")).toBeUndefined();
    expect(w.text()).toContain(
      "Remove the section “Power”? Its 3 widgets stay on the dashboard, at the top, outside any section.",
    );
    await w
      .findAll("button")
      .find((b) => b.text() === "Remove section")
      ?.trigger("click");
    expect(w.emitted("stage")?.[0]).toEqual([
      { event: "remove_section", input: { section_id: "dash_section_power" } },
    ]);
  });
});

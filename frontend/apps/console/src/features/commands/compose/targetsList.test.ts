import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/fixtures.ts";
import TargetsPanel from "./TargetsPanel.vue";
import { EMPTY_QUERY } from "./targets.ts";

/** Scale (lead 11-15): the target list renders only while open, capped at 200 until Show all. */
describe("Compose target list at scale", () => {
  it("renders nothing until opened, then 200 rows and Show all", async () => {
    const rows = Array.from({ length: 250 }, (_, i) => spacecraftRow(i + 1));
    const w = mount(TargetsPanel, {
      props: { fleet: rows, query: EMPTY_QUERY, targets: rows },
      global: { stubs: { RouterLink: RouterLinkStub } },
      attachTo: document.body,
    });
    const details = w.findAll("details").at(-1);
    if (!details) throw new Error("no details");
    expect(details.findAll("li")).toHaveLength(0);
    details.element.setAttribute("open", "");
    await details.trigger("toggle");
    // 200 targets plus the Show all row.
    expect(details.findAll("li")).toHaveLength(201);
    const all = details.findAll("button").find((b) => b.text() === "Show all 250");
    if (!all) throw new Error("no Show all");
    expect(all.attributes("aria-expanded")).toBe("false");
    if (all.element instanceof HTMLElement) all.element.focus();
    await all.trigger("click");
    // a11y B3 (#243): the toggle stays (250 targets plus its row), says Hide, keeps focus.
    expect(details.findAll("li")).toHaveLength(251);
    expect(all.attributes("aria-expanded")).toBe("true");
    expect(all.text()).toBe("Show first 200");
    expect(document.activeElement).toBe(all.element);
    await all.trigger("click");
    expect(details.findAll("li")).toHaveLength(201);
    w.unmount();
  });
});

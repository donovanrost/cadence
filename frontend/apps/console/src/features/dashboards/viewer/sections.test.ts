import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { snapshotJson } from "../fixtures.test-support.ts";
import { workspaceSnapshot, type WorkspaceSnapshot } from "../model/snapshot.ts";
import DashboardGrid from "./DashboardGrid.vue";

/** A board with a collapsed-by-default 'Power', an open 'Thermal', and an empty 'Spare'. */
function board(): WorkspaceSnapshot {
  const base = snapshotJson();
  const battery = base.placements[0];
  if (!battery) throw new Error("fixture");
  const r = decode(workspaceSnapshot, {
    ...base,
    sections: [
      { id: "power", title: "Power", description: "Batteries and buses.", collapsed: true },
      { id: "thermal", title: "Thermal", description: "Radiators.", collapsed: false },
      { id: "spare", title: "Spare", description: null, collapsed: false },
    ],
    placements: [
      battery,
      { ...battery, id: "radiator", authored_id: "radiator", section_id: "thermal" },
    ],
  });
  if (!r.ok) throw new Error("fixture");
  return r.value;
}
const mountGrid = () => mount(DashboardGrid, { props: { snapshot: board() } });
type Grid = ReturnType<typeof mountGrid>;
const heading = (w: Grid, title: string) => {
  const button = w.findAll("button[aria-expanded]").find((b) => b.text().includes(title));
  if (!button) throw new Error(`no heading ${title}`);
  return button;
};
/** v-show hides a collapsed section's grid (display: none); it stays mounted. */
const shown = (w: Grid, title: string) =>
  !(w.get(`#${heading(w, title).attributes("aria-controls")}`).attributes("style") ?? "").includes(
    "display: none",
  );

describe("sections in the viewer (ux, Sections in the viewer)", () => {
  it("opens collapsed when 'Start collapsed' is set: heading and count only", () => {
    const w = mountGrid();
    expect(heading(w, "Power").attributes("aria-expanded")).toBe("false");
    expect(heading(w, "Power").text()).toContain("1 WIDGET");
    expect(shown(w, "Power")).toBe(false);
    expect(w.text()).not.toContain("Batteries and buses.");
    expect(heading(w, "Thermal").attributes("aria-expanded")).toBe("true");
    expect(w.text()).toContain("Radiators.");
  });
  it("opens on toggle, and a fresh mount (kiosk, Present, a reload) shows the default again", async () => {
    const w = mountGrid();
    await heading(w, "Power").trigger("click");
    expect(heading(w, "Power").attributes("aria-expanded")).toBe("true");
    expect(shown(w, "Power")).toBe(true);
    expect(w.text()).toContain("Batteries and buses.");
    w.unmount();
    const again = mountGrid();
    expect(heading(again, "Power").attributes("aria-expanded")).toBe("false");
  });
  it("doesn't draw an empty section", () => {
    const w = mountGrid();
    expect(w.text()).not.toContain("Spare");
  });
});

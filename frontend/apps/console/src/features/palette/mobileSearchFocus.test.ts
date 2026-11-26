import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import MobileSearchResults from "./MobileSearchResults.vue";
import type { Group, GroupView, PaletteItem } from "./results.ts";

/** a11y B3/A5 (#243, ux and dashboards on #458): the phone Search results keep focus. */
const item = (n: number): PaletteItem => ({
  key: `sc-${n}`,
  group: "Spacecraft",
  title: `EARENDIL-${n}`,
  subtitle: "Nominal",
  hint: "",
  state: null,
  to: "/",
  commandTo: null,
  rank: n,
});
const view = (shown: number, more: number): GroupView => ({
  group: "Spacecraft",
  items: Array.from({ length: shown }, (_, i) => item(i + 1)),
  more,
});
const base = { query: "ear", sources: {}, expanded: new Set<Group>() };
afterEach(() => {
  document.body.innerHTML = "";
});

describe("Show all N", () => {
  it("stays as a toggle (Show first 5) with aria-expanded, so focus stays on it", async () => {
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [view(5, 4)] },
      attachTo: document.body,
    });
    const toggle = () => w.findAll("button").find((b) => /^Show (all|first)/.test(b.text()));
    expect(toggle()?.text()).toBe("Show all 9");
    expect(toggle()?.attributes("aria-expanded")).toBe("false");
    await toggle()?.trigger("click");
    expect(w.emitted("expand")?.[0]).toEqual(["Spacecraft"]);
    // The sheet expands the group: all rows shown, nothing more.
    await w.setProps({ groups: [view(9, 0)], expanded: new Set<Group>(["Spacecraft"]) });
    expect(toggle()?.text()).toBe("Show first 5");
    expect(toggle()?.attributes("aria-expanded")).toBe("true");
    await toggle()?.trigger("click");
    expect(w.emitted("collapse")?.[0]).toEqual(["Spacecraft"]);
    w.unmount();
  });
});

describe("Try again", () => {
  const failed = { Spacecraft: "failed" as const };

  it("lands focus on the group's heading once it's back", async () => {
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [], sources: failed },
      attachTo: document.body,
    });
    await w.get('[data-retry="Spacecraft"]').trigger("click");
    expect(w.emitted("retry")?.[0]).toEqual(["Spacecraft"]);
    await w.setProps({ sources: { Spacecraft: "loading" } });
    await w.setProps({ sources: { Spacecraft: "ready" }, groups: [view(2, 0)] });
    await flushPromises();
    expect(document.activeElement?.getAttribute("data-heading")).toBe("Spacecraft");
    w.unmount();
  });

  it("comes back to Try again if it failed again", async () => {
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [], sources: failed },
      attachTo: document.body,
    });
    await w.get('[data-retry="Spacecraft"]').trigger("click");
    await w.setProps({ sources: { Spacecraft: "loading" } });
    await w.setProps({ sources: failed });
    await flushPromises();
    expect(document.activeElement?.getAttribute("data-retry")).toBe("Spacecraft");
    w.unmount();
  });

  it("back with no rows: focus goes to the search field, and nothing pulls it later", async () => {
    const dialog = document.createElement("div");
    dialog.setAttribute("role", "dialog");
    const search = document.createElement("input");
    search.type = "search";
    dialog.append(search);
    document.body.append(dialog);
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [], sources: failed },
      attachTo: dialog,
    });
    await w.get('[data-retry="Spacecraft"]').trigger("click");
    await w.setProps({ sources: { Spacecraft: "loading" } });
    await w.setProps({ sources: { Spacecraft: "ready" }, groups: [] });
    await flushPromises();
    expect(document.activeElement).toBe(search);
    // A later search that brings the group back doesn't move focus (retrying was cleared).
    const other = document.createElement("button");
    document.body.append(other);
    other.focus();
    await w.setProps({ groups: [view(2, 0)] });
    await flushPromises();
    expect(document.activeElement).toBe(other);
    w.unmount();
  });

  it("names Try again and the toggle with their group (B7)", () => {
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [view(5, 4)], sources: { Alarms: "failed" as const } },
    });
    expect(w.get('[data-retry="Alarms"]').attributes("aria-label")).toBe("Try again, Alarms");
    const toggle = w.findAll("button").find((b) => b.text() === "Show all 9");
    expect(toggle?.attributes("aria-label")).toBe("Show all 9, Spacecraft");
  });

  it("leaves focus alone when the person moved on while it loaded (B4)", async () => {
    const w = mount(MobileSearchResults, {
      props: { ...base, groups: [], sources: failed },
      attachTo: document.body,
    });
    await w.get('[data-retry="Spacecraft"]').trigger("click");
    await w.setProps({ sources: { Spacecraft: "loading" } });
    const elsewhere = document.createElement("input");
    document.body.append(elsewhere);
    elsewhere.focus();
    await w.setProps({ sources: { Spacecraft: "ready" }, groups: [view(2, 0)] });
    await flushPromises();
    expect(document.activeElement).toBe(elsewhere);
    w.unmount();
  });
});

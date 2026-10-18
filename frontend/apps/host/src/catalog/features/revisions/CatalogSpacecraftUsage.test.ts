import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CatalogSpacecraftUsage from "./CatalogSpacecraftUsage.vue";
import { readSpacecraftUsage } from "./spacecraft-usage";

function usage(active: boolean, saved: boolean) {
  return {
    mission_id: "mission-a",
    total_count: 1,
    usage: [
      {
        id: "craft-a",
        name: "Explorer",
        active,
        saved,
        href: "/missions/mission-a/spacecraft/craft-a?section=changes",
      },
    ],
  };
}
test.each([
  [false, true, "Saved configuration"],
  [true, false, "Active"],
  [true, true, "Active · Saved configuration"],
] as const)(
  "renders active=%s saved=%s with direct spacecraft navigation",
  (active, saved, label) => {
    const wrapper = mount(CatalogSpacecraftUsage, { props: { data: usage(active, saved) } });
    const row = wrapper.get("#catalog-spacecraft-usage-craft-a");
    expect(row.findAll("td")[0]?.text()).toBe(label);
    expect(row.get("a").attributes("href")).toBe(
      "/missions/mission-a/spacecraft/craft-a?section=changes",
    );
    expect(wrapper.find("#catalog-spacecraft-usage-empty").exists()).toBe(false);
    wrapper.unmount();
  },
);
test("imported-only explains availability without claiming spacecraft use", () => {
  const wrapper = mount(CatalogSpacecraftUsage, {
    props: { data: { mission_id: "mission-a", total_count: 0, usage: [] } },
  });
  expect(wrapper.get("#catalog-spacecraft-usage-empty").text()).toContain(
    "Imported and available to select",
  );
  expect(wrapper.get("#catalog-spacecraft-usage-empty a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft",
  );
  wrapper.unmount();
});
test("rejects impossible usage, duplicate spacecraft, false totals and scope-mismatched links", () => {
  expect(() => readSpacecraftUsage(usage(false, false))).toThrow();
  const data = usage(true, true);
  expect(() => readSpacecraftUsage({ ...data, total_count: 0 })).toThrow();
  expect(() =>
    readSpacecraftUsage({ ...data, total_count: 2, usage: [...data.usage, ...data.usage] }),
  ).toThrow();
  expect(() => readSpacecraftUsage({ ...data, mission_id: "other" })).toThrow();
});
test("discloses detail truncation without truncating the total", () => {
  const rows = Array.from({ length: 100 }, (_, index) => ({
    id: "craft-" + index,
    name: "Explorer " + index,
    active: false,
    saved: true,
    href: "/missions/mission-a/spacecraft/craft-" + index + "?section=changes",
  }));
  const wrapper = mount(CatalogSpacecraftUsage, {
    props: { data: { mission_id: "mission-a", total_count: 101, usage: rows } },
  });
  expect(wrapper.get("#catalog-spacecraft-usage-limit").text()).toBe(
    "Showing 100 of 101 spacecraft.",
  );
  wrapper.unmount();
});

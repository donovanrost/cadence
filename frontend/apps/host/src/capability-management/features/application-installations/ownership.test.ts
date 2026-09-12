import { readFileSync } from "node:fs";
import { expect, test } from "vite-plus/test";
import * as publicFeature from "../../index";
import MissionApplicationsPage from "./MissionApplicationsPage.vue";
import SpacecraftApplicationsPage from "./SpacecraftApplicationsPage.vue";
import { installationBreadcrumbs } from "./breadcrumbs";

test("legacy package entries delegate to the core public API without a second implementation", () => {
  expect(publicFeature.MissionApplicationsPage).toBe(MissionApplicationsPage);
  expect(publicFeature.SpacecraftApplicationsPage).toBe(SpacecraftApplicationsPage);
  for (const [pkg, names] of [
    ["mission-catalog", ["MissionApplications", "MissionApplicationsPage"]],
    ["spacecraft", ["SpacecraftApplications", "SpacecraftApplicationsPage"]],
  ] as const) {
    for (const name of names) {
      const source = readFileSync(
        new URL("../../../../../" + pkg + "/src/" + name + ".vue", import.meta.url),
        "utf8",
      );
      expect(source).toContain('from "@cadence/plugin-host/capability-management"');
      expect(source).not.toMatch(/<template>|defineProps|defineEmits/);
    }
  }
});

test("both producer breadcrumb shapes preserve their navigation hierarchy", () => {
  expect(
    installationBreadcrumbs({
      attrs: {},
      items: [
        { label: "Mission", href: "/missions/mission-a" },
        {
          key: "current",
          separator: null,
          link: null,
          current: { attrs: {}, text: "Applications" },
        },
      ],
    }),
  ).toEqual([{ label: "Mission", href: "/missions/mission-a" }, { label: "Applications" }]);
});

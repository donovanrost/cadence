import { expect, test } from "vite-plus/test";
import { breadcrumbTrail } from "./breadcrumbs";

const context = {
  organization: { display_name: "Flight Operations" },
  mission: { display_name: "Kestrel" },
  spacecraft: { display_name: "KST-1" },
};

// Since #708 the settings pair is the catalog's only list with a page under it, and the
// application surface its only record.
test("a page's trail links back to its list", () => {
  expect(
    breadcrumbTrail(
      { path: "/missions/:mission_id/settings/:section_id", scope: "mission" },
      "/missions/m1/settings/general",
      context,
      "General",
    ),
  ).toEqual([
    { label: "Flight Operations", href: "/" },
    { label: "Kestrel", href: "/missions/m1" },
    { label: "Mission settings", href: "/missions/m1/settings" },
    { label: "General" },
  ]);
});

test("records above the page are left out; the spacecraft is named by context", () => {
  const labels = (pattern: string, path: string) =>
    breadcrumbTrail({ path: pattern, scope: "mission" }, path, context, "Page").map((c) => c.label);
  expect(
    labels(
      "/missions/:mission_id/applications/:application_key/:surface_id/edit",
      "/missions/m1/applications/ops_console/data_sources/edit",
    ),
  ).toEqual(["Flight Operations", "Kestrel", "Page"]);
  expect(
    labels(
      "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id",
      "/missions/m1/spacecraft/s1/applications/telemetry_decom/manage",
    ),
  ).toEqual(["Flight Operations", "Kestrel", "KST-1", "Page"]);
});

test("the mission page ends at the mission", () => {
  expect(
    breadcrumbTrail(
      { path: "/missions/:mission_id", scope: "mission" },
      "/missions/m1",
      context,
      "Kestrel",
    ),
  ).toEqual([{ label: "Flight Operations", href: "/" }, { label: "Kestrel" }]);
});

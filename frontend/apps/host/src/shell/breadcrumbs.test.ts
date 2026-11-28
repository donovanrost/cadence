import { expect, test } from "vite-plus/test";
import { breadcrumbTrail } from "./breadcrumbs";

const context = {
  organization: { display_name: "Flight Operations" },
  mission: { display_name: "Kestrel" },
  spacecraft: { display_name: "KST-1" },
};

test("a record's trail links back to its list", () => {
  expect(
    breadcrumbTrail(
      { path: "/missions/:mission_id/ops/contacts/records/:contact_id", scope: "mission" },
      "/missions/m1/ops/contacts/records/c1",
      context,
      "Contact Record",
    ),
  ).toEqual([
    { label: "Flight Operations", href: "/" },
    { label: "Kestrel", href: "/missions/m1" },
    { label: "Contact Schedule", href: "/missions/m1/ops/contacts" },
    { label: "Contact Record" },
  ]);
});

test("records above the page are left out; the spacecraft is named by context", () => {
  const labels = (pattern: string, path: string) =>
    breadcrumbTrail({ path: pattern, scope: "mission" }, path, context, "Page").map((c) => c.label);
  expect(
    labels(
      "/missions/:mission_id/ops/contacts/records/:contact_id/edit",
      "/missions/m1/ops/contacts/records/c1/edit",
    ),
  ).toEqual(["Flight Operations", "Kestrel", "Contact Schedule", "Page"]);
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

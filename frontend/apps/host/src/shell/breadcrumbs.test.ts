import { expect, test } from "vite-plus/test";
import { breadcrumbTrail } from "./breadcrumbs";

const context = {
  organization: { display_name: "Flight Operations" },
  mission: { display_name: "Kestrel" },
  spacecraft: { display_name: "KST-1" },
};

test("a record's trail links back through its section and list", () => {
  expect(
    breadcrumbTrail(
      { path: "/missions/:mission_id/comms/transports/:transport_id", scope: "mission" },
      "/missions/m1/comms/transports/t1",
      context,
      "Transport",
    ),
  ).toEqual([
    { label: "Flight Operations", href: "/" },
    { label: "Kestrel", href: "/missions/m1" },
    { label: "Comms", href: "/missions/m1/comms" },
    { label: "Transports", href: "/missions/m1/comms/transports" },
    { label: "Transport" },
  ]);
});

test("records above the page are left out; the spacecraft is named by context", () => {
  const labels = (pattern: string, path: string) =>
    breadcrumbTrail({ path: pattern, scope: "mission" }, path, context, "Page").map((c) => c.label);
  expect(
    labels(
      "/missions/:mission_id/comms/ground-stations/:ground_station_id/edit",
      "/missions/m1/comms/ground-stations/g1/edit",
    ),
  ).toEqual(["Flight Operations", "Kestrel", "Comms", "Ground Stations", "Page"]);
  expect(
    labels(
      "/missions/:mission_id/spacecraft/:spacecraft_id/routing",
      "/missions/m1/spacecraft/s1/routing",
    ),
  ).toEqual(["Flight Operations", "Kestrel", "Spacecraft", "KST-1", "Page"]);
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

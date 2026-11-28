// @vitest-environment node
import { expect, expectTypeOf, test } from "vite-plus/test";
import { href, isRouteId, routeCatalog, type Href, type RouteHeaderKind } from ".";
import catalog from "../../../../apps/host/src/routes.json";
import { projectRoutes } from "./project";

const surface = "/missions/:mission_id/applications/:application_key/:surface_id" as const;

test("the generated catalog matches the host route catalog exactly", () => {
  // Regenerate with `corepack pnpm routes:generate` when this fails.
  expect(routeCatalog).toEqual(projectRoutes(catalog));
});

// No catalog route admits a query key since #708 deleted the commands pages, so links are checked
// for their encoded params only.
test("links are built from routes, with encoded params", () => {
  expect(
    href(surface, { mission_id: "m 1", application_key: "ops_console", surface_id: "a/b" }),
  ).toBe("/missions/m%201/applications/ops_console/a%2Fb");
  expect(isRouteId(surface)).toBe(true);
  expect(isRouteId("/missions/:mission_id/settings")).toBe(false);
});

test("route drift is a type error", () => {
  expectTypeOf(
    href(surface, { mission_id: "m", application_key: "ops_console", surface_id: "data_sources" }),
  ).toEqualTypeOf<Href>();
  expectTypeOf<RouteHeaderKind<typeof surface>>().toEqualTypeOf<"resource">();
  // @ts-expect-error -- routes that do not exist cannot be linked
  expect(() => href("/missions/:mission_id/ops/nowhere", { mission_id: "m" })).not.toThrow();
  // @ts-expect-error -- every path param is required
  expect(() => href(surface, { mission_id: "m" })).toThrow();
  // @ts-expect-error -- a plain string is not a link
  const link: Href = "/missions";
  expect(link).toBe("/missions");
});

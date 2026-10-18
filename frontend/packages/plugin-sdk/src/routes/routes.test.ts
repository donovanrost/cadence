// @vitest-environment node
import { expect, expectTypeOf, test } from "vite-plus/test";
import { href, isRouteId, routeCatalog, type Href, type RouteHeaderKind } from ".";
import catalog from "../../../../apps/host/src/routes.json";
import { projectRoutes } from "./project";

test("the generated catalog matches the host route catalog exactly", () => {
  // Regenerate with `corepack pnpm routes:generate` when this fails.
  expect(routeCatalog).toEqual(projectRoutes(catalog));
});

test("links are built from routes, with encoded params and admitted query keys", () => {
  expect(href("/missions/:mission_id/ops/dashboards", { mission_id: "m 1" })).toBe(
    "/missions/m%201/ops/dashboards",
  );
  expect(
    href(
      "/missions/:mission_id/ops/dashboards",
      { mission_id: "m" },
      { tags: "eps,thermal", query: "" },
    ),
  ).toBe("/missions/m/ops/dashboards?tags=eps%2Cthermal");
  expect(href("/missions")).toBe("/missions");
  expect(isRouteId("/missions/:mission_id/ops/alarms")).toBe(true);
  expect(isRouteId("/missions/:mission_id/ops/nowhere")).toBe(false);
});

test("route drift is a type error", () => {
  expectTypeOf(href("/missions")).toEqualTypeOf<Href>();
  expectTypeOf<RouteHeaderKind<"/missions/:mission_id/ops/alarms">>().toEqualTypeOf<"collection">();
  expectTypeOf<
    RouteHeaderKind<"/missions/:mission_id/ops/dashboards/:dashboard_id/settings">
  >().toEqualTypeOf<"resource">();
  expectTypeOf<
    RouteHeaderKind<"/missions/:mission_id/ops/dashboards/:dashboard_id">
  >().toEqualTypeOf<"none">();
  // @ts-expect-error -- routes that do not exist cannot be linked
  expect(() => href("/missions/:mission_id/ops/nowhere", { mission_id: "m" })).not.toThrow();
  // @ts-expect-error -- every path param is required
  expect(() => href("/missions/:mission_id/ops/alarms", {})).toThrow();
  // @ts-expect-error -- query keys the route does not admit are rejected
  href("/missions/:mission_id/ops/alarms", { mission_id: "m" }, { tags: "eps" });
  // @ts-expect-error -- a plain string is not a link
  const link: Href = "/missions";
  expect(link).toBe("/missions");
});

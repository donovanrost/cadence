// @vitest-environment node
import { expect, expectTypeOf, test } from "vite-plus/test";
import { href, isRouteId, routeCatalog, type Href, type RouteHeaderKind } from ".";
import catalog from "../../../../apps/host/src/routes.json";
import retained from "../../../../tools/retained-legacy-routes.json";
import { projectRoutes } from "./project";

test("the generated catalog matches the host route catalog exactly", () => {
  // Regenerate with `corepack pnpm routes:generate` when this fails. The catalog also holds the
  // retained legacy routes, until the L1-L4 federated batch deletes them (fe-ops).
  expect(routeCatalog).toEqual(projectRoutes([...catalog, ...retained.routes]));
});

test("a retained legacy route never comes back into the host catalog (the list only shrinks)", () => {
  const hostPaths = new Set(catalog.map((route) => route.path));
  expect(retained.routes.filter((route) => hostPaths.has(route.path))).toEqual([]);
});

test("links are built from routes, with encoded params and admitted query keys", () => {
  expect(href("/missions/:mission_id/ops/alarms", { mission_id: "m 1" })).toBe(
    "/missions/m%201/ops/alarms",
  );
  expect(
    href(
      "/missions/:mission_id/ops/alarms",
      { mission_id: "m" },
      { severity: "warning,critical", query: "" },
    ),
  ).toBe("/missions/m/ops/alarms?severity=warning%2Ccritical");
  expect(href("/provider-accounts")).toBe("/provider-accounts");
  expect(isRouteId("/missions/:mission_id/ops/alarms")).toBe(true);
  expect(isRouteId("/missions/:mission_id/ops/nowhere")).toBe(false);
});

test("route drift is a type error", () => {
  expectTypeOf(href("/provider-accounts")).toEqualTypeOf<Href>();
  expectTypeOf<RouteHeaderKind<"/missions/:mission_id/ops/alarms">>().toEqualTypeOf<"collection">();
  expectTypeOf<
    RouteHeaderKind<"/missions/:mission_id/ops/commands/requests/:command_request_id">
  >().toEqualTypeOf<"resource">();
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

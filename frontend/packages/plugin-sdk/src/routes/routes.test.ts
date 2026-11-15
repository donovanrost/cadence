// @vitest-environment node
import { expect, expectTypeOf, test } from "vite-plus/test";
import { href, isRouteId, routeCatalog, type Href, type RouteHeaderKind } from ".";
import { existsSync, readFileSync } from "node:fs";
import catalog from "../../../../apps/host/src/routes.json";
import retained from "../../../../tools/retained-legacy-routes.json";
import { projectRoutes } from "./project";

const frontend = new URL("../../../../", import.meta.url);

/**
 * The retained legacy routes as §11c B left them (lead 11-15). The list may only shrink: B12 and
 * (C) remove an entry when they delete its last consumer. Adding a path means editing this frozen
 * baseline too, which is allowed only in a deletion batch's own commit (legacy-deletion.md).
 */
const RETAINED_BASELINE = [
  "/missions/:mission_id",
  "/missions/:mission_id/applications",
  "/missions/:mission_id/catalog",
  "/missions/:mission_id/catalog/databases/:catalog_database_id",
  "/missions/:mission_id/catalog/imports/:import_run_id",
  "/missions/:mission_id/catalog/new",
  "/missions/:mission_id/catalog/revisions/:catalog_revision_id",
  "/missions/:mission_id/comms",
  "/missions/:mission_id/comms/ground-stations",
  "/missions/:mission_id/comms/ground-stations/:ground_station_id",
  "/missions/:mission_id/comms/ground-stations/:ground_station_id/edit",
  "/missions/:mission_id/comms/ground-stations/new",
  "/missions/:mission_id/comms/routing",
  "/missions/:mission_id/comms/routing/:routing_rule_id",
  "/missions/:mission_id/comms/routing/new",
  "/missions/:mission_id/comms/transports",
  "/missions/:mission_id/comms/transports/:transport_id",
  "/missions/:mission_id/comms/transports/new",
  "/missions/:mission_id/comms/validation",
  "/missions/:mission_id/settings",
  "/missions/:mission_id/settings/:section_id",
  "/missions/:mission_id/spacecraft",
  "/missions/:mission_id/spacecraft/:spacecraft_id/applications",
  "/missions/:mission_id/spacecraft/:spacecraft_id/readiness",
  "/missions/:mission_id/spacecraft/:spacecraft_id/routing",
  "/missions/:mission_id/spacecraft/new",
  "/missions/:mission_id/spacecraft/profiles",
  "/missions/:mission_id/spacecraft/profiles/:profile_id",
  "/missions/:mission_id/spacecraft/profiles/new",
] as const;

test("the generated catalog matches the host route catalog exactly", () => {
  // Regenerate with `corepack pnpm routes:generate` when this fails. The catalog also holds the
  // retained legacy routes (tools/retained-legacy-routes.json), until B12 / (C) delete their consumers.
  expect(routeCatalog).toEqual(projectRoutes([...catalog, ...retained.routes]));
});

test("a retained legacy route never comes back into the host catalog", () => {
  const hostPaths = new Set(catalog.map((route) => route.path));
  expect(retained.routes.filter((route) => hostPaths.has(route.path))).toEqual([]);
});

test("the retained list only shrinks: a subset of the frozen baseline, never longer", () => {
  const baseline = new Set<string>(RETAINED_BASELINE);
  const paths = retained.routes.map((route) => route.path);
  expect(paths.filter((path) => !baseline.has(path))).toEqual([]);
  expect(new Set(paths).size).toBe(paths.length);
  expect(paths.length).toBeLessThanOrEqual(RETAINED_BASELINE.length);
});

test("every retained route still has a live consumer that types a header by it", () => {
  for (const route of retained.routes) {
    expect(route.consumers.length, route.path).toBeGreaterThan(0);
    for (const consumer of route.consumers) {
      const file = new URL(consumer.file, frontend);
      expect(existsSync(file), `${route.path}: ${consumer.file} is gone`).toBe(true);
      expect(
        readFileSync(file, "utf8").includes(JSON.stringify(route.path)),
        `${route.path}: ${consumer.file} (${consumer.surface}) no longer references it`,
      ).toBe(true);
    }
  }
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
  // §11c: no parameterless route is left, and the mission settings page is in the console.
  expect(href("/missions/:mission_id/ops", { mission_id: "m" })).toBe("/missions/m/ops");
  expect(isRouteId("/missions/:mission_id/ops/alarms")).toBe(true);
  expect(isRouteId("/missions/:mission_id/ops/nowhere")).toBe(false);
});

test("route drift is a type error", () => {
  expectTypeOf(href("/missions/:mission_id/ops", { mission_id: "m" })).toEqualTypeOf<Href>();
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

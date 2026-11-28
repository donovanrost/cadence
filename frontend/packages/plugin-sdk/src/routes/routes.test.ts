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
  "/missions/:mission_id/settings",
  "/missions/:mission_id/settings/:section_id",
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

// No catalog route admits a query key since #708 deleted the commands pages, so links are checked
// for their encoded params only.
test("links are built from routes, with encoded params", () => {
  expect(href("/missions/:mission_id/settings", { mission_id: "m 1" })).toBe(
    "/missions/m%201/settings",
  );
  expect(
    href("/missions/:mission_id/settings/:section_id", { mission_id: "m", section_id: "a/b" }),
  ).toBe("/missions/m/settings/a%2Fb");
  expect(
    href("/missions/:mission_id/applications/:application_key/:surface_id", {
      mission_id: "m",
      application_key: "ops_console",
      surface_id: "data_sources",
    }),
  ).toBe("/missions/m/applications/ops_console/data_sources");
  expect(isRouteId("/missions/:mission_id/settings")).toBe(true);
  expect(isRouteId("/missions/:mission_id/ops/commands")).toBe(false);
});

test("route drift is a type error", () => {
  expectTypeOf(
    href("/missions/:mission_id/applications/:application_key/:surface_id", {
      mission_id: "m",
      application_key: "ops_console",
      surface_id: "data_sources",
    }),
  ).toEqualTypeOf<Href>();
  expectTypeOf<RouteHeaderKind<"/missions/:mission_id/settings">>().toEqualTypeOf<"collection">();
  expectTypeOf<
    RouteHeaderKind<"/missions/:mission_id/applications/:application_key/:surface_id">
  >().toEqualTypeOf<"resource">();
  // @ts-expect-error -- routes that do not exist cannot be linked
  expect(() => href("/missions/:mission_id/ops/nowhere", { mission_id: "m" })).not.toThrow();
  // @ts-expect-error -- every path param is required
  expect(() => href("/missions/:mission_id/settings", {})).toThrow();
  // @ts-expect-error -- a plain string is not a link
  const link: Href = "/missions";
  expect(link).toBe("/missions");
});

import { hostRoute } from "./shell/host-navigation";
import { required } from "../../../test-support/required";
import { expect, test } from "vite-plus/test";
import routes from "./routes.json";
import { loadedOpsPages as opsPages } from "./module-pages.test-support";
test("commands are a compiled read-only mission contribution with explicit navigation", () => {
  const route = required(routes.find((r) => r.path === "/missions/:mission_id/ops/commands"));
  expect(route).toMatchObject({ kind: "ops_module", contribution: "commanding.monitor" });
  expect(route).not.toHaveProperty("application");
  expect(route).not.toHaveProperty("surface");
  expect(route.resourceParam).toBeUndefined();
  expect(route.queryKeys).toEqual(["status", "target", "query", "focus_command_id", "page"]);
  expect(required(opsPages["commanding.monitor"]).navigation).toBe(true);
  expect(required(opsPages["commanding.monitor"]).actions).toBeUndefined();
});
test("each core host route resolves to its registered owner", () => {
  expect(new Set(routes.map((route) => route.path)).size).toBe(routes.length);
  for (const route of routes) {
    if (route.kind === "ops_module") {
      expect(opsPages[required(route.contribution)], route.path).toBeDefined();
      expect(route.scope).toBe("mission");
      expect(route).not.toHaveProperty("application");
      expect(route).not.toHaveProperty("surface");
      continue;
    }
    if (route.kind === "application_surface") {
      // Not served by this host: catalogued only so the trusted application surfaces that still
      // render these pages can type their header by the path.
      expect(hostRoute(new URL(route.path, "https://cadence.test"))).toBeUndefined();
      expect(route).not.toHaveProperty("application");
      continue;
    }
    throw new Error(`Unregistered core route kind: ${route.kind} (${route.path})`);
  }
});

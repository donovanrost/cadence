import { hostRoute } from "./shell/host-navigation";
import { expect, test } from "vite-plus/test";
import routes from "./routes.json";
// Since #708 the catalog has no ops_module route: the host serves none, and a new one is refused here.
test("each core host route resolves to its registered owner", () => {
  expect(new Set(routes.map((route) => route.path)).size).toBe(routes.length);
  for (const route of routes) {
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

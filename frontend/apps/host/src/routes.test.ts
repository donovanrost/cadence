import { expect, test } from "vite-plus/test";
import routes from "./routes.json";
import { resolveHostComponent } from "./shell/registry";
import { manifest as missionCatalog } from "../../mission-catalog/src/federated-application";
import { manifest as spacecraft } from "../../spacecraft/src/federated-application";
import { manifest as comms } from "../../comms-overview/src/federated-application";
import { manifest as opsConsole } from "../../ops-console/src/federated-application";
import { manifest as organizationAdmin } from "../../organization-admin/src/federated-application";
const manifests = [missionCatalog, spacecraft, comms, opsConsole, organizationAdmin];
test("each host route resolves to a host component or a production surface in its declared scope", () => {
  expect(new Set(routes.map((route) => route.path)).size).toBe(routes.length);
  for (const route of routes) {
    if (route.kind === "application_management") {
      expect(resolveHostComponent(route.component)).toBeDefined();
      expect(route.queryKeys).toEqual([]);
      expect(["mission", "spacecraft"]).toContain(route.scope);
      continue;
    }
    const manifest = manifests.find(
      (manifest) => manifest.application.applicationKey === route.application,
    );
    expect(manifest, route.path).toBeDefined();
    const surface = manifest!.surfaces.find((surface) => surface.surfaceId === route.surface);
    expect(surface, route.path).toBeDefined();
    expect(surface!.scope, route.path).toBe(route.scope);
    expect(new Set(route.queryKeys).size, route.path).toBe(route.queryKeys.length);
    for (const key of Object.keys(route.queryAliases))
      expect(route.queryKeys, route.path).toContain(key);
  }
});

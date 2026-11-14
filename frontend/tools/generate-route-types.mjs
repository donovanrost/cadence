import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { renderRoutes } from "../packages/plugin-sdk/src/routes/project.ts";

const root = new URL("../", import.meta.url);
const hostRoutes =
  /** @type {import("../packages/plugin-sdk/src/routes/project.ts").CatalogEntry[]} */ (
    JSON.parse(await readFile(new URL("apps/host/src/routes.json", root), "utf8"))
  );
// Removed host routes that kept federated surfaces still link by type, until the L1-L4
// federated batch deletes them (fe-ops); routes.test.ts holds the list to shrinking only.
const retained =
  /** @type {{ routes: import("../packages/plugin-sdk/src/routes/project.ts").CatalogEntry[] }} */ (
    JSON.parse(await readFile(new URL("tools/retained-legacy-routes.json", root), "utf8"))
  );
const catalog = [...hostRoutes, ...retained.routes];
const target = fileURLToPath(new URL("packages/plugin-sdk/src/routes/catalog.generated.ts", root));
await writeFile(target, renderRoutes(catalog));
execFileSync(fileURLToPath(new URL("node_modules/.bin/vp", root)), ["fmt", target], {
  stdio: "inherit",
});

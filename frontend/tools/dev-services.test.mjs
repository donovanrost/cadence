import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { resolveConfig } from "vite-plus";
import { developmentOrigin, developmentPorts } from "./dev-services.ts";

void test("every development and preview service uses its unique fixed port", async () => {
  const services = Object.keys(developmentPorts);
  assert.equal(new Set(Object.values(developmentPorts)).size, services.length);
  for (const service of services) {
    // These keys come from the frozen configuration, not an external string.
    const name = /** @type {keyof typeof developmentPorts} */ (service);
    const root = new URL(`../apps/${name}/`, import.meta.url);
    const config = await resolveConfig(
      {
        root: root.pathname,
        configFile: new URL("vite.config.ts", root).pathname,
        logLevel: "silent",
      },
      "serve",
    );
    assert.equal(config.server.port, developmentPorts[name], name);
    assert.equal(config.preview.port, developmentPorts[name], name);
    assert.equal(config.server.strictPort, true, name);
    assert.equal(config.preview.strictPort, true, name);
    assert.equal(config.server.origin, developmentOrigin(name), name);
    const manifest = await readFile(new URL("package.json", root), "utf8");
    /** @type {unknown} */
    const pkg = JSON.parse(manifest);
    assert.ok(pkg !== null && typeof pkg === "object" && "scripts" in pkg);
    assert.ok(
      pkg.scripts !== null &&
        typeof pkg.scripts === "object" &&
        "dev" in pkg.scripts &&
        "preview" in pkg.scripts,
    );
    assert.equal(pkg.scripts.dev, "vp dev");
    assert.equal(pkg.scripts.preview, "vp preview");
  }
});

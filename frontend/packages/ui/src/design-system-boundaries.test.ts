import { readdirSync, readFileSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { describe, it, expect } from "vite-plus/test";
const frontend = resolve(import.meta.dirname, "../../..");
const web = resolve(frontend, "../apps/cadence_web");
function sources(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (["node_modules", "dist", ".mf", "vendor"].includes(entry.name)) return [];
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? sources(path)
      : /\.(vue|ts|css|js)$/.test(path) && !path.includes(".test.")
        ? [path]
        : [];
  });
}
describe("design-system ownership", () => {
  it("has one UI implementation and one production theme", () => {
    for (const app of readdirSync(join(frontend, "apps")))
      expect(existsSync(join(frontend, "apps", app, "src/ui"))).toBe(false);
    expect(existsSync(join(web, "assets/vue"))).toBe(false);
    expect(existsSync(join(web, "assets/css/tokens.css"))).toBe(false);
    expect(readFileSync(join(web, "assets/css/app.css"), "utf8")).toContain(
      "frontend/apps/host/src/phoenix.css",
    );
  });
  it("does not reintroduce experimental styles or DaisyUI", () => {
    for (const path of [
      ...sources(join(frontend, "packages/ui/src")),
      ...sources(join(frontend, "apps")),
    ]) {
      expect(readFileSync(path, "utf8"), path).not.toMatch(
        /--cadence-color-|Archivo Variable|@plugin[^\n]*daisyui|from ["'][^"']*\/ui\/(?:components|reka)\//,
      );
    }
    expect(existsSync(join(web, "assets/vendor/daisyui.js"))).toBe(false);
    expect(existsSync(join(frontend, "packages/ui/vendor/daisyui.cjs"))).toBe(false);
  });
  it("keeps reset and theme imports out of federated module entries", () => {
    for (const app of readdirSync(join(frontend, "apps"))) {
      const entry = join(frontend, "apps", app, "src/federated-application.ts");
      if (!existsSync(entry)) continue;
      expect(readFileSync(entry, "utf8"), entry).not.toMatch(
        /import ["'][^"']*(?:styles|base|theme)\.css/,
      );
    }
  });
});

import { describe, expect, it } from "vite-plus/test";
import { createConsoleRouter } from "./index.ts";
import { consoleRouteNames, isParamlessRouteName } from "./route-map.ts";

/** The typed map (route-map.ts) and the router agree both ways (typing audit Fix 4). */
describe("typed routes", () => {
  const registered = createConsoleRouter()
    .getRoutes()
    .flatMap((r) => (typeof r.name === "string" ? [r.name] : []))
    .sort();

  it("types every route the console registers, and registers every typed route", () => {
    expect(registered).toEqual(Object.keys(consoleRouteNames).sort());
  });

  it("calls a route paramless only when its path has no params beyond org and mission", () => {
    for (const r of createConsoleRouter().getRoutes()) {
      if (!isParamlessRouteName(r.name)) continue;
      const required = r.path.replace(/:(org|mission)\b/g, "").replace(/:\w+(\([^)]*\))?\?/g, "");
      expect(required, r.name).not.toContain(":");
    }
  });
});

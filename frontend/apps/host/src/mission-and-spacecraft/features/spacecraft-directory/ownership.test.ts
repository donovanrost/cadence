import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import * as publicSpacecraft from "../../spacecraft";

test("legacy spacecraft browsing entries delegate to the host public API without duplicate implementations", () => {
  for (const name of [
    "SpacecraftList",
    "SpacecraftListPage",
    "SpacecraftTypeList",
    "SpacecraftTypeListPage",
    "SpacecraftTypeShow",
  ] as const) {
    expect(publicSpacecraft[name]).toBeDefined();
    const source = readFileSync(
      resolve(
        dirname(fileURLToPath(import.meta.url)),
        "../../../../../spacecraft/src",
        `${name}.vue`,
      ),
      "utf8",
    );
    expect(source).toContain(`import { ${name} } from "@cadence/plugin-host/spacecraft"`);
    expect(source).toContain(`export default ${name};`);
    expect(source).not.toContain("<template>");
  }
});

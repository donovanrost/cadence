import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import * as publicSpacecraft from "../../spacecraft";
import SpacecraftIdentityForm from "./SpacecraftIdentityForm.vue";

test("legacy creation and editing delegate to the single host identity form", () => {
  for (const name of ["SpacecraftNew", "SpacecraftEdit"] as const) {
    expect(publicSpacecraft[name]).toBe(SpacecraftIdentityForm);
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

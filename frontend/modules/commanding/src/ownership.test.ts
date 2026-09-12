import { readFileSync, readdirSync } from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import { OpsCommands, SpacecraftCommanding } from "./index";
import LegacyCommands from "../../../apps/ops-console/src/OpsCommands.vue";
import LegacySpacecraftCommanding from "../../../apps/spacecraft/src/SpacecraftCommanding.vue";

const directory = dirname(fileURLToPath(import.meta.url));

test("legacy entries delegate to the exact public feature implementations", () => {
  expect(LegacyCommands).toBe(OpsCommands);
  expect(LegacySpacecraftCommanding).toBe(SpacecraftCommanding);
  for (const [path, entry] of [
    ["../../../apps/ops-console/src/OpsCommands.vue", "mission-commands"],
    ["../../../apps/spacecraft/src/SpacecraftCommanding.vue", "spacecraft-commanding"],
  ]) {
    const source = readFileSync(resolve(directory, path!), "utf8");
    expect(source).toContain(`@cadence/commanding/${entry}`);
    expect(source).not.toContain("<template>");
  }
});

test("features own their contracts and cannot depend on delivery or sibling internals", () => {
  for (const file of readdirSync(directory, { recursive: true, encoding: "utf8" })) {
    if (!/\.(vue|ts)$/.test(file) || /\.(test|test-support)\./.test(file)) continue;
    const absolute = resolve(directory, file);
    const source = readFileSync(absolute, "utf8");
    const feature = file.split(sep)[0] === "features" ? file.split(sep)[1] : undefined;
    for (const match of source.matchAll(/(?:from\s*|import\s*\()["']([^"']+)["']/g)) {
      const specifier = match[1]!;
      expect(specifier, file).not.toMatch(/@cadence\/(?:plugin-host|.*-plugin)(?:\/|$)/);
      if (!specifier.startsWith(".")) continue;
      const target = relative(directory, resolve(dirname(absolute), specifier));
      expect(target.startsWith(".."), `${file} -> ${specifier}`).toBe(false);
      if (feature && target.startsWith("features" + sep)) {
        expect(target.split(sep)[1], `${file} -> ${specifier}`).toBe(feature);
      }
    }
  }
  for (const feature of [
    "mission-commands",
    "spacecraft-commanding",
    "command-review",
    "command-authoring",
  ]) {
    expect(readFileSync(resolve(directory, "features", feature, "contracts.ts"), "utf8")).toContain(
      "export type",
    );
  }
});

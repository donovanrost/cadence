import { readFileSync, readdirSync } from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import * as planning from "./index";
const features = {
  "contact-requirements": [
    "OpsContactRequirementList",
    "OpsContactRequirementNew",
    "OpsContactRequirementShow",
    "OpsContactRequirementTemplate",
  ],
  "contact-plans": ["OpsContactPlanShow"],
  "contact-scheduling": ["OpsContactSchedule", "OpsContactDetail", "OpsContactRecord"],
  "fleet-planning": [
    "OpsFleetPlanning",
    "OpsFleetPlanningNew",
    "OpsFleetPlanningRun",
    "OpsFleetPlanningPolicy",
  ],
} as const;
const directory = dirname(fileURLToPath(import.meta.url));
const legacy = import.meta.glob("../../../apps/ops-console/src/Ops{Contact,FleetPlanning}*.vue", {
  eager: true,
  import: "default",
});
test("all twelve legacy entries delegate to public domain-owned implementations", () => {
  for (const [feature, names] of Object.entries(features))
    for (const name of names) {
      const path = "../../../apps/ops-console/src/" + name + ".vue";
      expect(legacy[path]).toBe(planning[name]);
      const source = readFileSync(resolve(directory, path), "utf8");
      expect(source).toContain("@cadence/planning-and-contacts/" + feature);
      expect(source).not.toContain("<template>");
    }
});
test("domain source owns contracts and has no delivery or sibling-feature internal dependencies", () => {
  for (const file of readdirSync(directory, { recursive: true, encoding: "utf8" })) {
    if (!/\.(vue|ts)$/.test(file) || /\.(test|test-support)\./.test(file)) continue;
    const absolute = resolve(directory, file),
      source = readFileSync(absolute, "utf8"),
      feature = file.split(sep)[0] === "features" ? file.split(sep)[1] : undefined;
    for (const match of source.matchAll(/(?:from\s*|import\s*\()["']([^"']+)["']/g)) {
      const specifier = match[1]!;
      expect(specifier, file).not.toMatch(/@cadence\/(?:plugin-host|.*-plugin)(?:\/|$)/);
      if (!specifier.startsWith(".")) continue;
      const target = relative(directory, resolve(dirname(absolute), specifier));
      expect(target.startsWith(".."), file + " -> " + specifier).toBe(false);
      if (feature && target.startsWith("features" + sep))
        expect(target.split(sep)[1], file).toBe(feature);
    }
  }
  for (const [feature, names] of Object.entries(features))
    for (const name of names) {
      expect(
        readFileSync(resolve(directory, "features", feature, name + ".contracts.ts"), "utf8"),
      ).toContain("export type " + name + "Props");
    }
  expect(
    readFileSync(resolve(directory, "../../../apps/ops-console/src/styles.css"), "utf8"),
  ).toContain('@source "../../../modules/planning-and-contacts/src"');
});

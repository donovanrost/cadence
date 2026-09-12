import { required } from "../../../test-support/required";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vite-plus/test";
import * as communications from "./index";

const features = {
  overview: ["CommsOverview", "CommsOverviewPage"],
  "setup-validation": ["CommsValidation"],
  transports: [
    "CommsTransportList",
    "CommsTransportListPage",
    "CommsTransportNew",
    "CommsTransportShow",
  ],
  routing: ["CommsRoutingList", "CommsRoutingListPage", "CommsRoutingNew", "CommsRoutingShow"],
  "ground-stations": [
    "CommsGroundStationForm",
    "CommsGroundStationList",
    "CommsGroundStationListPage",
    "CommsGroundStationShow",
  ],
  providers: ["CommsProviderList", "CommsProviderTable", "CommsProviderNew", "CommsProviderShow"],
} as const;
const directory = dirname(fileURLToPath(import.meta.url));
const legacy = import.meta.glob("../../../apps/comms-overview/src/*.vue", {
  eager: true,
  import: "default",
});

test("historical views delegate to the exact module-owned component", () => {
  for (const names of Object.values(features)) {
    for (const name of names) {
      const key = "../../../apps/comms-overview/src/" + name + ".vue";
      expect(legacy[key]).toBe(communications[name]);
      const adapter = readFileSync(resolve(directory, key), "utf8");
      expect(adapter).toContain('from "@cadence/communications"');
      expect(adapter).toContain("export default " + name + ";");
      expect(adapter).not.toContain("<template>");
    }
  }
});

test("domain source cannot depend on delivery packages or sibling feature internals", () => {
  for (const file of readdirSync(directory, { recursive: true, encoding: "utf8" })) {
    if (!/\.(vue|ts)$/.test(file) || /\.(test|test-support)\./.test(file)) continue;
    const absolute = resolve(directory, file);
    const source = readFileSync(absolute, "utf8");
    const feature = file.split(sep)[0] === "features" ? file.split(sep)[1] : undefined;
    for (const match of source.matchAll(/(?:from\s*|import\s*\()["']([^"']+)["']/g)) {
      const specifier = match[1];
      expect(specifier, file).not.toMatch(/@cadence\/(?:plugin-host|.*-plugin)(?:\/|$)/);
      if (!required(specifier).startsWith(".")) continue;
      const target = relative(directory, resolve(dirname(absolute), required(specifier)));
      expect(target.startsWith(".."), file + " -> " + specifier).toBe(false);
      if (feature && target.startsWith("features" + sep)) {
        expect(target.split(sep)[1], file + " -> " + specifier).toBe(feature);
      }
    }
  }
});

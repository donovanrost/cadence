import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(testDirectory, "../..");
const workspaceRoot = resolve(appRoot, "../..");

const smokeSource = await readFile(resolve(testDirectory, "federation_browser_smoke.mjs"), "utf8");
const appMix = await readFile(resolve(appRoot, "mix.exs"), "utf8");
const workspaceMix = await readFile(resolve(workspaceRoot, "mix.exs"), "utf8");
const publicationCheck = await readFile(
  resolve(workspaceRoot, "frontend/tools/production-publication-output-check.mjs"),
  "utf8",
);
const frontendPackage = JSON.parse(
  await readFile(resolve(workspaceRoot, "frontend/package.json"), "utf8"),
);

for (const contract of [
  "class CdpClient",
  "Network.enable",
  "Network.responseReceived",
  "Network.loadingFailed",
  "Network.getResponseBody",
  "Runtime.consoleAPICalled",
  "Runtime.exceptionThrown",
  "REMOTE READY",
  "mf-manifest",
  "published remote chunks",
  "#packet-bindings-submit",
  "save_packet_bindings",
  "canonical query refresh",
  "retained selection",
  "federation_browser_smoke passed",
]) {
  assert.ok(smokeSource.includes(contract), `federation smoke source contract missing ${contract}`);
}

assert.match(appMix, /"test\.browser\.federation"/);
assert.match(appMix, /"assets\.deploy"/);
assert.match(appMix, /federation_browser_smoke_test\.exs/);
assert.match(workspaceMix, /"test\.browser\.federation": :test/);
assert.match(workspaceMix, /"test\.browser\.federation"/);
assert.match(publicationCheck, /application-host/);
assert.match(publicationCheck, /comms-overview/);
assert.match(publicationCheck, /telemetry-decom/);
assert.equal(
  frontendPackage.scripts["test:browser:contract"],
  "node ../apps/cadence_web/assets/test/federation_browser_smoke_contract_test.mjs",
);

console.log("federation_browser_smoke_contract passed");

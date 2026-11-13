// Producer-contract coverage for CI: fails unless every consumer listed in
// frontend/tools/producer-contracts.json executed with its producer's fixture somewhere in the
// test shards. Each shard writes CADENCE_PRODUCER_FIXTURE_LEDGER and uploads it; this reads every
// downloaded ledger under the given directory.
//
// Usage: node scripts/ci/producer_coverage.mjs <ledger-directory>
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  assertProducerCoverage,
  producerContracts,
} from "../../frontend/tools/producer-contracts.mjs";

const directory = process.argv[2];
if (!directory) throw Error("usage: producer_coverage.mjs <ledger-directory>");

const ledgers = existsSync(directory)
  ? readdirSync(directory, { recursive: true })
      .map((entry) => join(directory, String(entry)))
      .filter((path) => statSync(path).isFile())
  : [];

const contracts = producerContracts();
assertProducerCoverage(
  contracts.map((entry) => entry.consumer),
  ledgers.map((path) => readFileSync(path, "utf8")).join("\n"),
);

console.log(
  `Producer coverage passed: all ${contracts.length} consumers executed with their producer's ` +
    `fixture across ${ledgers.length} shard ledgers.`,
);

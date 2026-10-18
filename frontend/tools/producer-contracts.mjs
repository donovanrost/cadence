import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "../..");

export function producerContracts() {
  /** @type {unknown} */
  const entries = JSON.parse(
    readFileSync(new URL("./producer-contracts.json", import.meta.url), "utf8"),
  );
  if (!Array.isArray(entries) || entries.length === 0)
    throw Error("Missing producer contract inventory");
  /** @type {unknown[]} */
  const items = entries;
  return items.map((entry) => {
    if (
      entry === null ||
      typeof entry !== "object" ||
      !("consumer" in entry) ||
      !("environment" in entry) ||
      !("producer" in entry) ||
      typeof entry.consumer !== "string" ||
      !/^(apps|modules)\/[\w/.-]+\.test\.ts$/.test(entry.consumer) ||
      typeof entry.environment !== "string" ||
      !/^CADENCE_[A-Z_]+$/.test(entry.environment) ||
      typeof entry.producer !== "string" ||
      !/^apps\/(cadence|cadence_web)\/test\/[\w/]+\.exs$/.test(entry.producer)
    ) {
      throw Error("Invalid producer contract inventory entry");
    }
    return { consumer: entry.consumer, environment: entry.environment, producer: entry.producer };
  });
}

/** @param {readonly string[]} expected @param {string} ledger */
export function assertProducerCoverage(expected, ledger) {
  const executed = new Set(ledger.split("\n").filter(Boolean));
  const missing = expected.filter((consumer) => !executed.has(consumer));
  if (missing.length) throw Error(`Producer consumers did not execute:\n${missing.join("\n")}`);
}

export function runProducerContracts() {
  const contracts = producerContracts();
  const temporary = mkdtempSync(join(tmpdir(), "cadence-producer-contracts-"));
  const ledger = join(temporary, "executed.txt");
  writeFileSync(ledger, "");
  try {
    for (const app of ["cadence", "cadence_web"]) {
      const prefix = `apps/${app}/`;
      const files = [
        ...new Set(
          contracts
            .filter((entry) => entry.producer.startsWith(prefix))
            .map((entry) => entry.producer.slice(prefix.length)),
        ),
      ];
      if (!files.length) throw Error(`No producer tests selected for ${app}`);
      const result = spawnSync("mix", ["test", ...files], {
        cwd: resolve(root, prefix),
        env: {
          ...process.env,
          MIX_ENV: "test",
          CADENCE_REQUIRE_PRODUCER_FIXTURES: "1",
          CADENCE_PRODUCER_FIXTURE_LEDGER: ledger,
        },
        stdio: "inherit",
      });
      if (result.error) throw result.error;
      if (result.status !== 0)
        throw Error(`${app} producer tests failed (${result.signal ?? result.status})`);
    }
    assertProducerCoverage(
      contracts.map((entry) => entry.consumer),
      readFileSync(ledger, "utf8"),
    );
    console.log(
      `Producer contracts passed: ${contracts.length} consumers executed with real Phoenix fixtures.`,
    );
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  runProducerContracts();
}

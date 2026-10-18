import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { producerFixture } from "../test-support/producer-fixture.ts";
import { assertProducerCoverage, producerContracts } from "./producer-contracts.mjs";

const consumer = "apps/host/src/consumer.test.ts";
const testModule = new URL(`../${consumer}`, import.meta.url).href;

void test("absent unit fixtures are explicitly unavailable and never readable", () => {
  const fixture = producerFixture("CADENCE_DOCUMENT", testModule, {});
  assert.equal(fixture.available, false);
  assert.throws(() => fixture.read(), /Missing producer fixture/);
  assert.throws(
    () =>
      producerFixture("CADENCE_DOCUMENT", testModule, {
        CADENCE_REQUIRE_PRODUCER_FIXTURES: "1",
      }),
    /Missing required producer fixture/,
  );
});

void test("the integration gate requires execution, not just fixture discovery or passing process status", () => {
  const temporary = mkdtempSync(join(tmpdir(), "cadence-fixture-gate-test-"));
  const ledger = join(temporary, "executed.txt");
  try {
    const fixture = producerFixture("CADENCE_DOCUMENT", testModule, {
      CADENCE_DOCUMENT: '{"data":"producer"}',
      CADENCE_REQUIRE_PRODUCER_FIXTURES: "1",
      CADENCE_PRODUCER_FIXTURE_LEDGER: ledger,
    });
    assert.equal(fixture.available, true);
    assert.throws(() => assertProducerCoverage([consumer], ""), /did not execute/);
    assert.equal(fixture.read(), '{"data":"producer"}');
    assertProducerCoverage([consumer], readFileSync(ledger, "utf8"));
    assert.throws(
      () => assertProducerCoverage([consumer, "missing"], readFileSync(ledger, "utf8")),
      /missing/,
    );
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

void test("the contract inventory names real consumers and producers and covers every fixture helper caller", async () => {
  const { glob } = await import("node:fs/promises");
  const root = new URL("../", import.meta.url);
  const contracts = producerContracts();
  const consumers = new Set(contracts.map((entry) => entry.consumer));
  assert.equal(consumers.size, contracts.length);
  for (const entry of contracts) {
    assert.ok(readFileSync(new URL(`../../${entry.producer}`, import.meta.url), "utf8").length);
    const source = readFileSync(new URL(entry.consumer, root), "utf8");
    assert.ok(source.includes(entry.environment));
    assert.ok(source.includes("test.skipIf(!producer.available)"));
  }
  for await (const file of glob("{apps,modules}/**/*.test.ts", {
    cwd: root,
    exclude: ["**/node_modules/**"],
  })) {
    const source = readFileSync(new URL(file, root), "utf8");
    if (source.includes("producerFixture("))
      assert.ok(consumers.has(file), `Unowned producer consumer: ${file}`);
  }
});

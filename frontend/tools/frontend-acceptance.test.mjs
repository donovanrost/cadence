import { jsonFixture, fixtureRecord, fixtureString } from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { test } from "node:test";

const metadata = jsonFixture(await readFile(new URL("../package.json", import.meta.url), "utf8"));

void test("the acceptance command stops after a failed required gate and preserves its exit status", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "cadence-acceptance-"));
  t.after(() => rm(directory, { force: true, recursive: true }));
  const stub = join(directory, "corepack");
  await writeFile(
    stub,
    `#!${process.execPath}\nconsole.log(process.argv.slice(2).join(" "));\nprocess.exit(process.argv.at(-1) === process.env.FAIL_GATE ? 73 : 0);\n`,
  );
  await chmod(stub, 0o755);
  for (const [gate, output] of [
    ["check", "pnpm check\n"],
    ["test", "pnpm check\npnpm test\n"],
    ["none", "pnpm check\npnpm test\n"],
  ]) {
    const result = spawnSync(fixtureString(fixtureRecord(metadata.scripts).verify), {
      shell: true,
      encoding: "utf8",
      env: { ...process.env, PATH: `${directory}${delimiter}${process.env.PATH}`, FAIL_GATE: gate },
    });
    assert.equal(result.status, gate === "none" ? 0 : 73, result.stderr);
    assert.equal(result.stdout, output);
  }
});

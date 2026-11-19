import { fixtureNumber, fixtureRecord, jsonFixture } from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { fileLineProblems, lineCount, MAX_LINES, sourceLineCounts } from "./file-lines.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));

/** The baseline's caps: `{ "<file>": { "lines": <cap>, "owner": "<who splits it>" } }`. */
async function caps() {
  const baseline = jsonFixture(
    await readFile(resolve(root, "tools/file-lines-baseline.json"), "utf8"),
  );
  return Object.fromEntries(
    Object.entries(baseline).map(([file, entry]) => [
      file,
      fixtureNumber(fixtureRecord(entry).lines),
    ]),
  );
}

// The 400-line rule (lead 11-16): the gate for every frontend source file. Long files wait in the
// baseline at their current length; they may only shrink, and leave it once they're split.
void test("frontend source files stay within 400 lines (shrink-only baseline)", async () => {
  const problems = fileLineProblems(await sourceLineCounts(root), await caps());
  assert.deepEqual(problems, [], problems.join("\n"));
});

void test("every baseline entry names an owner", async () => {
  const baseline = jsonFixture(
    await readFile(resolve(root, "tools/file-lines-baseline.json"), "utf8"),
  );
  for (const [file, entry] of Object.entries(baseline)) {
    const owner = fixtureRecord(entry).owner;
    assert.ok(typeof owner === "string" && owner !== "", `${file}: give it an owner`);
  }
});

void test("the checker names each way a file breaks the rule", () => {
  const long = MAX_LINES + 100;
  assert.deepEqual(
    fileLineProblems(
      {
        "apps/a/src/new.ts": MAX_LINES + 1,
        "apps/a/src/grew.ts": long + 1,
        "apps/a/src/shrank.ts": long - 1,
        "apps/a/src/split.ts": MAX_LINES,
        "apps/a/src/steady.ts": long,
        "apps/a/src/short.ts": 10,
      },
      {
        "apps/a/src/grew.ts": long,
        "apps/a/src/shrank.ts": long,
        "apps/a/src/split.ts": long,
        "apps/a/src/steady.ts": long,
        "apps/a/src/gone.ts": long,
      },
    ),
    [
      "apps/a/src/gone.ts: no longer exists; remove it from file-lines-baseline.json",
      `apps/a/src/grew.ts: grew to ${long + 1} lines (cap ${long}); split it instead`,
      `apps/a/src/new.ts: ${MAX_LINES + 1} lines, over ${MAX_LINES}; split it by concern`,
      `apps/a/src/shrank.ts: shrank to ${long - 1} lines; lower its cap in file-lines-baseline.json`,
      `apps/a/src/split.ts: ${MAX_LINES} lines, within ${MAX_LINES}; remove it from file-lines-baseline.json`,
    ],
  );
});

void test("lines are counted as wc -l counts them", () => {
  assert.equal(lineCount(""), 0);
  assert.equal(lineCount("a\n"), 1);
  assert.equal(lineCount("a\nb\n"), 2);
  assert.equal(lineCount("a\nb"), 1);
});

void test("tests, test support, generated and vendored files aren't counted", async () => {
  const counts = await sourceLineCounts(root);
  const files = Object.keys(counts);
  assert.ok(files.length > 100, "the walk found the source tree");
  assert.deepEqual(
    files.filter((f) => /\.test\.|\.test-support\.|\.generated\.|\/vendor\/|\.d\.ts$/.test(f)),
    [],
  );
  assert.ok(files.includes("apps/console/src/router/route-map.ts"));
});

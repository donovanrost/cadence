import {
  fixtureRows,
  fixtureString,
  fixtureRecord,
  fixtureNumber,
} from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const cli = resolve(root, "node_modules/@ast-grep/cli/ast-grep");

void test("structural rules discover real Vue scripts and report their original locations", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "cadence-structural-rules-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const fixtures = {
    "Captured.vue":
      '<script setup lang="ts">\nif (port?.captured) useCaptured(input, port);\n</script>\n',
    "Invalid.vue":
      '<script setup lang="ts">\nconst value = external as unknown as Model;\n</script>\n<template><div /></template>\n',
    "Legacy.vue": "<script setup>\nconst value = 1;\n</script>\n",
    "Valid.vue":
      '<script setup lang="ts">\n// external as unknown as Model\nconst text = "external as unknown as Model";\nconst value = { text } as const;\n</script>\n',
    "Static.vue": "<template><p>Static content</p></template>\n",
    "index.html": '<script type="module" src="/main.ts"></script>\n',
  };
  await Promise.all(
    Object.entries(fixtures).map(([file, text]) => writeFile(join(directory, file), text)),
  );
  const result = spawnSync(
    cli,
    ["scan", "--config", join(root, "sgconfig.yml"), "--json", directory],
    {
      cwd: root,
      encoding: "utf8",
    },
  );
  assert.equal(result.status, 1, result.stderr);
  const matches = fixtureRows(result.stdout)
    .map(({ file, ruleId, range }) => ({
      file: basename(fixtureString(file)),
      rule: fixtureString(ruleId),
      line: fixtureNumber(fixtureRecord(fixtureRecord(range).start).line) + 1,
    }))
    .sort((a, b) => a.file.localeCompare(b.file));
  assert.deepEqual(matches, [
    { file: "Captured.vue", rule: "no-captured-workflow-dispatch", line: 2 },
    { file: "Invalid.vue", rule: "no-double-assertion", line: 2 },
    { file: "Legacy.vue", rule: "vue-script-typescript", line: 1 },
  ]);
});

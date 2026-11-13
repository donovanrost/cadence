import {
  fixtureRows,
  fixtureString,
  fixtureRecord,
  fixtureNumber,
} from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
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

void test("scheduling boundary applies to real Vue scripts and permits transport adapters", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "cadence-schedule-boundary-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const feature = join(directory, "contact-scheduling");
  await mkdir(feature);
  const script = '<script setup lang="ts">\nawait port.execute("reserve", input);\n</script>\n';
  await writeFile(join(feature, "OpsContactSchedule.vue"), script);
  await writeFile(
    join(feature, "schedule-page-adapter.ts"),
    'await port.execute("reserve", input);',
  );
  const result = spawnSync(
    cli,
    ["scan", "--config", join(root, "sgconfig.yml"), "--json", directory],
    { cwd: root, encoding: "utf8" },
  );
  assert.equal(result.status, 1, result.stderr);
  const matches = fixtureRows(result.stdout);
  assert.equal(matches.length, 1);
  assert.equal(matches[0]?.ruleId, "scheduling-domain-api-only");
  assert.equal(basename(fixtureString(matches[0]?.file)), "OpsContactSchedule.vue");
});

// Typing plan §12B ratchet (director 11-13): a rule's not-yet-migrated ignores may only shrink.
// The baseline lists the files still allowed; nothing may be added to a rule's ignores.
void test("typing-migration ignore lists only shrink", async () => {
  const { readFile } = await import("node:fs/promises");
  const baseline = JSON.parse(
    await readFile(resolve(root, "ast-grep/migration-baselines.json"), "utf8"),
  );
  for (const rule of ["error-code-compared-as-text", "vocabulary-field-decoded-as-text"]) {
    const text = await readFile(resolve(root, `ast-grep/rules/${rule}.yml`), "utf8");
    const ignored = [...text.matchAll(/"(apps\/console\/src\/[^"*]+\.(?:ts|vue))"/g)].map(
      (m) => m[1],
    );
    const allowed = new Set(baseline[rule]);
    const added = ignored.filter((file) => !allowed.has(file));
    assert.deepEqual(added, [], `${rule}: these files were added to its ignores; migrate them instead`);
    assert.ok(
      ignored.length <= allowed.size,
      `${rule}: ${ignored.length} ignored files exceed the baseline of ${allowed.size}`,
    );
  }
});

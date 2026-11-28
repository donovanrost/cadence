import {
  fixtureArrayAt,
  fixtureRecordAt,
  jsonFixture,
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

// Typing plan §12B ratchet (director 11-13): a rule's not-yet-migrated ignores may only shrink.
// The baseline lists the files still allowed; nothing may be added to a rule's ignores.
void test("typing-migration ignore lists only shrink", async () => {
  const { readFile } = await import("node:fs/promises");
  const baseline = jsonFixture(
    await readFile(resolve(root, "ast-grep/migration-baselines.json"), "utf8"),
  );
  for (const rule of [
    "error-code-compared-as-text",
    "vocabulary-field-decoded-as-text",
    "word-map-keyed-by-text",
  ]) {
    const text = await readFile(resolve(root, `ast-grep/rules/${rule}.yml`), "utf8");
    const ignored = [...text.matchAll(/"(apps\/console\/src\/[^"*]+\.(?:ts|vue))"/g)].flatMap(
      (m) => (m[1] ? [m[1]] : []),
    );
    const allowed = new Set(fixtureArrayAt(baseline, rule).map(fixtureString));
    const added = ignored.filter((file) => !allowed.has(file));
    assert.deepEqual(
      added,
      [],
      `${rule}: these files were added to its ignores; migrate them instead`,
    );
    assert.ok(
      ignored.length <= allowed.size,
      `${rule}: ${ignored.length} ignored files exceed the baseline of ${allowed.size}`,
    );
  }
});

// Rule B (lead 11-15): a decoded token/string compared to a literal, whatever the field's name.
void test("decoded-text comparisons only fall (rule B ratchet)", async () => {
  const { readFile } = await import("node:fs/promises");
  const { countByFile, decodedTextCompared } = await import("./decoded-text-compared.mjs");
  const baseline = fixtureRecordAt(
    jsonFixture(await readFile(resolve(root, "ast-grep/migration-baselines.json"), "utf8")),
    "decoded-text-compared",
  );
  /** @param {string} file */
  const allowed = (file) => (file in baseline ? fixtureNumber(baseline[file]) : 0);
  const counts = countByFile(decodedTextCompared(resolve(root, "apps/console/tsconfig.app.json")));
  const over = Object.entries(counts)
    .filter(([file, n]) => n > allowed(file))
    .map(([file, n]) => `${file}: ${n} (baseline ${allowed(file)})`);
  assert.deepEqual(over, [], "decode these fields with known/knownText instead of comparing text");
});

void test("rule B fires on a decoded token compared to a literal, free-text or not", async (t) => {
  const { decodedTextCompared } = await import("./decoded-text-compared.mjs");
  const directory = await mkdtemp(join(tmpdir(), "cadence-decoded-text-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(
    join(directory, "tsconfig.json"),
    JSON.stringify({ compilerOptions: { strict: true, noEmit: true }, include: ["*.ts"] }),
  );
  await writeFile(
    join(directory, "case.ts"),
    [
      "type Reader<T> = { read(v: unknown): T };",
      "declare const d: {",
      "  token: Reader<string>;",
      "  string: Reader<string>;",
      "  nullable<T>(r: Reader<T>): Reader<T | null>;",
      '  known<const T extends string>(v: readonly T[]): Reader<T | "unrecognized">;',
      "  object<S>(s: S): Reader<{ [K in keyof S]: S[K] extends Reader<infer T> ? T : never }>;",
      "};",
      "type Decoded<R> = R extends Reader<infer T> ? T : never;",
      "const reader = d.object({",
      "  verdict: d.token,",
      "  // free-text: claimed open, but branched on below",
      "  action: d.nullable(d.string),",
      '  kind: d.known(["a", "b"] as const),',
      "  note: d.string,",
      "});",
      "declare const v: Decoded<typeof reader>;",
      'export const a = v.verdict === "met";',
      'export const b = v.kind === "a";',
      "// compared-as-text: a field path, an open set by design",
      'export const c = v.note === "x";',
      "export function f() {",
      "  switch (v.action) {",
      '    case "retried":',
      "      return 1;",
      "  }",
      "  return 0;",
      "}",
      "",
    ].join("\n"),
  );
  const hits = decodedTextCompared(join(directory, "tsconfig.json"));
  assert.deepEqual(
    hits.map(({ field, literal, freeText }) => ({ field, literal, freeText })),
    [
      { field: "verdict", literal: "met", freeText: false },
      { field: "action", literal: "retried", freeText: true },
    ],
  );
});

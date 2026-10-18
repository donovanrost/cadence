import { jsonFixture, fixtureRecord, fixtureArrayAt } from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import {
  assertWorkspaceCoverage,
  checkWorkspace,
  discoverTypecheckProjects,
} from "./typecheck-workspace.mjs";

/** @param {import("node:test").TestContext} t */
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "cadence-typecheck-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const project = join(root, "modules", "example");
  await mkdir(join(project, "src"), { recursive: true });
  await writeFile(
    join(project, "package.json"),
    JSON.stringify({ name: "@cadence/example", private: true }),
  );
  await writeFile(
    join(root, "tsconfig.json"),
    JSON.stringify({
      files: [],
      references: [{ path: "./modules/example" }, { path: "./tsconfig.tools.json" }],
    }),
  );
  const config = {
    compilerOptions: {
      target: "ES2023",
      module: "ESNext",
      moduleResolution: "Bundler",
      strict: true,
      noUncheckedIndexedAccess: true,
      exactOptionalPropertyTypes: true,
      noEmit: true,
      skipLibCheck: true,
      types: [],
    },
    include: ["src/**/*.ts", "src/**/*.vue"],
  };
  await writeFile(join(project, "tsconfig.json"), JSON.stringify(config));
  await writeFile(join(project, "src", "index.ts"), "export const value = 1;\n");
  await mkdir(join(root, "tools"));
  await writeFile(join(root, "tools", "check.ts"), "export const version: number = 1;\n");
  await writeFile(
    join(root, "tsconfig.tools.json"),
    JSON.stringify({ ...config, include: ["tools/**/*.ts"] }),
  );
  return { root, project };
}

void test("new domain modules cannot silently escape type checking", async (t) => {
  const { root, project } = await fixture(t);
  await writeFile(join(project, "src", "Feature.vue"), "<template><p>Review</p></template>");
  assert.deepEqual(await discoverTypecheckProjects(root), [
    "modules/example",
    "tsconfig.tools.json",
  ]);
  await rm(join(project, "tsconfig.json"));
  await assert.rejects(discoverTypecheckProjects(root), /modules\/example.*no tsconfig/);
});

void test("root references cannot omit or duplicate a discovered project", async (t) => {
  const { root } = await fixture(t);
  await writeFile(join(root, "tsconfig.json"), JSON.stringify({ files: [], references: [] }));
  await assert.rejects(discoverTypecheckProjects(root), /every workspace/);
  await writeFile(
    join(root, "tsconfig.json"),
    JSON.stringify({
      files: [],
      references: [
        { path: "modules/example" },
        { path: "modules/example" },
        { path: "tsconfig.tools.json" },
      ],
    }),
  );
  await assert.rejects(discoverTypecheckProjects(root), /exactly once/);
});

void test("CSS-only packages need no artificial TypeScript project", async (t) => {
  const { root } = await fixture(t);
  const tokens = join(root, "packages", "tokens");
  await mkdir(tokens, { recursive: true });
  await writeFile(join(tokens, "package.json"), JSON.stringify({ name: "@cadence/tokens" }));
  await writeFile(join(tokens, "theme.css"), ":root { --color: red; }");
  assert.deepEqual(await discoverTypecheckProjects(root), [
    "modules/example",
    "tsconfig.tools.json",
  ]);
});

void test("the actual compiler rejects invalid Vue template types and accepts their repair", async (t) => {
  const { root, project } = await fixture(t);
  const req = createRequire(resolve(import.meta.dirname, "../apps/host/package.json"));
  await mkdir(join(project, "node_modules"));
  await symlink(
    dirname(req.resolve("vue/package.json")),
    join(project, "node_modules", "vue"),
    "dir",
  );
  const component = join(project, "src", "Feature.vue");
  await writeFile(
    component,
    '<script setup lang="ts">const props = defineProps<{ count: number }>();</script><template><p>{{ props.count.toUpperCase() }}</p></template>',
  );
  const invalid = await checkWorkspace(root);
  assert.notEqual(invalid.status, 0);
  assert.match(invalid.stdout, /toUpperCase.*number/);
  await writeFile(
    component,
    '<script setup lang="ts">const props = defineProps<{ count: number }>();</script><template><p>{{ props.count.toFixed(0) }}</p></template>',
  );
  const valid = await checkWorkspace(root);
  assert.equal(valid.status, 0, valid.stdout + valid.stderr);
});

void test("JavaScript, tests and root helpers cannot be hidden by unused configs", async (t) => {
  const { root, project } = await fixture(t);
  const projects = await discoverTypecheckProjects(root);
  await assertWorkspaceCoverage(root, projects);
  await writeFile(join(project, "src", "unchecked.test.mjs"), "export const unchecked = 1;\n");
  await writeFile(
    join(project, "tsconfig.unused.json"),
    JSON.stringify({
      compilerOptions: { allowJs: true, checkJs: true, strict: true },
      include: ["src/**/*.mjs"],
    }),
  );
  await assert.rejects(assertWorkspaceCoverage(root, projects), /unchecked\.test\.mjs/);
  const configPath = join(project, "tsconfig.json");
  const config = jsonFixture(await readFile(configPath, "utf8"));
  fixtureRecord(config.compilerOptions).allowJs = true;
  fixtureArrayAt(config, "include").push("src/**/*.mjs");
  await writeFile(configPath, JSON.stringify(config));
  await assert.rejects(assertWorkspaceCoverage(root, projects), /JavaScript requires checkJs/);
  fixtureRecord(config.compilerOptions).checkJs = true;
  await writeFile(configPath, JSON.stringify(config));
  await assertWorkspaceCoverage(root, projects);
  await mkdir(join(root, "test-support"));
  await writeFile(join(root, "test-support", "helper.ts"), "export const helper = 1;\n");
  await assert.rejects(assertWorkspaceCoverage(root, projects), /test-support\/helper\.ts/);
});

void test("effective strict options cannot be weakened by a leaf project", async (t) => {
  const { root, project } = await fixture(t);
  const projects = await discoverTypecheckProjects(root);
  const configPath = join(project, "tsconfig.json");
  const config = jsonFixture(await readFile(configPath, "utf8"));
  fixtureRecord(config.compilerOptions).noUncheckedIndexedAccess = false;
  await writeFile(configPath, JSON.stringify(config));
  await assert.rejects(
    assertWorkspaceCoverage(root, projects),
    /must enable noUncheckedIndexedAccess/,
  );
  fixtureRecord(config.compilerOptions).noUncheckedIndexedAccess = true;
  fixtureRecord(config.compilerOptions).noCheck = true;
  await writeFile(configPath, JSON.stringify(config));
  await assert.rejects(assertWorkspaceCoverage(root, projects), /cannot enable noCheck/);
});

void test("JavaScript-only packages require a checked project", async (t) => {
  const { root } = await fixture(t);
  const project = join(root, "packages", "untyped");
  await mkdir(project, { recursive: true });
  await writeFile(join(project, "package.json"), JSON.stringify({ name: "@cadence/untyped" }));
  await writeFile(join(project, "index.js"), "export const value = 1;\n");
  await assert.rejects(discoverTypecheckProjects(root), /JavaScript.*no tsconfig/);
});

void test("the real compiler rejects an invalid checked JavaScript test", async (t) => {
  const { root, project } = await fixture(t);
  const configPath = join(project, "tsconfig.json");
  const config = jsonFixture(await readFile(configPath, "utf8"));
  Object.assign(fixtureRecord(config.compilerOptions), { allowJs: true, checkJs: true });
  fixtureArrayAt(config, "include").push("src/**/*.mjs");
  await writeFile(configPath, JSON.stringify(config));
  await writeFile(
    join(project, "src", "broken.test.mjs"),
    "const count = 1; count.toUpperCase();\n",
  );
  const result = await checkWorkspace(root);
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /broken\.test\.mjs.*toUpperCase/);
});

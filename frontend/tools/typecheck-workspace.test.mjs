import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, symlink, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { checkWorkspace, discoverTypecheckProjects } from "./typecheck-workspace.mjs";

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
      noEmit: true,
      skipLibCheck: true,
      types: [],
    },
    include: ["src/**/*.ts", "src/**/*.vue"],
  };
  await writeFile(join(project, "tsconfig.json"), JSON.stringify(config));
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

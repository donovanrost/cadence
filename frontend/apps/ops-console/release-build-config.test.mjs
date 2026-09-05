import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import test from "node:test";

const appRoot = resolve(import.meta.dirname);

async function sourceFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...(await sourceFiles(path)));
    else if (/\.(ts|vue|js)$/.test(entry.name)) files.push(path);
  }
  return files;
}

test("keeps the Ops release graph independent from Phoenix local Vue assets", async () => {
  const files = await sourceFiles(join(appRoot, "src"));
  const source = await Promise.all(files.map((path) => readFile(path, "utf8")));
  const forbidden = ["@cadence/cadence-web-vue", "apps/cadence_web/assets/vue", 'from "live_vue"'];

  for (const text of source) {
    for (const importPath of forbidden) assert.equal(text.includes(importPath), false, importPath);
  }
});

test("pins the release identity and Phoenix publication path", async () => {
  const federation = await readFile(join(appRoot, "module-federation.config.ts"), "utf8");
  const vite = await readFile(join(appRoot, "vite.config.ts"), "utf8");
  const phoenix = await readFile(join(appRoot, "vite.phoenix.config.ts"), "utf8");

  assert.match(federation, /name:\s*["']cadence_ops_console["']/);
  assert.match(federation, /"\.\/Application":\s*["']\.\/src\/federated-application\.ts["']/);
  assert.match(vite, /application-host\/ops-console/);
  assert.match(phoenix, /application-host\/ops-console/);
});

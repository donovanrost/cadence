import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { integrationRequire } from "./reka_adapter_test_support.mjs";

const baseCommit = "4f98922febb2d9de5f63d025326c8026decb4f26";
const pinnedNode =
  "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node";
const repositoryRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../.."
);
const importLine =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n';
const componentOpening = "<CadenceBreadcrumbs>";
const componentClosing = "</CadenceBreadcrumbs>";
const nativeClosing = "</nav>";
const { compileScript, parse } = integrationRequire("@vue/compiler-sfc");

const callers = Object.freeze([
  Object.freeze({
    path: "apps/cadence_web/assets/vue/AdminOrganizationInvite.vue",
    openingIndent: 8,
    baseSha256:
      "84704d7bc7669aa57c25a30853c5672b1ab50d4b6f47cc4f58fe5f64c05b29cd",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/AdminOrganizationNew.vue",
    openingIndent: 8,
    baseSha256:
      "68ecb467fbb1857fdd3f663b3f8b37d64845e8ce516ea7992ee38564378563e8",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/AdminOrganizationShow.vue",
    openingIndent: 6,
    baseSha256:
      "6c7d0b6ae3e1cdb886d6066a03849b25048e803f2b9c193cbbadfdfccee5f355",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/AdminRuntime.vue",
    openingIndent: 10,
    baseSha256:
      "1e172d9c95b582301d17d3df6d9683db2a5c4cb1199ce93d710333cec139d188",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogDatabaseNew.vue",
    openingIndent: 10,
    baseSha256:
      "1955e48df1b63db6e42a11fa612c23d78b1aa0148caacfc39f64d7b772f75c4d",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogDatabaseShow.vue",
    openingIndent: 10,
    baseSha256:
      "9245017883a83e9a527a90ef67583f8fc2b5902409c1d37361a5c62a8427a191",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogImportRunShow.vue",
    openingIndent: 10,
    baseSha256:
      "c05aa918056aeded53c068cca5b2c1ce2958da7feddb6ba5ceb9c8bf97c2c737",
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/CatalogRevisionShow.vue",
    openingIndent: 8,
    baseSha256:
      "ae09c8b16e2c9abb9aa9d5ad09a458922403abeaea6c80447dbf860d5c3a66dd",
  }),
]);

const occurrences = (source, value) => source.split(value).length - 1;
const sha256 = (source) => createHash("sha256").update(source).digest("hex");

function nativeOpening(openingIndent) {
  const attributeIndent = " ".repeat(openingIndent + 2);

  return `<nav
${attributeIndent}aria-label="Breadcrumb"
${attributeIndent}class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
${" ".repeat(openingIndent)}>`;
}

function bodyBetween(source, opening, closing, label) {
  assert.equal(
    occurrences(source, opening),
    1,
    `${label} has one exact opening boundary`
  );
  assert.equal(
    occurrences(source, closing),
    1,
    `${label} has one exact closing boundary`
  );

  const bodyStart = source.indexOf(opening) + opening.length;
  const bodyEnd = source.indexOf(closing, bodyStart);
  assert.notEqual(bodyEnd, -1, `${label} closes after its opening boundary`);

  return source.slice(bodyStart, bodyEnd);
}

assert.equal(
  process.versions.node,
  "24.16.0",
  "migration proof requires Node 24.16.0"
);
assert.equal(
  realpathSync(process.execPath),
  realpathSync(pinnedNode),
  `migration proof must run with ${pinnedNode}`
);
assert.equal(
  callers.length,
  8,
  "the immutable ledger contains exactly eight callers"
);

for (const caller of callers) {
  const componentPath = resolve(repositoryRoot, caller.path);
  const source = readFileSync(componentPath, "utf8");
  const parentSource = execFileSync(
    "git",
    ["show", `${baseCommit}:${caller.path}`],
    {
      cwd: repositoryRoot,
      encoding: "utf8",
    }
  );
  const callerNativeOpening = nativeOpening(caller.openingIndent);

  assert.equal(
    occurrences(source, importLine),
    1,
    `${caller.path} imports breadcrumbs once`
  );
  assert.equal(
    source.match(/^import CadenceBreadcrumbs\b/gm)?.length,
    1,
    `${caller.path} has one breadcrumbs import declaration`
  );
  assert.equal(
    source.match(/<CadenceBreadcrumbs\b/g)?.length,
    1,
    `${caller.path} opens one breadcrumbs wrapper`
  );
  assert.equal(
    occurrences(source, componentOpening),
    1,
    `${caller.path} uses the transparent slot opening without props`
  );
  assert.equal(
    occurrences(source, componentClosing),
    1,
    `${caller.path} closes one breadcrumbs wrapper`
  );
  assert.doesNotMatch(
    source,
    /<nav(?:\s|>)/,
    `${caller.path} has no residual native nav`
  );
  assert.doesNotMatch(
    source,
    /<CadenceBreadcrumbs\b[^>]*\b(?:v-bind:|:)?breadcrumbs\s*=/,
    `${caller.path} does not move caller-owned breadcrumb data into a DTO prop`
  );

  assert.equal(
    sha256(parentSource),
    caller.baseSha256,
    `${caller.path} pins the immutable ${baseCommit} bytes`
  );
  assert.equal(
    bodyBetween(
      source,
      componentOpening,
      componentClosing,
      `${caller.path} wrapper`
    ),
    bodyBetween(
      parentSource,
      callerNativeOpening,
      nativeClosing,
      `${caller.path} parent nav`
    ),
    `${caller.path} keeps every caller-owned breadcrumb body byte-for-byte in place`
  );

  const reconstructed = source
    .replace(importLine, "")
    .replace(componentOpening, callerNativeOpening)
    .replace(componentClosing, nativeClosing);

  assert.doesNotMatch(
    reconstructed,
    /CadenceBreadcrumbs/,
    `${caller.path} reconstruction peels only the newest import and wrapper`
  );
  assert.equal(
    sha256(reconstructed),
    caller.baseSha256,
    `${caller.path} reconstructs the frozen ${baseCommit} SHA-256`
  );
  assert.equal(
    reconstructed,
    parentSource,
    `${caller.path} reconstructs ${baseCommit} byte-for-byte`
  );

  const parsed = parse(source, { filename: componentPath });
  assert.deepEqual(
    parsed.errors,
    [],
    `${caller.path} parses with the pinned Vue compiler`
  );
  assert.ok(
    parsed.descriptor.scriptSetup,
    `${caller.path} retains its script setup block`
  );
  assert.ok(
    parsed.descriptor.template,
    `${caller.path} retains its template block`
  );
  assert.doesNotThrow(
    () =>
      compileScript(parsed.descriptor, {
        id: `breadcrumb-admin-catalog-${caller.path}`,
        inlineTemplate: true,
      }),
    `${caller.path} compiles as an actual SFC`
  );
}

console.log(
  `breadcrumb_admin_catalog_migration_test passed (${callers.length} callers reconstruct ${baseCommit})`
);

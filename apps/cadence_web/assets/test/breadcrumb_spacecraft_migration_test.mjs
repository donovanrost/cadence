#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  expectedNodeVersion,
  integrationRequire,
} from "./reka_adapter_test_support.mjs";

const pinnedNode =
  "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node";
const parent = "4f98922febb2d9de5f63d025326c8026decb4f26";
const testDirectory = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(testDirectory, "../../../..");
const componentImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n';
const detailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n';
const navClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60";
const { compileScript, compileTemplate, parse } =
  integrationRequire("@vue/compiler-sfc");

assert.equal(process.execPath, pinnedNode);
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `spacecraft breadcrumb migration contracts use pinned Node ${expectedNodeVersion}`
);

const fixtures = Object.freeze([
  Object.freeze({
    filename: "SpacecraftCommanding.vue",
    indent: "          ",
    parentSha256:
      "846d46944e9bf1931719a57a5b815e7e64c4c9eefb013c8b0a43c85199cdaffe",
  }),
  Object.freeze({
    filename: "SpacecraftEdit.vue",
    indent: "          ",
    parentSha256:
      "d838c7a8884613dc7500ad2eb5bc58f04f282ea1468abbe806a52c6baf373fd9",
  }),
  Object.freeze({
    filename: "SpacecraftNew.vue",
    indent: "          ",
    parentSha256:
      "5b90aee8743ee8588e39b38eb8aae0c0effa38ebaaae3fcfe52b2011b11ecaf2",
  }),
  Object.freeze({
    filename: "SpacecraftReadiness.vue",
    indent: "          ",
    parentSha256:
      "3bba363a0fe5c980aaa29bab5bd24be239ff18b3686e1b4e6a42adffe0612729",
  }),
  Object.freeze({
    filename: "SpacecraftRouting.vue",
    indent: "          ",
    parentSha256:
      "996eeea14e3de24143c89382e67458cb388b538b7e9db6659598f91e3e433c93",
  }),
  Object.freeze({
    filename: "SpacecraftShow.vue",
    indent: "          ",
    parentSha256:
      "1a87e95b77a494ce16f788ac179c2f6f8631c787015ea6250996cfa48216da54",
  }),
  Object.freeze({
    filename: "SpacecraftTelemetryDecom.vue",
    indent: "          ",
    parentSha256:
      "57656051b4a0e6fb9918889b2d2ba861877f8ee7efc7073986a931a101ff17b8",
  }),
  Object.freeze({
    filename: "SpacecraftTypeNew.vue",
    indent: "          ",
    parentSha256:
      "ee750dd6715114d0f8aef1040dd0b15bb6622a1b58fb7553427104e0ab09a71d",
  }),
  Object.freeze({
    filename: "SpacecraftTypeShow.vue",
    indent: "        ",
    parentSha256:
      "03ed0ec37f2fe0c7f3e273f44c363471a0f4232a13dfdb4bf733ea19f5aea1d3",
  }),
]);

assert.equal(
  fixtures.length,
  9,
  "the spacecraft breadcrumb cohort has exactly nine callers"
);
assert.equal(
  new Set(fixtures.map(({ filename }) => filename)).size,
  fixtures.length,
  "every spacecraft breadcrumb caller is inventoried exactly once"
);

const occurrences = (source, fragment) => source.split(fragment).length - 1;
const sha256 = (source) => createHash("sha256").update(source).digest("hex");

const peelCadenceDetailsFrames = (source, expectedCount, label) => {
  const expectedImportCount = expectedCount > 0 ? 1 : 0;

  assert.equal(occurrences(source, detailsFrameImport), expectedImportCount, `${label} details import count`);
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`);
  assert.equal(occurrences(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`);

  const peeled = source
    .replace(detailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>");

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/);
  return peeled;
};

const replaceExactlyOnce = (source, migrated, parentSource, label) => {
  assert.equal(occurrences(source, migrated), 1, label);
  return source.replace(migrated, parentSource);
};

const boundaryBody = (source, opening, closing, label) => {
  assert.equal(occurrences(source, opening), 1, `${label} opening count`);
  assert.equal(occurrences(source, closing), 1, `${label} closing count`);

  const start = source.indexOf(opening) + opening.length;
  const end = source.indexOf(closing, start);
  assert.notEqual(end, -1, `${label} closing follows its opening`);
  return source.slice(start, end);
};

for (const fixture of fixtures) {
  const caller = `apps/cadence_web/assets/vue/${fixture.filename}`;
  const componentPath = resolve(repoRoot, caller);
  const source = await readFile(componentPath, "utf8");
  const parentSource = execFileSync(
    "git",
    ["-C", repoRoot, "show", `${parent}:${caller}`],
    {
      encoding: "utf8",
    }
  );
  const wrapperOpening = `${fixture.indent}<CadenceBreadcrumbs>`;
  const wrapperClosing = `${fixture.indent}</CadenceBreadcrumbs>`;
  const nativeOpening = `${fixture.indent}<nav
${fixture.indent}  aria-label="Breadcrumb"
${fixture.indent}  class="${navClass}"
${fixture.indent}>`;
  const nativeClosing = `${fixture.indent}</nav>`;

  assert.equal(
    sha256(parentSource),
    fixture.parentSha256,
    `${fixture.filename} keeps the frozen ${parent} parent SHA-256`
  );
  assert.equal(
    occurrences(source, componentImport),
    1,
    `${fixture.filename} imports the wrapper once`
  );
  assert.equal(
    source.match(/^import CadenceBreadcrumbs\b/gm)?.length,
    1,
    `${fixture.filename} has exactly one CadenceBreadcrumbs import declaration`
  );
  assert.equal(
    occurrences(source, "<CadenceBreadcrumbs"),
    1,
    `${fixture.filename} has exactly one wrapper opening`
  );
  assert.equal(
    occurrences(source, "</CadenceBreadcrumbs>"),
    1,
    `${fixture.filename} has exactly one wrapper closing`
  );
  assert.doesNotMatch(
    source,
    /<nav\b[^>]*\baria-label="Breadcrumb"[^>]*>/s,
    `${fixture.filename} has no residual native Breadcrumb nav`
  );
  assert.doesNotMatch(
    source,
    /<CadenceBreadcrumbs\b[^>]*\b:?breadcrumbs\s*=/s,
    `${fixture.filename} passes no breadcrumb DTO prop`
  );
  assert.equal(
    boundaryBody(
      source,
      wrapperOpening,
      wrapperClosing,
      `${fixture.filename} wrapper`
    ),
    boundaryBody(
      parentSource,
      nativeOpening,
      nativeClosing,
      `${fixture.filename} parent nav`
    ),
    `${fixture.filename} keeps every caller-owned breadcrumb child byte-for-byte in place`
  );

  const reconstructed = replaceExactlyOnce(
    replaceExactlyOnce(
      replaceExactlyOnce(
        peelCadenceDetailsFrames(
          source,
          fixture.filename === "SpacecraftShow.vue" ? 1 : 0,
          fixture.filename
        ),
        componentImport,
        "",
        `${fixture.filename} import reconstruction`
      ),
      wrapperOpening,
      nativeOpening,
      `${fixture.filename} opening reconstruction`
    ),
    wrapperClosing,
    nativeClosing,
    `${fixture.filename} closing reconstruction`
  );

  assert.doesNotMatch(
    reconstructed,
    /CadenceBreadcrumbs/,
    `${fixture.filename} reconstruction peels only the newest breadcrumb layer`
  );
  assert.equal(
    reconstructed,
    parentSource,
    `${fixture.filename} reconstructs ${parent} byte-for-byte`
  );
  assert.equal(
    sha256(reconstructed),
    fixture.parentSha256,
    `${fixture.filename} reconstruction preserves its frozen parent SHA-256`
  );

  const parsed = parse(source, { filename: componentPath });
  assert.deepEqual(
    parsed.errors,
    [],
    `${fixture.filename} parses with the pinned Vue compiler`
  );
  assert.ok(
    parsed.descriptor.scriptSetup,
    `${fixture.filename} keeps its script setup block`
  );
  assert.ok(
    parsed.descriptor.template,
    `${fixture.filename} keeps its template block`
  );

  const id = `breadcrumb-spacecraft-${fixture.filename}`;
  const compiledScript = compileScript(parsed.descriptor, { id });
  const compiledTemplate = compileTemplate({
    source: parsed.descriptor.template.content,
    filename: componentPath,
    id,
  });

  assert.match(compiledScript.content, /defineComponent|_defineComponent/);
  assert.deepEqual(
    compiledTemplate.errors,
    [],
    `${fixture.filename} template compiles`
  );
  assert.match(compiledTemplate.code, /render|_sfc_render/);
}

console.log(
  `breadcrumb_spacecraft_migration_test passed (${fixtures.length} compiled callers, exact ${parent} reconstructions)`
);

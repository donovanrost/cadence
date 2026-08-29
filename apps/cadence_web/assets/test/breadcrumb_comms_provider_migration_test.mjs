#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  expectedNodeVersion,
  integrationRequire,
} from "./reka_adapter_test_support.mjs";

const pinnedNode =
  "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node";
const parent = "4f98922febb2d9de5f63d025326c8026decb4f26";
const repositoryRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../.."
);
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n';
const detailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n';
const wrapperOpening = "<CadenceBreadcrumbs>";
const wrapperClosing = "</CadenceBreadcrumbs>";
const nativeClosing = "</nav>";
const navClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60";
const { compileScript, compileTemplate, parse } =
  integrationRequire("@vue/compiler-sfc");

assert.equal(process.execPath, pinnedNode);
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `breadcrumb migration contracts use pinned Node ${expectedNodeVersion}`
);

const fixtures = Object.freeze([
  Object.freeze({
    filename: "CommsGroundStationForm.vue",
    indentation: 10,
    parentSha256:
      "c48517e038041a653dc7e30c787071a27d1710480590e0edc967a6a5b13f391a",
  }),
  Object.freeze({
    filename: "CommsGroundStationShow.vue",
    indentation: 10,
    parentSha256:
      "b8fb1dda3a8c78f1c020257df0af05252bcc98fc682dd90a992da47eeac71510",
  }),
  Object.freeze({
    filename: "CommsProviderNew.vue",
    indentation: 8,
    parentSha256:
      "3749036a326868159fb9fa24676e82144c886d9e465cb87f126e684f63b6af70",
  }),
  Object.freeze({
    filename: "CommsProviderShow.vue",
    indentation: 10,
    parentSha256:
      "edeccd16af8553cf3a696fd1220375fbde1ca6091110d9288205256bbdd0faa8",
  }),
  Object.freeze({
    filename: "CommsRoutingNew.vue",
    indentation: 10,
    parentSha256:
      "77a4a113122aeb37713f94ede2238e572adcdb6d5e0af2ebc1d29503b21f8c29",
  }),
  Object.freeze({
    filename: "CommsRoutingShow.vue",
    indentation: 10,
    parentSha256:
      "98e5fad0f72701601f4319da38d87eb976cb34e0210b70913b6be8fa8ad3b411",
  }),
  Object.freeze({
    filename: "CommsTransportNew.vue",
    indentation: 10,
    parentSha256:
      "ecb5b7ec66cd67acac5df776f0c870cbdda91e89ef093cb2905ab800fcb221ee",
  }),
  Object.freeze({
    filename: "CommsTransportShow.vue",
    indentation: 8,
    parentSha256:
      "bf45c23e7c225a5725591abbf609549d51c3f2af9d846a26b3c0c36e3ccb2a4c",
  }),
  Object.freeze({
    filename: "CommsValidation.vue",
    indentation: 10,
    parentSha256:
      "766788d43de5e072703e4fca3bb9ca2a3b73c385d8ebe2970a2477845073a87d",
  }),
  Object.freeze({
    filename: "MissionNew.vue",
    indentation: 10,
    parentSha256:
      "5dc414e66073e878a1cf520fd6f0babf2ad61f4c0bf5c6f57a4418bae1c0af6e",
  }),
  Object.freeze({
    filename: "ProviderAccountNew.vue",
    indentation: 8,
    parentSha256:
      "56e53133a92db766f8c648e629f29487b2c4284c41256398649d016a0258c11e",
  }),
  Object.freeze({
    filename: "ProviderAccountShow.vue",
    indentation: 10,
    parentSha256:
      "1ebe60edd69925a3107a4af662df8d120a83a59890622a8dd8c45d88d5e35dba",
  }),
]);

const occurrences = (source, fragment) => source.split(fragment).length - 1;
const sha256 = (source) => createHash("sha256").update(source).digest("hex");
const detailsFrameCounts = Object.freeze({
  "CommsProviderShow.vue": 1,
  "CommsRoutingShow.vue": 1,
  "CommsTransportNew.vue": 1,
  "CommsTransportShow.vue": 1,
  "ProviderAccountShow.vue": 1,
});

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

const nativeOpening = (indentation) => {
  const attributeIndentation = " ".repeat(indentation + 2);
  const closingIndentation = " ".repeat(indentation);

  return `<nav
${attributeIndentation}aria-label="Breadcrumb"
${attributeIndentation}class="${navClass}"
${closingIndentation}>`;
};

const replaceExact = (source, migrated, predecessor, expectedCount, label) => {
  assert.equal(occurrences(source, migrated), expectedCount, label);
  return source.split(migrated).join(predecessor);
};

const wrapperBody = (source, opening, closing, label) => {
  assert.equal(occurrences(source, opening), 1, `${label} opening count`);
  assert.equal(occurrences(source, closing), 1, `${label} closing count`);

  const bodyStart = source.indexOf(opening) + opening.length;
  const bodyEnd = source.indexOf(closing, bodyStart);
  assert.ok(bodyEnd > bodyStart, `${label} body boundary`);
  return source.slice(bodyStart, bodyEnd);
};

assert.equal(
  fixtures.length,
  12,
  "all twelve exclusively owned breadcrumb callers are inventoried"
);

let importerCount = 0;
let wrapperCount = 0;

for (const fixture of fixtures) {
  const repositoryPath = `apps/cadence_web/assets/vue/${fixture.filename}`;
  const componentPath = resolve(repositoryRoot, repositoryPath);
  const source = readFileSync(componentPath, "utf8");
  const parentSource = execFileSync(
    "git",
    ["-C", repositoryRoot, "show", `${parent}:${repositoryPath}`],
    { encoding: "utf8" }
  );
  const expectedNativeOpening = nativeOpening(fixture.indentation);

  assert.equal(
    sha256(parentSource),
    fixture.parentSha256,
    `${fixture.filename} retains its frozen parent SHA-256 at ${parent}`
  );
  assert.equal(
    occurrences(source, breadcrumbsImport),
    1,
    `${fixture.filename} imports CadenceBreadcrumbs exactly once`
  );
  assert.equal(
    source.match(/^import CadenceBreadcrumbs\b/gm)?.length ?? 0,
    1,
    `${fixture.filename} has one CadenceBreadcrumbs import declaration`
  );
  assert.equal(
    occurrences(source, wrapperOpening),
    1,
    `${fixture.filename} has one prop-free slot wrapper opening`
  );
  assert.equal(
    occurrences(source, wrapperClosing),
    1,
    `${fixture.filename} has one slot wrapper closing`
  );
  assert.equal(
    source.match(/<CadenceBreadcrumbs\b/g)?.length ?? 0,
    1,
    `${fixture.filename} has no unlisted breadcrumb wrapper`
  );
  assert.doesNotMatch(source, /<CadenceBreadcrumbs\b[^>]*\bbreadcrumbs\s*=/);
  assert.doesNotMatch(
    source,
    /<nav\b/,
    `${fixture.filename} has no residual native nav`
  );
  assert.doesNotMatch(source, /aria-label="Breadcrumb"/);

  const migratedBody = wrapperBody(
    source,
    wrapperOpening,
    wrapperClosing,
    `${fixture.filename} migrated breadcrumb`
  );
  const parentBody = wrapperBody(
    parentSource,
    expectedNativeOpening,
    nativeClosing,
    `${fixture.filename} parent breadcrumb`
  );

  assert.equal(
    sha256(migratedBody),
    sha256(parentBody),
    `${fixture.filename} preserves the breadcrumb body SHA-256`
  );
  assert.equal(
    migratedBody,
    parentBody,
    `${fixture.filename} keeps every breadcrumb child byte-for-byte in place`
  );
  assert.equal(occurrences(migratedBody, "<template"), 1);
  assert.equal(occurrences(migratedBody, "v-for="), 1);
  assert.equal(occurrences(migratedBody, ":key="), 1);
  assert.equal(occurrences(migratedBody, "v-if="), 2);
  assert.equal(occurrences(migratedBody, "<a"), 1);
  assert.equal(occurrences(migratedBody, ":href="), 1);
  assert.equal(occurrences(migratedBody, 'data-phx-link="redirect"'), 1);
  assert.equal(occurrences(migratedBody, 'data-phx-link-state="push"'), 1);
  assert.equal(occurrences(migratedBody, 'aria-hidden="true"'), 1);

  const reconstructed = replaceExact(
    replaceExact(
      replaceExact(
        peelCadenceDetailsFrames(
          source,
          detailsFrameCounts[fixture.filename] ?? 0,
          fixture.filename
        ),
        breadcrumbsImport,
        "",
        1,
        `${fixture.filename} import reconstruction`
      ),
      wrapperOpening,
      expectedNativeOpening,
      1,
      `${fixture.filename} opening reconstruction`
    ),
    wrapperClosing,
    nativeClosing,
    1,
    `${fixture.filename} closing reconstruction`
  );

  assert.doesNotMatch(reconstructed, /CadenceBreadcrumbs/);
  assert.equal(
    sha256(reconstructed),
    fixture.parentSha256,
    `${fixture.filename} reconstructs its exact parent SHA-256 by peeling only this migration`
  );
  assert.equal(
    reconstructed,
    parentSource,
    `${fixture.filename} reconstructs its parent source byte-for-byte`
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

  const id = `breadcrumb-comms-provider-${fixture.filename}`;
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

  importerCount += 1;
  wrapperCount += 1;
}

assert.equal(
  importerCount,
  12,
  "the cohort has exactly twelve CadenceBreadcrumbs importers"
);
assert.equal(
  wrapperCount,
  12,
  "the cohort has exactly twelve transparent slot wrappers"
);

console.log(
  "breadcrumb_comms_provider_migration_test passed (12 importers, 12 exact inverse reconstructions)"
);

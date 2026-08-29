import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"
import {peelCadenceOpsViewport} from "./ops_viewport_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const parent = "f9f36bb729e9f9abb1a2d01c3924bddf3d7eb99a"
const detailsImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `contact details migration uses pinned Node ${expectedNodeVersion}`,
)

const callers = Object.freeze([
  Object.freeze({
    file: "OpsContactRequirementNew.vue",
    roots: 1,
    parentSha256: "dc4d4523b460e5f25ded1405f4ef64f3030139acc8aede4a9cd54c8d891b3fad",
    excludedDescendants: Object.freeze({
      "<summary": 1,
      "<input": 4,
      "v-model=": 4,
    }),
  }),
  Object.freeze({
    file: "OpsContactRequirementTemplate.vue",
    roots: 2,
    parentSha256: "40a97c33faa08cded831ad19b2945946cd90b0d5c987202a500961633e0bf948",
    excludedDescendants: Object.freeze({
      "<summary": 2,
      "<input": 4,
      "v-model=": 4,
    }),
  }),
  Object.freeze({
    file: "OpsContactPlanShow.vue",
    roots: 2,
    parentSha256: "8451a70f4ed65d628a2a9711814e223f6f1a3735ae98abe4da11b3208fdf8791",
    excludedDescendants: Object.freeze({
      "<summary": 2,
      "<form": 1,
      "<textarea": 1,
      "<button": 1,
      "v-model=": 1,
    }),
  }),
  Object.freeze({
    file: "OpsContactSchedule.vue",
    roots: 1,
    parentSha256: "e653e28fea185a77ab2d255f1a43762de319bd61c024674b63f535130491b293",
    excludedDescendants: Object.freeze({
      "<summary": 1,
    }),
  }),
  Object.freeze({
    file: "OpsContactDetail.vue",
    roots: 1,
    parentSha256: "0d27cd38f5523f8ef0d5b7ed950cd597b1c93c27989f2363e0406604d8d21e92",
    excludedDescendants: Object.freeze({
      "<summary": 1,
      "<a": 1,
      "data-phx-link=": 1,
      "data-phx-link-state=": 1,
    }),
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const boundaries = (source, tag) =>
  [...source.matchAll(new RegExp(`(<${tag}\\b[^>]*>)([\\s\\S]*?)</${tag}>`, "g"))].map(
    (match) => Object.freeze({body: match[2], opening: match[1]}),
  )

assert.equal(callers.length, 5, "the owned contact cohort contains exactly five callers")
assert.equal(
  callers.reduce((total, caller) => total + caller.roots, 0),
  7,
  "the owned contact cohort contains exactly seven details roots",
)

for (const caller of callers) {
  const repositoryPath = `apps/cadence_web/assets/vue/${caller.file}`
  const componentPath = resolve(vueDirectory, caller.file)
  const source = peelCadenceInlineWarnings(
    peelCadenceOpsViewport(await readFile(componentPath, "utf8"), caller.file),
    caller.file,
  )
  const parentSource = execFileSync(
    "git",
    ["-C", repositoryRoot, "show", `${parent}:${repositoryPath}`],
    {encoding: "utf8"},
  )
  const migratedBoundaries = boundaries(source, "CadenceDetailsFrame")
  const parentBoundaries = boundaries(parentSource, "details")

  assert.equal(
    sha256(parentSource),
    caller.parentSha256,
    `${caller.file} retains its frozen parent SHA-256 at ${parent}`,
  )
  assert.equal(
    occurrences(source, detailsImport),
    1,
    `${caller.file} imports CadenceDetailsFrame exactly once`,
  )
  assert.equal(
    source.match(/^import CadenceDetailsFrame\b/gm)?.length ?? 0,
    1,
    `${caller.file} has one CadenceDetailsFrame import declaration`,
  )
  assert.equal(
    migratedBoundaries.length,
    caller.roots,
    `${caller.file} has exactly its inventoried wrapper openings`,
  )
  assert.equal(
    occurrences(source, "</CadenceDetailsFrame>"),
    caller.roots,
    `${caller.file} has exactly its inventoried wrapper closings`,
  )
  assert.equal(
    parentBoundaries.length,
    caller.roots,
    `${caller.file} parent has exactly its frozen native details roots`,
  )
  assert.doesNotMatch(source, /<details(?:\s|>)/, `${caller.file} has no residual native target`)

  for (const [index, migratedBoundary] of migratedBoundaries.entries()) {
    const parentBoundary = parentBoundaries[index]

    assert.equal(
      migratedBoundary.opening.replace(/^<CadenceDetailsFrame/, "<details"),
      parentBoundary.opening,
      `${caller.file} root ${index + 1} preserves every opening attribute byte-for-byte`,
    )
    assert.equal(
      migratedBoundary.body,
      parentBoundary.body,
      `${caller.file} root ${index + 1} preserves its caller-owned body byte-for-byte`,
    )
    assert.equal(
      sha256(migratedBoundary.body),
      sha256(parentBoundary.body),
      `${caller.file} root ${index + 1} preserves its caller-owned body SHA-256`,
    )
  }

  const migratedBodies = migratedBoundaries.map((boundary) => boundary.body).join("")
  const parentBodies = parentBoundaries.map((boundary) => boundary.body).join("")

  for (const [fragment, expectedCount] of Object.entries(caller.excludedDescendants)) {
    assert.equal(
      occurrences(migratedBodies, fragment),
      expectedCount,
      `${caller.file} keeps ${expectedCount} caller-owned ${fragment} exclusions`,
    )
    assert.equal(
      occurrences(parentBodies, fragment),
      expectedCount,
      `${caller.file} parent freezes ${expectedCount} caller-owned ${fragment} exclusions`,
    )
  }

  const reconstructed = source
    .replace(detailsImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(reconstructed, /CadenceDetailsFrame/)
  assert.equal(
    sha256(reconstructed),
    caller.parentSha256,
    `${caller.file} reconstructs its frozen parent SHA-256 by peeling only this migration`,
  )
  assert.equal(
    reconstructed,
    parentSource,
    `${caller.file} reconstructs parent ${parent} byte-for-byte`,
  )
}

const dom = installDom('<div id="details-contact-compile"></div>')
try {
  const compiledCallers = await Promise.all(
    callers.map((caller) => loadSfc(resolve(vueDirectory, caller.file))),
  )

  for (const [index, compiled] of compiledCallers.entries()) {
    assert.equal(typeof compiled.component, "object", `${callers[index].file} compiles to a component`)
    assert.ok(compiled.descriptor.scriptSetup, `${callers[index].file} keeps script setup`)
    assert.ok(compiled.descriptor.template, `${callers[index].file} keeps its actual template`)
  }
} finally {
  dom.window.close()
}

console.log(
  `details_contact_migration_test passed (5 actual SFCs, 7 roots, parent ${parent})`,
)

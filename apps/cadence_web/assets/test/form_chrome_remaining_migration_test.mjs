import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `remaining form-chrome migration contracts use pinned Node ${expectedNodeVersion}`,
)

const foundationBase = "9e3e7adfa9b673ae928bfa34c6ba977e5a64c1a4"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const actionImport = 'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"'
const actionWrapperClass = "flex items-center gap-3 border-t border-base-300/60 pt-5"

const foundations = Object.freeze([
  {
    file: "OpsContactPlanShow.vue",
    sha256: "4705f28ee4c3bc0a590e6db181c37b6e780192d7d37c5d0bb9b986faee2dd9e5",
    actionIndent: null,
    native: {buttons: 4, anchors: 2, inputs: 0, selects: 0, textareas: 3, hidden: 0, forms: 3},
    showContent: [
      "{{ page.header.heading }}",
      "{{ page.execution.heading }}",
      "{{ page.submission.heading }}",
      "{{ page.approval_evidence.heading }}",
      "{{ page.rationale.heading }}",
    ],
  },
  {
    file: "OpsContactRequirementShow.vue",
    sha256: "d47dbbd37e5798262464e30ae78220608f61c6eafbf383da4ea8f59c265130a4",
    actionIndent: null,
    native: {buttons: 3, anchors: 1, inputs: 0, selects: 0, textareas: 0, hidden: 0, forms: 0},
    showContent: [
      "{{ page.header.intent }}",
      "{{ page.planning.heading }}",
      "{{ page.opportunities.heading }}",
      "{{ page.journey.heading }}",
      "{{ page.versions.heading }}",
    ],
  },
  {
    file: "AdminOrganizationInvite.vue",
    sha256: "4bac43ea822f4df4df3aea3387d95d34f2e50d3946ae12074c7a0785b2f90f9c",
    actionIndent: "      ",
    native: {buttons: 1, anchors: 2, inputs: 4, selects: 1, textareas: 0, hidden: 1, forms: 1},
    showContent: [],
  },
  {
    file: "AdminOrganizationNew.vue",
    sha256: "76fe8a8f7a9940ddd80a2b1762fb03788b41365dc4edc5c271abbac28bb83a35",
    actionIndent: "      ",
    native: {buttons: 1, anchors: 2, inputs: 2, selects: 0, textareas: 0, hidden: 0, forms: 1},
    showContent: [],
  },
  {
    file: "MissionNew.vue",
    sha256: "9104fbebeba9ff9952a7fe0471401a9af4a3dee9dcb1d5621a0c2dd0cdd8fda1",
    actionIndent: "      ",
    native: {buttons: 1, anchors: 2, inputs: 2, selects: 0, textareas: 0, hidden: 0, forms: 1},
    showContent: [],
  },
  {
    file: "OpsDashboardNew.vue",
    sha256: "1a8769bbd84d14ec2a06f5522c474ffd6a4dc609606259725020845c741a2a45",
    actionIndent: "        ",
    native: {buttons: 1, anchors: 1, inputs: 2, selects: 0, textareas: 1, hidden: 0, forms: 1},
    showContent: [],
  },
])

const migratedCallSiteLedger = Object.freeze([
  "AdminOrganizationInvite.vue action row 1",
  "AdminOrganizationNew.vue action row 1",
  "MissionNew.vue action row 1",
  "OpsDashboardNew.vue action row 1",
])

const count = (source, pattern) => source.match(pattern)?.length ?? 0
const digest = (source) => createHash("sha256").update(source).digest("hex")
const escapePattern = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
const migratedCallSites = []

for (const foundation of foundations) {
  const source = await readFile(resolve(vueDirectory, foundation.file), "utf8")
  let reconstructedSource = source
  let reconstructedImports = 0
  let reconstructedActionRows = 0

  reconstructedSource = reconstructedSource.replace(
    new RegExp(`^${escapePattern(actionImport)}\\n`, "gm"),
    () => {
      reconstructedImports += 1
      return ""
    },
  )

  if (foundation.actionIndent === null) {
    assert.equal(
      reconstructedImports,
      0,
      `${foundation.file} has no form-action import to remove`,
    )
    assert.doesNotMatch(
      source,
      /<h2\b|CadenceFormSectionHeader/,
      `${foundation.file} contains no exact section-header shape at the immutable foundation base`,
    )
  } else {
    assert.equal(reconstructedImports, 1, `${foundation.file} has one exact form-action import`)

    const wrapperPattern = new RegExp(
      `^${foundation.actionIndent}<CadenceFormActions wrapper-class="${escapePattern(actionWrapperClass)}">\\n([\\s\\S]*?)\\n^${foundation.actionIndent}</CadenceFormActions>$`,
      "gm",
    )

    reconstructedSource = reconstructedSource.replace(wrapperPattern, (_match, controls) => {
      reconstructedActionRows += 1
      migratedCallSites.push(`${foundation.file} action row ${reconstructedActionRows}`)
      assert.equal(count(controls, /<button\b/g), 1, "the native submit button stays in the caller")
      assert.equal(count(controls, /<a\b/g), 1, "the native cancel anchor stays in the caller")
      assert.match(controls, /type="submit"/, "native submit semantics stay in the caller")
      assert.match(controls, /data-phx-link="redirect"/, "Phoenix redirect ownership stays in the caller")
      assert.match(controls, /data-phx-link-state="push"/, "Phoenix link state stays in the caller")

      return `${foundation.actionIndent}<div class="${actionWrapperClass}">
${controls}
${foundation.actionIndent}</div>`
    })

    assert.equal(reconstructedActionRows, 1, `${foundation.file} reconstructs one action row`)
  }

  assert.deepEqual(
    {
      buttons: count(source, /<button\b/g),
      anchors: count(source, /<a\b/g),
      inputs: count(source, /<input\b/g),
      selects: count(source, /<select\b/g),
      textareas: count(source, /<textarea\b/g),
      hidden: count(source, /type="hidden"/g),
      forms: count(source, /<form\b/g),
    },
    foundation.native,
    `${foundation.file} keeps every native control physically caller-owned`,
  )

  for (const content of foundation.showContent) {
    assert.ok(
      source.includes(content),
      `${foundation.file} keeps show-page content caller-owned: ${content}`,
    )
  }

  assert.equal(
    digest(reconstructedSource),
    foundation.sha256,
    `${foundation.file} reconstructs foundation base ${foundationBase} one-for-one`,
  )
}

assert.deepEqual(
  migratedCallSites,
  migratedCallSiteLedger,
  "every and only exact remaining form-chrome call site is inventoried",
)

console.log("form_chrome_remaining_migration_test passed")

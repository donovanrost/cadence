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
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const reconstructPageHeaderSource = (source) =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace(
      '<CadencePageHeaderFrame variant="ops">',
      '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")

const contactPlanPanels = [
  {
    currentOpen:
      '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
    originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
    headerClass: "border-b border-base-300 px-4 py-3",
  },
  {
    currentOpen:
      '        <CadencePanel\n          v-if="page.unsatisfied !== null"\n          :id="page.unsatisfied.id"\n          class="border border-warning/40 bg-warning/5"\n          header-class="border-b border-warning/30 px-4 py-3"\n        >',
    originalOpen:
      '        <section\n          v-if="page.unsatisfied !== null"\n          :id="page.unsatisfied.id"\n          class="border border-warning/40 bg-warning/5"\n        >',
    headerClass: "border-b border-warning/30 px-4 py-3",
  },
  {
    currentOpen:
      '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
    originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
    headerClass: "border-b border-base-300 px-4 py-3",
  },
  {
    currentOpen:
      '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
    originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
    headerClass: "border-b border-base-300 px-4 py-3",
  },
]

const occurrences = (source, needle) => source.split(needle).length - 1
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

const peelPanel = (source, panel, path) => {
  const panelIndent = panel.currentOpen.match(/^(\s*)<CadencePanel/)?.[1]
  assert.notEqual(panelIndent, undefined, `${path}: panel indentation is frozen`)
  const headerIndent = `${panelIndent}  `
  const pattern = new RegExp(
    `${escapeRegExp(panel.currentOpen)}\\n${escapeRegExp(headerIndent)}<template #header>([\\s\\S]*?)\\n${escapeRegExp(headerIndent)}</template>([\\s\\S]*?)\\n${escapeRegExp(panelIndent)}</CadencePanel>`,
  )
  const match = pattern.exec(source)

  assert.notEqual(match, null, `${path}: exact migrated panel boundary exists`)

  const replacement =
    `${panel.originalOpen}\n${headerIndent}<div class="${panel.headerClass}">` +
    `${match[1]}\n${headerIndent}</div>${match[2]}\n${panelIndent}</section>`

  return source.slice(0, match.index) + replacement + source.slice(match.index + match[0].length)
}

const reconstructContactPlanBase = (migratedSource) => {
  let source = migratedSource.replace(cadencePanelImport, "")

  for (const panel of contactPlanPanels) {
    source = peelPanel(source, panel, "OpsContactPlanShow.vue")
  }

  return source
}

const reconstructContactRequirementBase = (migratedSource, expectedPanels) => {
  let source = migratedSource.replace(cadencePanelImport, "")
  let reconstructedPanels = 0

  while (source.includes("<CadencePanel")) {
    const panelStart = source.indexOf("<CadencePanel")
    const lineStart = source.lastIndexOf("\n", panelStart) + 1
    const panelIndent = source.slice(lineStart, panelStart)
    const panelOpenEnd = source.indexOf(">", panelStart) + 1
    const panelOpen = source.slice(panelStart, panelOpenEnd)
    const inlineHeaderClass = panelOpen.match(/ header-class="([^"]+)">$/)
    const multilineHeaderClass = panelOpen.match(/\n([ \t]*)header-class="([^"]+)"\n[ \t]*>$/)

    assert.ok(
      inlineHeaderClass || multilineHeaderClass,
      "each CadencePanel opening must carry one reconstructable header-class",
    )

    const headerClass = inlineHeaderClass?.[1] ?? multilineHeaderClass[2]
    const baseOpen = inlineHeaderClass
      ? panelOpen
          .replace("<CadencePanel", "<section")
          .replace(` header-class="${headerClass}"`, "")
      : panelOpen
          .replace("<CadencePanel", "<section")
          .replace(`${multilineHeaderClass[1]}header-class="${headerClass}"\n`, "")
    const slotIndent = `${panelIndent}  `
    const slotOpen = `${slotIndent}<template #header>`
    const slotStart = source.indexOf(slotOpen, panelOpenEnd)
    const slotEnd = slotStart + slotOpen.length
    const slotClose = `\n${slotIndent}</template>`
    const slotCloseStart = source.indexOf(slotClose, slotEnd)
    const slotCloseEnd = slotCloseStart + slotClose.length
    const panelClose = `\n${panelIndent}</CadencePanel>`
    const panelCloseStart = source.indexOf(panelClose, slotCloseEnd)
    const panelCloseEnd = panelCloseStart + panelClose.length

    assert.notEqual(slotStart, -1, "each CadencePanel must open an immediate header slot")
    assert.notEqual(slotCloseStart, -1, "each CadencePanel header slot must close")
    assert.notEqual(panelCloseStart, -1, "each CadencePanel must close")

    source =
      source.slice(0, panelStart) +
      baseOpen +
      source.slice(panelOpenEnd, slotStart) +
      `${slotIndent}<div class="${headerClass}">` +
      source.slice(slotEnd, slotCloseStart) +
      `\n${slotIndent}</div>` +
      source.slice(slotCloseEnd, panelCloseStart) +
      `\n${panelIndent}</section>` +
      source.slice(panelCloseEnd)

    reconstructedPanels += 1
  }

  assert.equal(reconstructedPanels, expectedPanels, "all expected panels must reconstruct")
  assert.equal(occurrences(source, "CadencePanel"), 0, "reconstruction must remove CadencePanel")
  return source
}

const reconstructPanels = (source, file) => {
  if (file === "OpsContactPlanShow.vue") return reconstructContactPlanBase(source)
  if (file === "OpsContactRequirementShow.vue") {
    return reconstructContactRequirementBase(source, 4)
  }

  return source
}

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
  let reconstructedSource = reconstructPanels(reconstructPageHeaderSource(source), foundation.file)
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

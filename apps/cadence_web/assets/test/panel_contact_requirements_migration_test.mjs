import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const pinnedNodeVersion = "v24.16.0"
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const cadencePageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const cadencePageHeaderFrameOpen = '<CadencePageHeaderFrame variant="ops">'
const cadencePageHeaderFrameClose = "</CadencePageHeaderFrame>"
const opsPageHeaderOpen =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const {parse} = integrationRequire("@vue/compiler-sfc")

const files = [
  {
    name: "OpsContactRequirementNew.vue",
    panels: 2,
    sha256: "890819f865f916664f51708fa64f8533d261ac62a6f5e8deeaff1fc7e413c658",
    headerClasses: {
      "border-b border-base-300 px-5 py-3": 2
    }
  },
  {
    name: "OpsContactRequirementShow.vue",
    panels: 4,
    sha256: "d47dbbd37e5798262464e30ae78220608f61c6eafbf383da4ea8f59c265130a4",
    headerClasses: {
      "flex items-center justify-between border-b border-base-300 px-4 py-3": 2,
      "border-b border-base-300 px-4 py-3": 2
    }
  },
  {
    name: "OpsContactRequirementTemplate.vue",
    panels: 2,
    sha256: "929c036b0ccc55901458734c14d03af68a8f820e2f3fa27eb6d709c6d5507e31",
    headerClasses: {
      "flex items-center justify-between border-b border-base-300 px-4 py-3": 1,
      "border-b border-base-300 px-4 py-3": 1
    }
  },
  {
    name: "OpsContactSchedule.vue",
    panels: 3,
    sha256: "5470be3cd3a98de00f121eb2913c2b5a037643e846591b9bd91e0df02e62818e",
    headerClasses: {
      "flex flex-col gap-3 border-b border-base-300 px-4 py-3 sm:flex-row sm:items-end sm:justify-between": 1,
      "flex items-center justify-between border-b border-base-300 px-4 py-3": 2
    }
  }
]

const rawScheduleAsideStart =
  '        <aside class="min-w-0 border border-base-300 bg-base-200/25 lg:sticky lg:top-0 lg:self-start">'
const rawScheduleAsideEnd = "\n        </aside>"
const rawScheduleAsideSha256 = "7ee7b82e26ada81562fda604c5d51fe9e501f55933b621de6b827ecdf2baf648"

const occurrences = (source, needle) => source.split(needle).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

const peelPageHeaderFrame = (source, name) => {
  assert.equal(occurrences(source, cadencePageHeaderFrameImport), 1, `${name} page header import count`)
  assert.equal(occurrences(source, cadencePageHeaderFrameOpen), 1, `${name} page header open count`)
  assert.equal(occurrences(source, cadencePageHeaderFrameClose), 1, `${name} page header close count`)

  const predecessorCompatibleSource = source
    .replace(cadencePageHeaderFrameImport, "")
    .replace(cadencePageHeaderFrameOpen, opsPageHeaderOpen)
    .replace(cadencePageHeaderFrameClose, "</header>")

  assert.equal(
    occurrences(predecessorCompatibleSource, "CadencePageHeaderFrame"),
    0,
    `${name} predecessor source has no residual CadencePageHeaderFrame`
  )

  return predecessorCompatibleSource
}

const extractRawScheduleAside = (source) => {
  const start = source.indexOf(rawScheduleAsideStart)
  assert.notEqual(start, -1, "OpsContactSchedule raw aside variant must remain present")

  const closing = source.indexOf(rawScheduleAsideEnd, start)
  assert.notEqual(closing, -1, "OpsContactSchedule raw aside variant must remain closed")

  return source.slice(start, closing + rawScheduleAsideEnd.length)
}

const reconstructBase = (migratedSource, expectedPanels) => {
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
      "each CadencePanel opening must carry one reconstructable header-class"
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

assert.equal(process.version, pinnedNodeVersion, `run with pinned Node ${pinnedNodeVersion}`)
assert.equal(files.reduce((total, file) => total + file.panels, 0), 11)

for (const file of files) {
  const source = await readFile(resolve(vueDirectory, file.name), "utf8")
  const parsed = parse(source, {filename: file.name})

  assert.equal(parsed.errors.length, 0, `${file.name} must parse with the Vue compiler`)
  assert.equal(occurrences(source, cadencePanelImport), 1, `${file.name} import count`)
  assert.equal(occurrences(source, "<CadencePanel"), file.panels, `${file.name} open count`)
  assert.equal(occurrences(source, "</CadencePanel>"), file.panels, `${file.name} close count`)
  assert.equal(occurrences(source, "header-class="), file.panels, `${file.name} header-class count`)
  assert.equal(occurrences(source, "<template #header>"), file.panels, `${file.name} header slot count`)

  for (const [headerClass, expectedCount] of Object.entries(file.headerClasses)) {
    assert.equal(
      occurrences(source, `header-class="${headerClass}"`),
      expectedCount,
      `${file.name} ${headerClass} count`
    )
  }

  const predecessorCompatibleSource = peelPageHeaderFrame(source, file.name)

  if (file.name === "OpsContactSchedule.vue") {
    assert.equal(sha256(extractRawScheduleAside(predecessorCompatibleSource)), rawScheduleAsideSha256)
  }

  const reconstructed = reconstructBase(predecessorCompatibleSource, file.panels)
  assert.equal(sha256(reconstructed), file.sha256, `${file.name} frozen base SHA-256`)

  if (file.name === "OpsContactSchedule.vue") {
    assert.equal(sha256(extractRawScheduleAside(reconstructed)), rawScheduleAsideSha256)
  }
}

console.log("panel contact requirements migration: 4 SFCs, 11 panels, and raw aside verified")

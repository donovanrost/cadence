import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {fileURLToPath} from "node:url"
import {resolve} from "node:path"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const {parse} = integrationRequire("@vue/compiler-sfc")

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const cadencePanelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"'
const assetsRoot = fileURLToPath(new URL("../", import.meta.url))

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, "24.16.0")

const files = [
  {
    path: "vue/OpsContactDetail.vue",
    panelCount: 5,
    baseSha256: "c9bb6fb1cf04d664600ad9965e8927c00da816d38774a7df62faa1bd58e049d4",
    importInsertion: `${cadencePanelImport}\n`,
    headerClasses: [
      ["flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3", 1],
      ["border-b border-base-300 px-4 py-3", 4]
    ],
    rawVariants: [
      '  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">\n    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
      '      <aside class="min-w-0 space-y-5 xl:sticky xl:top-0 xl:self-start">'
    ],
    panels: [
      {
        currentOpen:
          '        <CadencePanel :id="page.values.id" class="border border-base-300 bg-base-200/20" header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="page.values.id" class="border border-base-300 bg-base-200/20">',
        headerClass:
          "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel :id="page.changes.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="page.changes.id" class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel :id="page.binding_chain.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="page.binding_chain.id" class="border border-base-300 bg-base-200/25">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen: '        <section class="border border-base-300 bg-base-200/25">',
        headerClass: "border-b border-base-300 px-4 py-3"
      }
    ]
  },
  {
    path: "vue/OpsContactPlanShow.vue",
    panelCount: 4,
    baseSha256: "4705f28ee4c3bc0a590e6db181c37b6e780192d7d37c5d0bb9b986faee2dd9e5",
    importInsertion: `${cadencePanelImport}\n`,
    headerClasses: [
      ["border-b border-base-300 px-4 py-3", 3],
      ["border-b border-warning/30 px-4 py-3", 1]
    ],
    rawVariants: [
      '  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">\n    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
      '        <section :id="page.summary.id" class="border border-base-300 bg-base-200/20">\n          <div class="grid gap-4 p-4 sm:grid-cols-3">',
      '      <aside class="min-w-0 space-y-5">',
      '        <section class="border border-base-300 bg-base-200/20 p-4">\n          <p class="hud-label">{{ page.rationale.heading }}</p>'
    ],
    panels: [
      {
        currentOpen:
          '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel\n          v-if="page.unsatisfied !== null"\n          :id="page.unsatisfied.id"\n          class="border border-warning/40 bg-warning/5"\n          header-class="border-b border-warning/30 px-4 py-3"\n        >',
        originalOpen:
          '        <section\n          v-if="page.unsatisfied !== null"\n          :id="page.unsatisfied.id"\n          class="border border-warning/40 bg-warning/5"\n        >',
        headerClass: "border-b border-warning/30 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen: '        <section class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      }
    ]
  },
  {
    path: "vue/OpsContactRecord.vue",
    panelCount: 4,
    baseSha256: "27ba5df055cf368437c556338ccc89d8982f8a34896c0702cfd00eba50c5c00a",
    importInsertion: `${cadencePanelImport}\n\n`,
    headerClasses: [["border-b border-base-300 px-4 py-3", 4]],
    rawVariants: [
      '  <main :id="record.id" class="min-h-0 flex-1 overflow-y-auto bg-base-100">\n    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
      '      <aside class="min-w-0 space-y-5">'
    ],
    panels: [
      {
        currentOpen:
          '        <CadencePanel :id="record.window.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="record.window.id" class="border border-base-300 bg-base-200/25">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel :id="record.paths.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="record.paths.id" class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel :id="record.lineage.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="record.lineage.id" class="border border-base-300 bg-base-200/25">',
        headerClass: "border-b border-base-300 px-4 py-3"
      },
      {
        currentOpen:
          '        <CadencePanel :id="record.context.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">',
        originalOpen:
          '        <section :id="record.context.id" class="border border-base-300 bg-base-200/20">',
        headerClass: "border-b border-base-300 px-4 py-3"
      }
    ]
  }
]

const countLiteral = (source, literal) => source.split(literal).length - 1
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

const peelPanel = (source, panel, path) => {
  const panelIndent = panel.currentOpen.match(/^(\s*)<CadencePanel/)?.[1]
  assert.notEqual(panelIndent, undefined, `${path}: panel indentation is frozen`)
  const headerIndent = `${panelIndent}  `
  const pattern = new RegExp(
    `${escapeRegExp(panel.currentOpen)}\\n${escapeRegExp(headerIndent)}<template #header>([\\s\\S]*?)\\n${escapeRegExp(headerIndent)}</template>([\\s\\S]*?)\\n${escapeRegExp(panelIndent)}</CadencePanel>`
  )
  const match = pattern.exec(source)

  assert.notEqual(match, null, `${path}: exact migrated panel boundary exists`)

  const replacement =
    `${panel.originalOpen}\n${headerIndent}<div class="${panel.headerClass}">` +
    `${match[1]}\n${headerIndent}</div>${match[2]}\n${panelIndent}</section>`

  return source.slice(0, match.index) + replacement + source.slice(match.index + match[0].length)
}

let totalPanels = 0

for (const file of files) {
  const source = await readFile(resolve(assetsRoot, file.path), "utf8")
  const parsed = parse(source, {filename: file.path})

  assert.deepEqual(parsed.errors, [], `${file.path}: Vue compiler parses the SFC`)
  assert.equal(countLiteral(source, cadencePanelImport), 1, `${file.path}: exact import count`)
  assert.equal(countLiteral(source, "<CadencePanel"), file.panelCount, `${file.path}: open count`)
  assert.equal(
    countLiteral(source, "</CadencePanel>"),
    file.panelCount,
    `${file.path}: close count`
  )
  assert.equal(
    countLiteral(source, "header-class="),
    file.panelCount,
    `${file.path}: header-class count`
  )
  assert.equal(
    countLiteral(source, "<template #header>"),
    file.panelCount,
    `${file.path}: header slot count`
  )

  for (const [headerClass, expectedCount] of file.headerClasses) {
    assert.equal(
      countLiteral(source, `header-class="${headerClass}"`),
      expectedCount,
      `${file.path}: exact ${headerClass} count`
    )
  }

  for (const rawVariant of file.rawVariants) {
    assert.equal(countLiteral(source, rawVariant), 1, `${file.path}: raw variant remains exact`)
  }

  let reconstructed = source.replace(file.importInsertion, "")
  assert.equal(
    reconstructed.length,
    source.length - file.importInsertion.length,
    `${file.path}: exact import insertion peels once`
  )

  for (const panel of file.panels) {
    reconstructed = peelPanel(reconstructed, panel, file.path)
  }

  assert.equal(
    reconstructed.includes("CadencePanel"),
    false,
    `${file.path}: reconstruction has no residual CadencePanel`
  )

  for (const rawVariant of file.rawVariants) {
    assert.equal(
      countLiteral(reconstructed, rawVariant),
      1,
      `${file.path}: reconstruction preserves the raw variant`
    )
  }

  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    file.baseSha256,
    `${file.path}: reconstruction matches the frozen base byte-for-byte`
  )

  totalPanels += file.panelCount
}

assert.equal(totalPanels, 13, "the frozen cohort contains exactly 13 panels")

console.log("panel contact detail migration contract: ok")

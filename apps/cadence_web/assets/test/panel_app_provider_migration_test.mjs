#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFileSync} from "node:fs"
import {fileURLToPath} from "node:url"

import {integrationRequire} from "./reka_adapter_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const compactPageHeaderOpen = '    <CadencePageHeaderFrame variant="compact">'
const compactPageHeaderBaseOpen = '    <header class="border-b border-primary/20 pb-4">'
const compactPageHeaderClose = "    </CadencePageHeaderFrame>"
const compactPageHeaderBaseClose = "    </header>"
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const panelHeaderClass =
  "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
const {parse} = integrationRequire("@vue/compiler-sfc")

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, "24.16.0")

const occurrenceCount = (source, fragment) => source.split(fragment).length - 1

const replaceExact = (source, from, to, expectedCount, label) => {
  assert.equal(occurrenceCount(source, from), expectedCount, label)
  return source.split(from).join(to)
}

const fixtures = [
  {
    name: "AdminRuntime.vue",
    sha256: "39e6e11081179de270e78e1288698ebf330e8f098809f52c9466df457bb1b463",
    panelCount: 3,
    openingRewrites: [
      {
        count: 2,
        migrated: `    <CadencePanel
      class="card bg-base-200 border border-base-300"
      header-class="${panelHeaderClass}"
    >
      <template #header>`,
        base: `    <section class="card bg-base-200 border border-base-300">
      <div class="${panelHeaderClass}">`
      },
      {
        count: 1,
        migrated: `    <CadencePanel
      v-if="selection.detail"
      :id="selection.detail.id"
      class="card bg-base-200 border border-base-300"
      header-class="${panelHeaderClass}"
    >
      <template #header>`,
        base: `    <section
      v-if="selection.detail"
      :id="selection.detail.id"
      class="card bg-base-200 border border-base-300"
    >
      <div class="${panelHeaderClass}">`
      }
    ],
    headerCloseRewrites: [
      {
        count: 3,
        migrated: "      </template>",
        base: "      </div>"
      }
    ],
    panelClose: {
      count: 3,
      migrated: "    </CadencePanel>",
      base: "    </section>"
    },
    rawFragments: [
      {fragment: '    <header class="border-b border-primary/20 pb-4">', count: 1}
    ]
  },
  {
    name: "CommsValidation.vue",
    sha256: "a92264ee7156342d91fdf504d17c39ac16fe06f487a505ed4ca7af502836e95b",
    panelCount: 1,
    openingRewrites: [
      {
        count: 1,
        migrated: `      <CadencePanel
        v-for="group in validation.finding_groups"
        :id="group.id"
        :key="group.id"
        class="card bg-base-200 border border-base-300"
        header-class="${panelHeaderClass}"
      >
        <template #header>`,
        base: `      <section
        v-for="group in validation.finding_groups"
        :id="group.id"
        :key="group.id"
        class="card bg-base-200 border border-base-300"
      >
        <div class="${panelHeaderClass}">`
      }
    ],
    headerCloseRewrites: [
      {
        count: 1,
        migrated: '        </template>\n        <div class="card-body p-0">',
        base: '        </div>\n        <div class="card-body p-0">'
      }
    ],
    panelClose: {
      count: 1,
      migrated: "      </CadencePanel>",
      base: "      </section>"
    },
    rawFragments: [
      {fragment: '    <header class="border-b border-primary/20 pb-4">', count: 1}
    ]
  },
  {
    name: "ProviderAccountShow.vue",
    sha256: "e22c0208bfb070a8b0b2748831e3203206637a11f09f4a3f7dd161101c8f2251",
    panelCount: 3,
    openingRewrites: [
      {
        count: 1,
        migrated: `        <CadencePanel
          :id="page.grants.card_id"
          class="card bg-base-200 border border-base-300"
          header-class="${panelHeaderClass}"
        >
          <template #header>`,
        base: `        <section :id="page.grants.card_id" class="card bg-base-200 border border-base-300">
          <div class="${panelHeaderClass}">`
      },
      {
        count: 1,
        migrated: `        <CadencePanel
          :id="page.grant_form_card.id"
          class="card bg-base-200 border border-base-300"
          header-class="${panelHeaderClass}"
        >
          <template #header>`,
        base: `        <section :id="page.grant_form_card.id" class="card bg-base-200 border border-base-300">
          <div class="${panelHeaderClass}">`
      },
      {
        count: 1,
        migrated: `        <CadencePanel
          :id="page.audit.card_id"
          class="card bg-base-200 border border-base-300"
          header-class="${panelHeaderClass}"
        >
          <template #header>`,
        base: `        <section :id="page.audit.card_id" class="card bg-base-200 border border-base-300">
          <div class="${panelHeaderClass}">`
      }
    ],
    headerCloseRewrites: [
      {
        count: 2,
        migrated: '          </template>\n          <div class="card-body p-0">',
        base: '          </div>\n          <div class="card-body p-0">'
      },
      {
        count: 1,
        migrated: '          </template>\n          <div class="card-body p-6">',
        base: '          </div>\n          <div class="card-body p-6">'
      }
    ],
    panelClose: {
      count: 3,
      migrated: "        </CadencePanel>",
      base: "        </section>"
    },
    rawFragments: [
      {fragment: '    <header class="border-b border-primary/20 pb-4">', count: 1},
      {fragment: '      <aside class="space-y-4">', count: 1}
    ]
  }
]

for (const fixture of fixtures) {
  const filename = fileURLToPath(new URL(`../vue/${fixture.name}`, import.meta.url))
  const currentSource = readFileSync(filename, "utf8")
  const parsed = parse(currentSource, {filename})

  assert.deepEqual(parsed.errors, [], `${fixture.name} must parse with the Vue compiler`)
  let source = replaceExact(
    currentSource,
    pageHeaderImport,
    "",
    1,
    `${fixture.name} page header import reconstruction`
  )
  source = replaceExact(
    source,
    compactPageHeaderOpen,
    compactPageHeaderBaseOpen,
    1,
    `${fixture.name} page header opening reconstruction`
  )
  source = replaceExact(
    source,
    compactPageHeaderClose,
    compactPageHeaderBaseClose,
    1,
    `${fixture.name} page header close reconstruction`
  )
  assert.equal(occurrenceCount(source, panelImport), 1, `${fixture.name} import count`)
  assert.equal(
    occurrenceCount(source, "<CadencePanel\n"),
    fixture.panelCount,
    `${fixture.name} open count`
  )
  assert.equal(
    occurrenceCount(source, "</CadencePanel>"),
    fixture.panelCount,
    `${fixture.name} close count`
  )
  assert.equal(
    occurrenceCount(source, `header-class="${panelHeaderClass}"`),
    fixture.panelCount,
    `${fixture.name} header-class count`
  )

  for (const {fragment, count} of fixture.rawFragments) {
    assert.equal(occurrenceCount(source, fragment), count, `${fixture.name} raw variant`)
  }

  let reconstructed = replaceExact(
    source,
    panelImport,
    "",
    1,
    `${fixture.name} import reconstruction`
  )

  for (const rewrite of fixture.openingRewrites) {
    reconstructed = replaceExact(
      reconstructed,
      rewrite.migrated,
      rewrite.base,
      rewrite.count,
      `${fixture.name} opening reconstruction`
    )
  }

  for (const rewrite of fixture.headerCloseRewrites) {
    reconstructed = replaceExact(
      reconstructed,
      rewrite.migrated,
      rewrite.base,
      rewrite.count,
      `${fixture.name} header close reconstruction`
    )
  }
  reconstructed = replaceExact(
    reconstructed,
    fixture.panelClose.migrated,
    fixture.panelClose.base,
    fixture.panelClose.count,
    `${fixture.name} panel close reconstruction`
  )

  assert.equal(
    reconstructed.includes("CadencePanel"),
    false,
    `${fixture.name} reconstruction must contain no residual CadencePanel`
  )
  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    fixture.sha256,
    `${fixture.name} must reconstruct the exact frozen base`
  )
}

console.log("panel app/provider migration contract passed")

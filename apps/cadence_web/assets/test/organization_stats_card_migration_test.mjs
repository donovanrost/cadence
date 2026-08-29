import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "OrganizationStats imports the unchanged CadenceCard primitive for exactly three metric shells",
  "the fixed predecessor commit preserves the frozen OrganizationStats bytes and SHA-256",
  "the newest CadenceCard layer peels to the fixed predecessor byte-for-byte without moving HEAD",
  "the real OrganizationStats SFC graph compiles and mounts after JSDOM globals are installed",
  "the root and all three native section and body identities retain their exact tags and classes",
  "the caller-owned labels and counts retain their exact classes, values, and order",
  "reactive count updates preserve every native element identity and the exact emitted DOM",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const predecessor = "32992e075c285c2e0e02ebf02bc5fa88863ca488"
const predecessorByteLength = 1439
const predecessorSha256 = "99e4693d18ba7d2b32301bfbc7a09c5b52c83d12f26f9fa344ed5a7855b89771"
const repositoryPath = "apps/cadence_web/assets/vue/OrganizationStats.vue"
const rootClass = "grid gap-4 md:grid-cols-3"
const cardClass =
  "card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
const bodyClass = "card-body p-6"
const countClass = "mt-2 font-mono text-3xl font-bold"
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n\n'
const cards = Object.freeze([
  Object.freeze({key: "mission_count", id: "organization-stat-missions", label: "Missions"}),
  Object.freeze({
    key: "spacecraft_count",
    id: "organization-stat-spacecraft",
    label: "Spacecraft",
  }),
  Object.freeze({key: "member_count", id: "organization-stat-members", label: "Members"}),
])

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, "24.16.0")
assert.equal(scenarios.length, 7)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const componentPath = resolve(repositoryRoot, repositoryPath)
const sha256 = (value) => createHash("sha256").update(value).digest("hex")
const gitShow = (commit, path) =>
  execFileSync("git", ["-C", repositoryRoot, "show", `${commit}:${path}`])

const currentSource = await readFile(componentPath, "utf8")
const predecessorBytes = gitShow(predecessor, repositoryPath)

assert.equal(
  execFileSync("git", ["-C", repositoryRoot, "cat-file", "-t", predecessor], {
    encoding: "utf8",
  }).trim(),
  "commit",
)
assert.equal(predecessorBytes.byteLength, predecessorByteLength)
assert.equal(sha256(predecessorBytes), predecessorSha256)
assert.equal(currentSource.split(cardImport).length - 1, 1)
assert.equal(currentSource.match(/^import CadenceCard\b/gm)?.length, 1)
assert.equal(currentSource.match(/<CadenceCard\b/g)?.length, cards.length)
assert.equal(currentSource.match(/<\/CadenceCard>/g)?.length, cards.length)
assert.equal(currentSource.match(/body-class="card-body p-6"/g)?.length, cards.length)
assert.equal(currentSource.match(/<div class="card-body p-6">/g)?.length ?? 0, 0)

let reconstructed = currentSource.replace(cardImport, "")

for (const card of cards) {
  const opening = `    <CadenceCard
      id="${card.id}"
      class="${cardClass}"
      body-class="card-body p-6"
    >
`
  const originalOpening = `    <section
      id="${card.id}"
      class="${cardClass}"
    >
      <div class="card-body p-6">`
  const closing = "\n    </CadenceCard>"

  assert.equal(reconstructed.split(opening).length - 1, 1, `${card.label} opening is exact`)

  const openingIndex = reconstructed.indexOf(opening)
  const slotStart = openingIndex + opening.length
  const closingIndex = reconstructed.indexOf(closing, slotStart)

  assert.ok(closingIndex > slotStart, `${card.label} closing follows its opening`)

  const callerSlot = reconstructed.slice(slotStart, closingIndex)

  assert.equal(
    callerSlot,
    `        <p class="hud-label">${card.label}</p>
        <p class="${countClass}">{{ ${card.key} }}</p>`,
  )

  const original = `${originalOpening}\n${callerSlot}\n      </div>\n    </section>`

  reconstructed =
    reconstructed.slice(0, openingIndex) +
    original +
    reconstructed.slice(closingIndex + closing.length)
}

assert.doesNotMatch(reconstructed, /CadenceCard/)
assert.equal(Buffer.byteLength(reconstructed), predecessorByteLength)
assert.equal(sha256(reconstructed), predecessorSha256)
assert.deepEqual(Buffer.from(reconstructed), predecessorBytes)

const dom = installDom('<div id="organization-stats-contract"></div>')
const loaded = await loadSfc(componentPath)
const {createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")
const counts = reactive({mission_count: 7, spacecraft_count: 11, member_count: 13})
const Oracle = defineComponent({
  name: "OrganizationStatsCardMigrationOracle",
  setup() {
    return () => h(loaded.component, counts)
  },
})
const app = createApp(Oracle)

app.mount(dom.window.document.querySelector("#organization-stats-contract"))
await flushVue(nextTick)

const root = dom.window.document.querySelector("#organization-stats")
const sections = [...root.children]
const bodies = sections.map((section) => section.firstElementChild)
const labelElements = bodies.map((body) => body.children[0])
const countElements = bodies.map((body) => body.children[1])
const expectedOuterHtml = (values) =>
  `<div id="organization-stats" class="${rootClass}">` +
  cards
    .map(
      (card) =>
        `<section id="${card.id}" class="${cardClass}"><div class="${bodyClass}">` +
        `<p class="hud-label">${card.label}</p>` +
        `<p class="${countClass}">${values[card.key]}</p>` +
        `</div></section>`,
    )
    .join("") +
  `</div>`

assert.equal(root.outerHTML, expectedOuterHtml(counts))
assert.equal(root.tagName, "DIV")
assert.deepEqual(elementAttributes(root), {class: rootClass, id: "organization-stats"})
assert.equal(root.childNodes.length, cards.length)
assert.deepEqual(
  sections.map((section) => section.id),
  cards.map((card) => card.id),
)

for (const [index, card] of cards.entries()) {
  const section = sections[index]
  const body = bodies[index]
  const label = labelElements[index]
  const count = countElements[index]

  assert.equal(section.tagName, "SECTION")
  assert.deepEqual(elementAttributes(section), {class: cardClass, id: card.id})
  assert.equal(section.childNodes.length, 1)
  assert.equal(section.children.length, 1)
  assert.equal(section.hasAttribute("body-class"), false)
  assert.equal(section.hasAttribute("bodyclass"), false)
  assert.equal(body.tagName, "DIV")
  assert.deepEqual(elementAttributes(body), {class: bodyClass})
  assert.equal(body.childNodes.length, 2)
  assert.deepEqual(
    [...body.children].map((element) => element.tagName),
    ["P", "P"],
  )
  assert.deepEqual(elementAttributes(label), {class: "hud-label"})
  assert.equal(label.textContent, card.label)
  assert.deepEqual(elementAttributes(count), {class: countClass})
  assert.equal(count.textContent, String(counts[card.key]))
}

counts.mission_count = 17
counts.spacecraft_count = 19
counts.member_count = 23
await flushVue(nextTick)

assert.strictEqual(dom.window.document.querySelector("#organization-stats"), root)
assert.equal(root.outerHTML, expectedOuterHtml(counts))

for (const [index, card] of cards.entries()) {
  const section = dom.window.document.querySelector(`#${card.id}`)

  assert.strictEqual(section, sections[index])
  assert.strictEqual(section.firstElementChild, bodies[index])
  assert.strictEqual(section.firstElementChild.children[0], labelElements[index])
  assert.strictEqual(section.firstElementChild.children[1], countElements[index])
  assert.equal(labelElements[index].textContent, card.label)
  assert.equal(countElements[index].textContent, String(counts[card.key]))
}

app.unmount()
dom.window.close()

console.log(
  `organization_stats_card_migration_test passed (${cards.length} exact cards, ${scenarios.length} scenarios, predecessor ${predecessor})`,
)

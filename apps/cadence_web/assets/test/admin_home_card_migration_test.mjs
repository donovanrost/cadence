import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {installDom, loadSfc} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "AdminHome card migration contracts use pinned Node 24.16.0",
)

const base = "c37dd6fc62ab440f2964b85f8231989f1234f488"
const baseSha256 = "909f1e8f46beb46fc544f33e67a70901cdd3e5be8cebce9ce1dab9141769a753"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const adminHomePath = resolve(testDirectory, "../vue/AdminHome.vue")
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n\n'
const pageHeaderFrameImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const peelPageHeaderFrame = (value) =>
  value
    .replace(pageHeaderFrameImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")
const source = await readFile(adminHomePath, "utf8")
const digest = (value) => createHash("sha256").update(value).digest("hex")
const count = (value, pattern) => value.match(pattern)?.length ?? 0

const boundaries = Object.freeze([
  {
    name: "organizations",
    opening: `      <CadenceCard
        id="admin-home-organizations-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
`,
    originalOpening: `      <section
        id="admin-home-organizations-card"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body p-6">`,
  },
  {
    name: "users",
    opening: `      <CadenceCard
        id="admin-home-users-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
`,
    originalOpening:
      `      <section id="admin-home-users-card" class="card bg-base-200 border border-base-300">\n` +
      `        <div class="card-body p-6">`,
  },
  {
    name: "runtime",
    opening: `      <CadenceCard
        id="admin-home-runtime-card"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
`,
    originalOpening: `      <section
        id="admin-home-runtime-card"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body p-6">`,
  },
])

const hoverCard = `        <section
          class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
        >
          <div class="card-body p-6">
            <div class="flex items-center gap-4">
              <div>
                <h3 class="font-semibold">
                  {{ presentation.quick_actions.create_organization_title }}
                </h3>
                <p class="text-sm text-base-content/60">
                  {{ presentation.quick_actions.create_organization_description }}
                </p>
              </div>
            </div>
          </div>
        </section>`

assert.equal(source.split(cardImport).length - 1, 1, "AdminHome imports CadenceCard once")
assert.equal(count(source, /<CadenceCard\b/g), 3, "exactly three conventional cards migrate")
assert.equal(count(source, /body-class="card-body p-6"/g), 3)
assert.equal(count(source, /<div class="card-body p-6">/g), 1)
assert.equal(source.split(hoverCard).length - 1, 1, "the hover quick-action card stays raw")
assert.match(
  source,
  /<a\s+id="admin-home-create-organization-link"[\s\S]*?<section\s+class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-\[linear-gradient\(var\(--state-hover\),var\(--state-hover\)\)\]"/,
)

let reconstructed = peelPageHeaderFrame(source).replace(cardImport, "")

for (const boundary of boundaries) {
  assert.equal(
    reconstructed.split(boundary.opening).length - 1,
    1,
    `${boundary.name} CadenceCard opening is exact and unique`,
  )

  const openingIndex = reconstructed.indexOf(boundary.opening)
  const slotStart = openingIndex + boundary.opening.length
  const closing = "\n      </CadenceCard>"
  const closingIndex = reconstructed.indexOf(closing, slotStart)

  assert.ok(closingIndex > slotStart, `${boundary.name} closing follows its opening`)

  const callerSlot = reconstructed.slice(slotStart, closingIndex)

  assert.match(callerSlot, /^          <(?:p|button|a)\b/)
  assert.doesNotMatch(callerSlot, /<div class="card-body p-6">/)

  const original =
    `${boundary.originalOpening}\n${callerSlot}\n` +
    `        </div>\n      </section>`

  reconstructed =
    reconstructed.slice(0, openingIndex) +
    original +
    reconstructed.slice(closingIndex + closing.length)
}

assert.doesNotMatch(reconstructed, /CadenceCard/)
assert.equal(
  digest(reconstructed),
  baseSha256,
  `stripping exactly one import and three boundaries reconstructs base ${base}`,
)
assert.equal(boundaries.length, 3)

installDom()
const compiledAdminHome = await loadSfc(adminHomePath)

assert.ok(compiledAdminHome.descriptor.scriptSetup)
assert.ok(compiledAdminHome.descriptor.template)
assert.equal(typeof compiledAdminHome.component.setup, "function")

console.log("admin_home_card_migration_test passed (3 boundaries, exact base reconstruction)")

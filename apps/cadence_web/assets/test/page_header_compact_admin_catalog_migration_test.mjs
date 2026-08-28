import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFileSync, realpathSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const importLine =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const frameOpening = '<CadencePageHeaderFrame variant="compact">'
const frameClosing = "</CadencePageHeaderFrame>"
const nativeOpening = '<header class="border-b border-primary/20 pb-4">'
const nativeClosing = "</header>"
const callers = [
  "apps/cadence_web/assets/vue/CatalogDatabaseNew.vue",
  "apps/cadence_web/assets/vue/CatalogImportRunShow.vue",
  "apps/cadence_web/assets/vue/CatalogRevisionShow.vue",
  "apps/cadence_web/assets/vue/CatalogDatabaseShow.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationInvite.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationNew.vue",
  "apps/cadence_web/assets/vue/AdminRuntime.vue",
  "apps/cadence_web/assets/vue/AdminOrganizationShow.vue",
  "apps/cadence_web/assets/vue/ApplicationHost.vue"
]

function occurrences(source, value) {
  return source.split(value).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

assert.equal(process.versions.node, "24.16.0", "migration proof requires Node 24.16.0")
assert.equal(
  realpathSync(process.execPath),
  realpathSync(pinnedNode),
  `migration proof must run with ${pinnedNode}`
)

for (const caller of callers) {
  const source = readFileSync(resolve(repositoryRoot, caller), "utf8")

  assert.equal(occurrences(source, importLine), 1, `${caller} must have one frame import`)
  assert.equal(occurrences(source, frameOpening), 1, `${caller} must have one compact frame`)
  assert.equal(occurrences(source, frameClosing), 1, `${caller} must close one compact frame`)
  assert.equal(
    occurrences(source, nativeOpening),
    0,
    `${caller} must have no residual native compact page header`
  )

  const reconstructed = source
    .replace(importLine, "")
    .replace(frameOpening, nativeOpening)
    .replace(frameClosing, nativeClosing)
  const parentSource = execFileSync("git", ["show", `${parent}:${caller}`], {
    cwd: repositoryRoot
  })

  assert.equal(
    sha256(Buffer.from(reconstructed, "utf8")),
    sha256(parentSource),
    `${caller} must reconstruct byte-for-byte to ${parent}`
  )
}

console.log(`ok - ${callers.length} compact admin/catalog page-header migrations reconstruct ${parent}`)

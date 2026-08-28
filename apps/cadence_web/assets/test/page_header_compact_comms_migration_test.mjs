import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {execFileSync} from "node:child_process"
import {readFileSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import test from "node:test"

assert.equal(
  process.versions.node,
  "24.16.0",
  "page header compact comms migration test requires pinned Node 24.16.0",
)

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const migrationImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const frameOpening = '<CadencePageHeaderFrame variant="compact">'
const frameClosing = "</CadencePageHeaderFrame>"
const nativeOpening = '<header class="border-b border-primary/20 pb-4">'
const nativeClosing = "</header>"
const callers = [
  "apps/cadence_web/assets/vue/ProviderAccountNew.vue",
  "apps/cadence_web/assets/vue/ProviderAccountShow.vue",
  "apps/cadence_web/assets/vue/CommsProviderNew.vue",
  "apps/cadence_web/assets/vue/CommsProviderShow.vue",
  "apps/cadence_web/assets/vue/CommsTransportNew.vue",
  "apps/cadence_web/assets/vue/CommsTransportShow.vue",
  "apps/cadence_web/assets/vue/CommsValidation.vue",
  "apps/cadence_web/assets/vue/CommsRoutingNew.vue",
  "apps/cadence_web/assets/vue/CommsRoutingShow.vue",
  "apps/cadence_web/assets/vue/CommsGroundStationForm.vue",
  "apps/cadence_web/assets/vue/CommsGroundStationShow.vue",
]

function occurrences(source, value) {
  return source.split(value).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

for (const caller of callers) {
  test(`${caller} has one compact frame and reconstructs its exact parent source`, () => {
    const source = readFileSync(resolve(repositoryRoot, caller), "utf8")

    assert.equal(occurrences(source, migrationImport), 1, "expected exactly one frame import")
    assert.equal(occurrences(source, frameOpening), 1, "expected exactly one frame opening")
    assert.equal(occurrences(source, frameClosing), 1, "expected exactly one frame closing")
    assert.doesNotMatch(source, /<header\b/, "expected no residual native header")

    const reconstructed = source
      .replace(migrationImport, "")
      .replace(frameOpening, nativeOpening)
      .replace(frameClosing, nativeClosing)
    const parentSource = execFileSync("git", ["-C", repositoryRoot, "show", `${parent}:${caller}`], {
      encoding: "utf8",
    })

    assert.equal(
      sha256(reconstructed),
      sha256(parentSource),
      "reconstructed SHA-256 must match the exact parent source",
    )
  })
}

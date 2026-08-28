import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFileSync} from "node:fs"
import {dirname, resolve} from "node:path"
import test from "node:test"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "expected pinned Node 24.16.0")

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const componentImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const frameOpening = '<CadencePageHeaderFrame variant="compact">'
const frameClosing = "</CadencePageHeaderFrame>"
const nativeOpening = '<header class="border-b border-primary/20 pb-4">'
const nativeClosing = "</header>"
const callers = [
  "apps/cadence_web/assets/vue/SpacecraftTypeNew.vue",
  "apps/cadence_web/assets/vue/SpacecraftTypeShow.vue",
  "apps/cadence_web/assets/vue/SpacecraftNew.vue",
  "apps/cadence_web/assets/vue/SpacecraftEdit.vue",
  "apps/cadence_web/assets/vue/SpacecraftShow.vue",
  "apps/cadence_web/assets/vue/SpacecraftTelemetryDecom.vue",
  "apps/cadence_web/assets/vue/SpacecraftCommanding.vue",
  "apps/cadence_web/assets/vue/SpacecraftReadiness.vue",
  "apps/cadence_web/assets/vue/SpacecraftRouting.vue",
  "apps/cadence_web/assets/vue/MissionNew.vue",
  "apps/cadence_web/assets/vue/MissionOverview.vue",
  "apps/cadence_web/assets/vue/OpsActivationRequests.vue",
]

function occurrences(source, needle) {
  return source.split(needle).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

test("compact spacecraft and mission page-header migration is exact", async (t) => {
  for (const caller of callers) {
    await t.test(caller, () => {
      const source = readFileSync(resolve(repoRoot, caller), "utf8")

      assert.equal(occurrences(source, componentImport), 1, "expected exactly one frame import")
      assert.equal(occurrences(source, frameOpening), 1, "expected exactly one compact frame")
      assert.equal(occurrences(source, frameClosing), 1, "expected exactly one frame closing tag")
      assert.equal(occurrences(source, nativeOpening), 0, "residual native page header")

      const importInsertion = caller.endsWith("/SpacecraftRouting.vue")
        ? `${componentImport}\n\n`
        : `${componentImport}\n`
      const reconstructed = source
        .replace(importInsertion, "")
        .replace(frameOpening, nativeOpening)
        .replace(frameClosing, nativeClosing)
      const parentSource = execFileSync("git", ["show", `${parent}:${caller}`], {
        cwd: repoRoot,
      })

      assert.equal(sha256(reconstructed), sha256(parentSource), "reconstructed source differs from parent")
    })
  }
})

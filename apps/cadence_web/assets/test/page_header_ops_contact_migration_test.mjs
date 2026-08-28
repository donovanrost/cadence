import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const expectedNodeVersion = "24.16.0"
const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const importLine =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const nativeOpening =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'
const frameOpening = '<CadencePageHeaderFrame variant="ops">'
const frameClosing = "</CadencePageHeaderFrame>"
const callers = {
  "OpsContactRequirementNew.vue":
    "9da718bb44ff7b53bd5418887825a52ae06f92ab58807c417605401e149081a7",
  "OpsContactRequirementShow.vue":
    "3d3e458575482cbc0a6428c598c70e6bdbe95d7b6c21b77575b40cdfd88e8c70",
  "OpsContactPlanShow.vue":
    "d9320303ec6c51ca8e43ab7c7fe2fec338588c83967f8c74457bc4a87a972c9e",
  "OpsContactRequirementTemplate.vue":
    "2745f51c1e967771ab2c6c705c94c48e8df2051d85b7f58d33b64b122bb2091b",
  "OpsContactSchedule.vue":
    "d9ceae5f1943d983a05595aab3f0c331a87d42dd0e8cd6e63f2736f956d00f73",
  "OpsContactDetail.vue":
    "ef5e69e7a47ae9ddb989e17fb508084b37de30afc1fc10069d18151fb11e1798",
  "OpsContactRecord.vue":
    "9dade15b7f8062f83fc2999aaaeedcb67a16393f9166687111181f45bc285f80",
  "OpsContactRequirementList.vue":
    "0b211aec3c1bc284a9db8d93ccc822b8188b7f012a1567848ef89a4b09a85fab",
}

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `operations contact page-header migration uses pinned Node ${expectedNodeVersion}`,
)

const count = (source, token) => source.split(token).length - 1
const sha256 = source => createHash("sha256").update(source).digest("hex")
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")

for (const [filename, expectedParentHash] of Object.entries(callers)) {
  const source = await readFile(resolve(vueDirectory, filename), "utf8")

  assert.equal(count(source, importLine), 1, `${filename} has exactly one frame import`)
  assert.equal(count(source, frameOpening), 1, `${filename} has exactly one ops frame`)
  assert.equal(count(source, frameClosing), 1, `${filename} closes exactly one ops frame`)
  assert.doesNotMatch(source, /<header(?:\s|>)/, `${filename} has no residual native header`)

  const reconstructed = source
    .replace(`${importLine}\n`, "")
    .replace(frameOpening, nativeOpening)
    .replace(frameClosing, "</header>")

  assert.equal(
    sha256(reconstructed),
    expectedParentHash,
    `${filename} reverses byte-for-byte to parent ${parent}`,
  )
}

console.log(
  `page_header_ops_contact_migration_test passed (${Object.keys(callers).length} callers, parent ${parent})`,
)

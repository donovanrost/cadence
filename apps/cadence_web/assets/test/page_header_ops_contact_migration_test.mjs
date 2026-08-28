import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const expectedNodeVersion = "24.16.0"
const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const importLine =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceValidationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const cadenceValidationMessageSite =
  /^( *)<CadenceValidationMessage v-for="error in template_form\.fields\.([a-z_]+)\.errors" :key="error">\{\{ error \}\}<\/CadenceValidationMessage>$/gm
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
const cadenceFieldFrames = {
  "OpsContactRequirementNew.vue": 16,
  "OpsContactRequirementShow.vue": 0,
  "OpsContactPlanShow.vue": 3,
  "OpsContactRequirementTemplate.vue": 15,
  "OpsContactSchedule.vue": 0,
  "OpsContactDetail.vue": 3,
  "OpsContactRecord.vue": 0,
  "OpsContactRequirementList.vue": 0,
}
const multilineLabels = new Set([
  "change.decision_forms.approval.reason.label",
  "change.decision_forms.rejection.reason.label",
  "change.decision_forms.acknowledgment.reason.label",
  "admin_controls.approve_form.field.label",
  "admin_controls.rejection.form.field.label",
  "form.fields.minimum_data_volume_bytes.label",
  "form.fields.minimum_duration_seconds.label",
  "form.fields.preferred_duration_seconds.label",
  "form.fields.minimum_separation_seconds.label",
])
const cadenceFieldFrame =
  /^( *)<CadenceField\n\1  :control-id="([^"]+)"\n\1  wrapper-class="fieldset mb-3"\n\1  :label="([^"]+)"\n\1  label-class="hud-label block mb-1\.5"\n\1>\n([\s\S]*?)\n\1<\/CadenceField>/gm

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `operations contact page-header migration uses pinned Node ${expectedNodeVersion}`,
)

const count = (source, token) => source.split(token).length - 1
const sha256 = source => createHash("sha256").update(source).digest("hex")
const peelCadenceValidationMessages = (source) =>
  source
    .replace(cadenceValidationMessageImport, "")
    .replace(
      cadenceValidationMessageSite,
      (_match, indent, field) =>
        `${indent}<p v-for="error in template_form.fields.${field}.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>`,
    )
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")

const peelCadenceFields = (source, filename, expectedFrames) => {
  const expectedImports = expectedFrames === 0 ? 0 : 1
  assert.equal(count(source, cadenceFieldImport), expectedImports, `${filename} field import count`)
  assert.equal(count(source, "<CadenceField\n"), expectedFrames, `${filename} field open count`)
  assert.equal(count(source, "</CadenceField>"), expectedFrames, `${filename} field close count`)

  let reconstructedFrames = 0
  const reconstructed = source
    .replace(cadenceFieldImport, "")
    .replace(cadenceFieldFrame, (_match, indent, controlId, label, body) => {
      let control = body
      let originalErrors = ""
      const errorsOpen = `\n${indent}  <template #errors>\n`
      const errorsStart = body.indexOf(errorsOpen)

      if (errorsStart !== -1) {
        const errorsClose = `\n${indent}  </template>`
        assert.ok(body.endsWith(errorsClose), `${filename} errors slot closes exactly`)
        control = body.slice(0, errorsStart)
        const errorSource = body.slice(errorsStart + errorsOpen.length, -errorsClose.length)
        assert.ok(errorSource.startsWith(`${indent}    `), `${filename} error stays caller-owned`)
        originalErrors = `\n${errorSource.slice(2)}`
      }

      const originalControl = control
        .split("\n")
        .map((line) => `  ${line}`)
        .join("\n")
      const originalSpan = multilineLabels.has(label)
        ? `${indent}    <span class="hud-label block mb-1.5">\n${indent}      {{ ${label} }}\n${indent}    </span>`
        : `${indent}    <span class="hud-label block mb-1.5">{{ ${label} }}</span>`

      reconstructedFrames += 1
      return `${indent}<div class="fieldset mb-3">\n${indent}  <label :for="${controlId}">\n${originalSpan}\n${originalControl}\n${indent}  </label>${originalErrors}\n${indent}</div>`
    })

  assert.equal(reconstructedFrames, expectedFrames, `${filename} reconstructs every field frame`)
  assert.equal(count(reconstructed, "CadenceField"), 0, `${filename} has no residual CadenceField`)
  return reconstructed
}

for (const [filename, expectedParentHash] of Object.entries(callers)) {
  const source = await readFile(resolve(vueDirectory, filename), "utf8")

  assert.equal(count(source, importLine), 1, `${filename} has exactly one frame import`)
  assert.equal(count(source, frameOpening), 1, `${filename} has exactly one ops frame`)
  assert.equal(count(source, frameClosing), 1, `${filename} closes exactly one ops frame`)
  assert.doesNotMatch(source, /<header(?:\s|>)/, `${filename} has no residual native header`)

  const reconstructed = peelCadenceFields(
    peelCadenceValidationMessages(source),
    filename,
    cadenceFieldFrames[filename],
  )
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

import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CONTACT CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const cadenceValidationMessageImport =
  'import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"\n'
const cadenceValidationMessageSite =
  /^( *)<CadenceValidationMessage v-for="error in template_form\.fields\.([a-z_]+)\.errors" :key="error">\{\{ error \}\}<\/CadenceValidationMessage>$/gm
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const cadenceDetailsFrameCounts = Object.freeze({
  "OpsContactDetail.vue": 1,
  "OpsContactPlanShow.vue": 2,
  "OpsContactRequirementNew.vue": 1,
  "OpsContactRequirementTemplate.vue": 2,
})

const peelCadenceDetailsFrames = (source, expectedCount, label) => {
  const expectedImportCount = expectedCount > 0 ? 1 : 0

  assert.equal(occurrences(source, cadenceDetailsFrameImport), expectedImportCount, `${label} details import count`)
  assert.equal(source.match(/<CadenceDetailsFrame\b/g)?.length ?? 0, expectedCount, `${label} details opening count`)
  assert.equal(occurrences(source, "</CadenceDetailsFrame>"), expectedCount, `${label} details closing count`)

  const peeled = source
    .replace(cadenceDetailsFrameImport, "")
    .split("<CadenceDetailsFrame")
    .join("<details")
    .split("</CadenceDetailsFrame>")
    .join("</details>")

  assert.doesNotMatch(peeled, /CadenceDetailsFrame/)
  return peeled
}

const peelCadenceValidationMessages = (source) =>
  source
    .replace(cadenceValidationMessageImport, "")
    .replace(
      cadenceValidationMessageSite,
      (_match, indent, field) =>
        `${indent}<p v-for="error in template_form.fields.${field}.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>`,
    )

const callers = Object.freeze([
  {
    file: "OpsContactDetail.vue",
    frames: 3,
    errors: 0,
    headSha256: "5b0d231e917130aecc6e77886ba8d9dee4565adf014736e6cfbae29d5815a415",
  },
  {
    file: "OpsContactPlanShow.vue",
    frames: 3,
    errors: 0,
    headSha256: "02715dfcf8dc41955021485ae0b53836a4438edd9fb474ce48ea6abc8c2f862a",
  },
  {
    file: "OpsContactRequirementNew.vue",
    frames: 16,
    errors: 0,
    headSha256: "d9fca2775e838e22d9d5b4e03f01fd2572455f7f732b92043a5f23b8a4c1b4ec",
  },
  {
    file: "OpsContactRequirementTemplate.vue",
    frames: 15,
    errors: 15,
    headSha256: "fb0b1129f55f0c188d04d7bee23df3fcb00996156f6aed01fb1e69aea4def8e1",
  },
])

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

const reconstructHeadSource = (migratedSource, caller) => {
  migratedSource = peelCadenceInlineWarnings(migratedSource, caller.file)
  assert.equal(occurrences(migratedSource, cadenceFieldImport), 1, `${caller.file} import count`)

  let reconstructedFrames = 0
  const reconstructed = peelCadenceValidationMessages(
    peelCadenceDetailsFrames(
      migratedSource,
      cadenceDetailsFrameCounts[caller.file] ?? 0,
      caller.file,
    ),
  )
    .replace(cadenceFieldImport, "")
    .replace(cadenceFieldFrame, (_match, indent, controlId, label, body) => {
      let control = body
      let originalErrors = ""
      const errorsOpen = `\n${indent}  <template #errors>\n`
      const errorsStart = body.indexOf(errorsOpen)

      if (errorsStart !== -1) {
        const errorsClose = `\n${indent}  </template>`
        assert.ok(body.endsWith(errorsClose), `${caller.file} errors slot closes exactly`)
        control = body.slice(0, errorsStart)
        const errorSource = body.slice(errorsStart + errorsOpen.length, -errorsClose.length)
        assert.ok(errorSource.startsWith(`${indent}    `), `${caller.file} error stays caller-owned`)
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

  assert.equal(reconstructedFrames, caller.frames, `${caller.file} reconstructs every frame`)
  assert.equal(
    sha256(reconstructed),
    caller.headSha256,
    `${caller.file} reconstructs byte-for-byte to its HEAD source`,
  )
}

const sources = new Map(
  await Promise.all(
    callers.map(async (caller) => [caller.file, await readFile(resolve(vueDirectory, caller.file), "utf8")]),
  ),
)

for (const caller of callers) {
  const source = sources.get(caller.file)

  assert.equal(occurrences(source, cadenceFieldImport), 1, `${caller.file} exact import count`)
  assert.equal(occurrences(source, "<CadenceField\n"), caller.frames, `${caller.file} open count`)
  assert.equal(occurrences(source, "</CadenceField>"), caller.frames, `${caller.file} close count`)
  assert.equal(
    occurrences(source, 'wrapper-class="fieldset mb-3"'),
    caller.frames,
    `${caller.file} wrapper-class count`,
  )
  assert.equal(
    occurrences(source, '<template #errors>'),
    caller.errors,
    `${caller.file} errors slot count`,
  )
  assert.doesNotMatch(
    source,
    /<div class="fieldset(?: mb-3)?">\n\s*<label :for=/,
    `${caller.file} has no residual eligible literal shell`,
  )
  reconstructHeadSource(source, caller)
}

assert.equal(callers.reduce((total, caller) => total + caller.frames, 0), 37)

const excludedTemplateShells = Object.freeze([
  {
    opening:
      '                <div v-if="template.schedule_type === \'fixed_interval\'" class="fieldset mb-3">',
    sha256: "8ad81f11066c873ca5def0f0125da0aebe6a1567031c14cbf2a32cb594c31c27",
  },
  {
    opening: '                <div v-if="template.schedule_type === \'daily\'" class="fieldset mb-3">',
    sha256: "ccae25ad696e485d123c33fbbc07cc0c45b4861fac4b1cc1d4ebb9fc0b745f32",
  },
  {
    opening: `                <div
                  v-if="['minimum_duration', 'minimum_data_volume'].includes(template.success_measure)"
                  class="fieldset mb-3"
                >`,
    sha256: "0c1407e2c01e6d791343fb41b901e2aae24e1349fb3853f403651fcd6cff8715",
  },
  {
    opening:
      '                <div v-if="template.success_measure === \'minimum_data_volume\'" class="fieldset mb-3">',
    sha256: "99c0e57be2de40bd823efd80291ba54e267d0125d3f6f5aa02229d1a74361805",
  },
])

const templateSource = sources.get("OpsContactRequirementTemplate.vue")
const templatePredecessorSource = peelCadenceValidationMessages(
  peelCadenceDetailsFrames(
    peelCadenceInlineWarnings(templateSource, "OpsContactRequirementTemplate.vue"),
    cadenceDetailsFrameCounts["OpsContactRequirementTemplate.vue"],
    "OpsContactRequirementTemplate.vue",
  ),
)
for (const excluded of excludedTemplateShells) {
  assert.equal(
    occurrences(templatePredecessorSource, excluded.opening),
    1,
    "excluded conditional shell remains once",
  )
  const start = templatePredecessorSource.indexOf(excluded.opening)
  const close = "\n                </div>"
  const end = templatePredecessorSource.indexOf(close, start)

  assert.notEqual(end, -1, "excluded conditional shell remains closed")
  assert.equal(
    sha256(templatePredecessorSource.slice(start, end + close.length)),
    excluded.sha256,
    "excluded conditional shell remains byte-for-byte unchanged",
  )
}
assert.equal(occurrences(templatePredecessorSource, '<label :for="template_form.fields.'), 4)

const dom = installDom('<div id="contact-field-compile"></div>')
try {
  const compiledCallers = await Promise.all(
    callers.map((caller) => loadSfc(resolve(vueDirectory, caller.file))),
  )

  for (const [index, compiled] of compiledCallers.entries()) {
    assert.equal(typeof compiled.component, "object", `${callers[index].file} compiles to a component`)
    assert.ok(compiled.descriptor.scriptSetup, `${callers[index].file} keeps script setup`)
    assert.ok(compiled.descriptor.template, `${callers[index].file} keeps its real template`)
  }
} finally {
  dom.window.close()
}

console.log("field_contact_migration_test passed (37 fields, 4 real SFCs, 4 exclusions)")

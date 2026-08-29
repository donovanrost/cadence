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
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const componentImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const cadenceFieldImport = 'import CadenceField from "./ui/components/CadenceField.vue"\n'
const tableFrameImport =
  'import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n'
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
const tableFrameBoundaries = Object.freeze({
  "apps/cadence_web/assets/vue/SpacecraftTypeShow.vue": Object.freeze({
    frameOpening:
      '        <CadenceTableFrame id="spacecraft-profile-version-history" class="mt-3">',
    tableOpening:
      '        <table id="spacecraft-profile-version-history" class="table mt-3">',
    frameClosing: "        </CadenceTableFrame>",
    tableClosing: "        </table>",
  }),
  "apps/cadence_web/assets/vue/MissionOverview.vue": Object.freeze({
    frameOpening: '        <CadenceTableFrame v-else id="mission-spacecraft-readiness">',
    tableOpening: '        <table v-else id="mission-spacecraft-readiness" class="table">',
    frameClosing: "        </CadenceTableFrame>",
    tableClosing: "        </table>",
  }),
})
const cadenceFieldBoundaries = Object.freeze({
  "apps/cadence_web/assets/vue/SpacecraftNew.vue": Object.freeze([
    Object.freeze({name: "display name", indent: "        ", fieldKey: "display_name"}),
    Object.freeze({name: "SCID", indent: "        ", fieldKey: "scid"}),
    Object.freeze({
      name: "spacecraft type",
      indent: "        ",
      fieldKey: "spacecraft_type_id",
      multilineLabel: true,
    }),
  ]),
  "apps/cadence_web/assets/vue/SpacecraftEdit.vue": Object.freeze([
    Object.freeze({name: "display name", indent: "        ", fieldKey: "display_name"}),
    Object.freeze({name: "SCID", indent: "        ", fieldKey: "scid"}),
    Object.freeze({
      name: "spacecraft type",
      indent: "        ",
      fieldKey: "spacecraft_type_id",
      multilineLabel: true,
    }),
  ]),
  "apps/cadence_web/assets/vue/MissionNew.vue": Object.freeze([
    Object.freeze({name: "display name", indent: "      ", fieldKey: "display_name"}),
    Object.freeze({name: "slug", indent: "      ", fieldKey: "slug"}),
  ]),
})

function occurrences(source, needle) {
  return source.split(needle).length - 1
}

function sha256(source) {
  return createHash("sha256").update(source).digest("hex")
}

function peelCadenceBreadcrumbs(source, label) {
  const importCount = occurrences(source, breadcrumbsImport)
  const openingCount = occurrences(source, "<CadenceBreadcrumbs>")
  const closingCount = occurrences(source, "</CadenceBreadcrumbs>")

  if (importCount === 0) {
    assert.equal(openingCount, 0, `${label} has no unimported breadcrumb opening`)
    assert.equal(closingCount, 0, `${label} has no unimported breadcrumb closing`)
    return source
  }

  assert.equal(importCount, 1, `${label} has one exact breadcrumb import`)
  assert.equal(openingCount, 1, `${label} has one exact breadcrumb opening`)
  assert.equal(closingCount, 1, `${label} has one exact breadcrumb closing`)

  const openingMatch = source.match(/^( *)<CadenceBreadcrumbs>$/m)
  assert.ok(openingMatch, `${label} has an explicitly bounded breadcrumb opening`)
  const indent = openingMatch[1]
  const wrapperOpening = `${indent}<CadenceBreadcrumbs>`
  const wrapperClosing = `${indent}</CadenceBreadcrumbs>`
  const nativeOpening = `${indent}<nav
${indent}  aria-label="Breadcrumb"
${indent}  class="${breadcrumbNavClass}"
${indent}>`

  assert.equal(occurrences(source, wrapperOpening), 1, `${label} opening indentation is exact`)
  assert.equal(occurrences(source, wrapperClosing), 1, `${label} closing indentation is exact`)

  const peeled = source
    .replace(breadcrumbsImport, "")
    .replace(wrapperOpening, nativeOpening)
    .replace(wrapperClosing, `${indent}</nav>`)

  assert.equal(occurrences(peeled, "CadenceBreadcrumbs"), 0, `${label} breadcrumb peel is exact`)
  return peeled
}

function cadenceFieldOpening(boundary) {
  const expression = `form.fields.${boundary.fieldKey}`
  return `${boundary.indent}<CadenceField
${boundary.indent}  :control-id="${expression}.id"
${boundary.indent}  wrapper-class="fieldset mb-3"
${boundary.indent}  :label="${expression}.label"
${boundary.indent}  label-class="hud-label block mb-1.5"
${boundary.indent}>`
}

function cadenceFieldLabel(boundary) {
  const expression = `form.fields.${boundary.fieldKey}.label`
  if (!boundary.multilineLabel) {
    return `${boundary.indent}    <span class="hud-label block mb-1.5">{{ ${expression} }}</span>`
  }

  return `${boundary.indent}    <span class="hud-label block mb-1.5">
${boundary.indent}      {{ ${expression} }}
${boundary.indent}    </span>`
}

function peelCadenceField(source, caller) {
  const boundaries = cadenceFieldBoundaries[caller]
  if (!boundaries) return source

  assert.equal(occurrences(source, cadenceFieldImport), 1, "expected exactly one field import")
  assert.equal(
    source.match(/^import CadenceField\b/gm)?.length,
    1,
    "expected exactly one field import declaration",
  )
  assert.equal(
    source.match(/<CadenceField\b/g)?.length,
    boundaries.length,
    "expected the exact compatible field-frame inventory",
  )

  let peeled = source.replace(cadenceFieldImport, "")
  for (const boundary of boundaries) {
    const opening = cadenceFieldOpening(boundary)
    assert.equal(occurrences(peeled, opening), 1, `expected one exact ${boundary.name} opening`)

    const start = peeled.indexOf(opening)
    const closing = `\n${boundary.indent}</CadenceField>`
    const end = peeled.indexOf(closing, start + opening.length)
    assert.notEqual(end, -1, `expected one exact ${boundary.name} closing`)

    const callerOwnedControl = peeled.slice(start + opening.length, end)
    const originalControl = callerOwnedControl.replaceAll(
      `\n${boundary.indent}  `,
      `\n${boundary.indent}    `,
    )
    const expression = `form.fields.${boundary.fieldKey}`
    const original = `${boundary.indent}<div class="fieldset mb-3">
${boundary.indent}  <label :for="${expression}.id">
${cadenceFieldLabel(boundary)}${originalControl}
${boundary.indent}  </label>
${boundary.indent}</div>`

    peeled = peeled.slice(0, start) + original + peeled.slice(end + closing.length)
  }

  assert.doesNotMatch(peeled, /CadenceField/)
  return peeled
}

function peelTableFrame(source, caller) {
  const boundary = tableFrameBoundaries[caller]
  if (!boundary) return source

  assert.equal(occurrences(source, tableFrameImport), 1, "expected exactly one table import")
  assert.equal(
    source.match(/^import CadenceTableFrame\b/gm)?.length,
    1,
    "expected exactly one table import declaration",
  )
  assert.equal(
    source.match(/<CadenceTableFrame\b/g)?.length,
    1,
    "expected exactly one table frame",
  )
  assert.equal(occurrences(source, boundary.frameClosing), 1, "expected one table-frame closing")
  assert.equal(occurrences(source, boundary.frameOpening), 1, "expected one exact table opening")

  const peeled = source
    .replace(tableFrameImport, "")
    .replace(boundary.frameOpening, boundary.tableOpening)
    .replace(boundary.frameClosing, boundary.tableClosing)

  assert.doesNotMatch(peeled, /CadenceTableFrame/)
  return peeled
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
      const reconstructed = peelTableFrame(
        peelCadenceField(peelCadenceBreadcrumbs(source, caller), caller),
        caller,
      )
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

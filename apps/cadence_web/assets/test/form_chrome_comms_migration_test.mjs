import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion} from "./reka_adapter_test_support.mjs"
import {peelCadenceNoticeFrames} from "./notice_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Comms form-chrome migration contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const breadcrumbsImport =
  'import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"\n'
const cadenceDetailsFrameImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const breadcrumbNavClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const actionWrapperClass = "flex items-center gap-3 border-t border-base-300/60 pt-5"
const pageHeaderImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n'
const reconstructPageHeaderSource = (source) =>
  source
    .replace(pageHeaderImport, "")
    .replace(
      '<CadencePageHeaderFrame variant="compact">',
      '<header class="border-b border-primary/20 pb-4">',
    )
    .replace(
      '<CadencePageHeaderFrame variant="ops">',
      '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
    )
    .replace("</CadencePageHeaderFrame>", "</header>")
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const rawReviewShell = `        <section
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-0">`
const imports = Object.freeze([
  'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"',
  'import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"',
])

const header = (
  key,
  numberExpression,
  titleExpression,
  {indent = 8, multilineNumber = false, dividerClass = "flex-1 h-px bg-base-300/60"} = {},
) => ({key, numberExpression, titleExpression, indent, multilineNumber, dividerClass})

const manifests = Object.freeze([
  Object.freeze({
    filename: "CommsProviderNew.vue",
    foundationHash: "f93e0166e7044a6e37b8a721b542d7eb39944c7dfcc6a274adc77fe042ee9094",
    cardCount: 0,
    formOpen: '<form v-else :id="form.id" class="space-y-8" @submit.prevent="save">',
    nativeTagCounts: Object.freeze({form: 1, button: 1, a: 3, input: 3, select: 3}),
    headers: Object.freeze([
      header("binding", "form.sections.binding.number", "form.sections.binding.title"),
      header(
        "resource-scope",
        "form.sections.resource_scope.number",
        "form.sections.resource_scope.title",
        {multilineNumber: true},
      ),
      header(
        "delivery-policy",
        "form.sections.delivery_policy.number",
        "form.sections.delivery_policy.title",
        {multilineNumber: true},
      ),
    ]),
  }),
  Object.freeze({
    filename: "CommsRoutingNew.vue",
    foundationHash: "2255683f05974961d89361772a97e53d6b607d5049f3320c8467e66838242e3d",
    cardCount: 0,
    formOpen: '<form :id="form.id" class="space-y-8" @submit.prevent="save">',
    nativeTagCounts: Object.freeze({form: 1, button: 1, a: 2, input: 2, select: 4}),
    headers: Object.freeze([
      header("intent", "form.sections.intent.number", "form.sections.intent.title"),
      header("transport", "form.sections.transport.number", "form.sections.transport.title"),
      header("policy", "form.sections.policy.number", "form.sections.policy.title"),
    ]),
  }),
  Object.freeze({
    filename: "CommsTransportNew.vue",
    foundationHash: "f78d6f7e72e0fd01248a2adf39054030015f363fa25c588f848f3dc9a909cb20",
    cardCount: 1,
    formOpen: '<form :id="form.id" class="space-y-8" @submit.prevent="save">',
    nativeTagCounts: Object.freeze({form: 1, button: 1, a: 3, input: 5, select: 6}),
    headers: Object.freeze([
      header("identity", "form.sections.identity.number", "form.sections.identity.title"),
      header("origin", "form.sections.origin.number", "form.sections.origin.title"),
      header("source", "form.sections.source.number", "form.sections.source.title"),
      header("direct-configuration", "section.number", "section.title", {indent: 10}),
      header(
        "provider-capability",
        "form.sections.provider_capability.number",
        "form.sections.provider_capability.title",
        {indent: 10, multilineNumber: true},
      ),
      header(
        "provider-derived",
        "form.provider_derived.number",
        "form.provider_derived.title",
        {indent: 10, dividerClass: "h-px flex-1 bg-base-300/60"},
      ),
      header(
        "review",
        "form.sections.review.number",
        "form.sections.review.title",
        {dividerClass: "h-px flex-1 bg-base-300/60"},
      ),
    ]),
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1
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

const peelCadenceBreadcrumbs = (source, label) => {
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

const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'
const migratedDataRowOpening = `                <CadenceDataRow
                  v-for="row in form.provider_derived.configuration.rows"
                  :key="row.label"
                  row-class="hud-data-row"
                  label-class="hud-data-label"
                  :label="row.label"
                >`
const foundationDataRowOpening = `                <div
                  v-for="row in form.provider_derived.configuration.rows"
                  :key="row.label"
                  class="hud-data-row"
                >
                  <span class="hud-data-label">{{ row.label }}</span>`

const replaceOnce = (source, migrated, foundation, description) => {
  assert.equal(occurrences(source, migrated), 1, `${description} is inventoried exactly once`)
  return source.replace(migrated, foundation)
}

const reconstructCards = (source, manifest) => {
  const expectedImportCount = manifest.cardCount === 0 ? 0 : 1
  assert.equal(
    occurrences(source, cardImport),
    expectedImportCount,
    `${manifest.filename} has its exact CadenceCard import count`,
  )
  assert.equal(
    source.match(/<CadenceCard\b/g)?.length ?? 0,
    manifest.cardCount,
    `${manifest.filename} has its exact CadenceCard opening count`,
  )
  assert.equal(
    occurrences(source, "</CadenceCard>"),
    manifest.cardCount,
    `${manifest.filename} has its exact CadenceCard closing count`,
  )
  assert.equal(
    occurrences(source, 'body-class="card-body p-6"'),
    manifest.cardCount,
    `${manifest.filename} has one exact p-6 body boundary per card`,
  )

  if (manifest.filename === "CommsTransportNew.vue") {
    assert.equal(occurrences(source, rawReviewShell), 1, "the raw p-0 review card stays exact")
  }

  let openingCount = 0
  let reconstructed = source.replace(cardImport, "")

  reconstructed = reconstructed.replace(
    /^([ \t]*)<CadenceCard\b([^>]*)>\n/gm,
    (_opening, indentation, rawAttributes) => {
      openingCount += 1
      assert.equal(
        occurrences(rawAttributes, 'body-class="card-body p-6"'),
        1,
        `${manifest.filename} card boundary ${openingCount} owns one exact body class`,
      )

      const sectionAttributes = rawAttributes
        .replace(/\n[ \t]*body-class="card-body p-6"/, "")
        .replace(/ body-class="card-body p-6"/, "")

      assert.doesNotMatch(sectionAttributes, /body-class=/)
      return (
        `${indentation}<section${sectionAttributes}>\n` +
        `${indentation}  <div class="card-body p-6">\n`
      )
    },
  )

  assert.equal(openingCount, manifest.cardCount, `${manifest.filename} reconstructs every card opening`)

  let closingCount = 0
  reconstructed = reconstructed.replace(/^([ \t]*)<\/CadenceCard>$/gm, (_closing, indentation) => {
    closingCount += 1
    return `${indentation}  </div>\n${indentation}</section>`
  })

  assert.equal(closingCount, manifest.cardCount, `${manifest.filename} reconstructs every card closing`)

  if (manifest.filename === "CommsTransportNew.vue") {
    assert.equal(
      occurrences(reconstructed, rawReviewShell),
      1,
      "the pre-card source keeps the raw p-0 review card",
    )
  }

  assert.doesNotMatch(
    reconstructed,
    /CadenceCard/,
    `${manifest.filename} pre-card source has no residual primitive`,
  )
  return reconstructed
}

const reconstructDataRow = (source) => {
  assert.equal(occurrences(source, dataRowImport), 1, "the transport imports CadenceDataRow once")
  assert.equal(
    occurrences(source, migratedDataRowOpening),
    1,
    "the transport has exactly one migrated data-row opening boundary",
  )
  assert.equal(
    occurrences(source, "</CadenceDataRow>"),
    1,
    "the transport has exactly one migrated data-row closing boundary",
  )

  const reconstructed = source
    .replace(dataRowImport, "")
    .replace(migratedDataRowOpening, foundationDataRowOpening)
    .replace("</CadenceDataRow>", "</div>")

  assert.doesNotMatch(reconstructed, /CadenceDataRow/, "the pre-data-row source has no residual primitive")
  return reconstructed
}

const migratedHeader = ({numberExpression, titleExpression, indent, dividerClass}) => {
  const spaces = " ".repeat(indent)
  return `${spaces}<CadenceFormSectionHeader
${spaces}  wrapper-class="flex items-center gap-3"
${spaces}  :number="${numberExpression}"
${spaces}  number-class="hud-label text-primary/70"
${spaces}  :title="${titleExpression}"
${spaces}  title-class="hud-label"
${spaces}  divider-class="${dividerClass}"
${spaces}/>`
}

const foundationHeader = ({numberExpression, titleExpression, indent, multilineNumber, dividerClass}) => {
  const spaces = " ".repeat(indent)
  const number = multilineNumber
    ? `
${spaces}    {{ ${numberExpression} }}
${spaces}  `
    : `{{ ${numberExpression} }}`

  return `${spaces}<div class="flex items-center gap-3">
${spaces}  <span class="hud-label text-primary/70">${number}</span>
${spaces}  <h2 class="hud-label">{{ ${titleExpression} }}</h2>
${spaces}  <div class="${dividerClass}"></div>
${spaces}</div>`
}

assert.equal(manifests.length, 3, "all three exclusively owned Comms features are inventoried")
assert.equal(
  manifests.reduce((count, manifest) => count + manifest.headers.length, 0),
  13,
  "all thirteen exact section-header call sites are inventoried",
)

for (const manifest of manifests) {
  const componentPath = resolve(testDirectory, `../vue/${manifest.filename}`)
  const source = await readFile(componentPath, "utf8")

  for (const importLine of imports) {
    assert.equal(occurrences(source, `${importLine}\n`), 1, `${manifest.filename} owns ${importLine}`)
  }

  assert.equal(
    occurrences(source, "<CadenceFormSectionHeader\n"),
    manifest.headers.length,
    `${manifest.filename} has no unlisted section-header migrations`,
  )
  assert.equal(
    occurrences(source, `<CadenceFormActions wrapper-class="${actionWrapperClass}">`),
    1,
    `${manifest.filename} has its one exact action-wrapper migration`,
  )
  assert.equal(
    occurrences(source, '<div class="flex items-center gap-3">'),
    0,
    `${manifest.filename} retains no repeated native section-header wrapper`,
  )
  assert.equal(
    occurrences(source, `<div class="${actionWrapperClass}">`),
    0,
    `${manifest.filename} retains no repeated native action wrapper`,
  )

  for (const [tag, expectedCount] of Object.entries(manifest.nativeTagCounts)) {
    assert.equal(
      source.match(new RegExp(`<${tag}\\b`, "g"))?.length ?? 0,
      expectedCount,
      `${manifest.filename} keeps every native ${tag} call site in the caller`,
    )
  }

  assert.equal(occurrences(source, manifest.formOpen), 1, `${manifest.filename} keeps parent save authority`)
  const formStart = source.indexOf(manifest.formOpen)
  const formEnd = source.indexOf("    </form>", formStart)
  assert.ok(formStart >= 0 && formEnd > formStart, `${manifest.filename} retains its caller-owned form`)
  const formSource = source.slice(formStart, formEnd)
  const actionsStart = formSource.indexOf(
    `<CadenceFormActions wrapper-class="${actionWrapperClass}">`,
  )
  const actionsEnd = formSource.indexOf("</CadenceFormActions>", actionsStart)
  assert.ok(
    actionsStart >= 0 && actionsEnd > actionsStart,
    `${manifest.filename} keeps the action boundary inside the parent form`,
  )
  const actionsSource = formSource.slice(actionsStart, actionsEnd)
  assert.match(actionsSource, /<button\b/, `${manifest.filename} keeps the native button in the caller`)
  assert.match(actionsSource, /<a\b/, `${manifest.filename} keeps the native anchor in the caller`)
  assert.match(actionsSource, /:id="form\.actions\.submit\.id"/)
  assert.match(actionsSource, /type="submit"/)
  assert.match(actionsSource, /:id="form\.actions\.cancel\.id"/)
  assert.match(actionsSource, /:href="form\.actions\.cancel\.href"/)
  assert.match(actionsSource, /data-phx-link="redirect"/)
  assert.match(actionsSource, /data-phx-link-state="push"/)

  const preCardSource = reconstructCards(
    reconstructPageHeaderSource(
      peelCadenceBreadcrumbs(
        peelCadenceDetailsFrames(
          peelCadenceNoticeFrames(source, manifest.filename),
          manifest.filename === "CommsTransportNew.vue" ? 1 : 0,
          manifest.filename,
        ),
        manifest.filename,
      ),
    ),
    manifest,
  )
  let reconstructed =
    manifest.filename === "CommsTransportNew.vue"
      ? reconstructDataRow(preCardSource)
      : preCardSource
  for (const importLine of imports) {
    reconstructed = replaceOnce(
      reconstructed,
      `${importLine}\n`,
      "",
      `${manifest.filename} ${importLine}`,
    )
  }
  for (const site of manifest.headers) {
    reconstructed = replaceOnce(
      reconstructed,
      migratedHeader(site),
      foundationHeader(site),
      `${manifest.filename} ${site.key} section header`,
    )
  }

  reconstructed = replaceOnce(
    reconstructed,
    `      <CadenceFormActions wrapper-class="${actionWrapperClass}">`,
    `      <div class="${actionWrapperClass}">`,
    `${manifest.filename} action wrapper opening`,
  )
  reconstructed = replaceOnce(
    reconstructed,
    "      </CadenceFormActions>",
    "      </div>",
    `${manifest.filename} action wrapper closing`,
  )

  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    manifest.foundationHash,
    `${manifest.filename} reconstructs its immutable foundation-base source byte-for-byte`,
  )
}

console.log("form_chrome_comms_migration_test passed")

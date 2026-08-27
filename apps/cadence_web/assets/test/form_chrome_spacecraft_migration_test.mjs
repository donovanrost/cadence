import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion, integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `spacecraft form-chrome migration contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const {parse} = integrationRequire("@vue/compiler-sfc")
const formChromeImports =
  'import CadenceFormActions from "./ui/components/CadenceFormActions.vue"\n' +
  'import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"\n'
const actionOpen =
  '      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">'
const originalActionOpen =
  '      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">'

const singleLineHeader = (indent, expression, dividerClass) =>
  `${indent}<div class="flex items-center gap-3">
${indent}  <span class="hud-label text-primary/70">{{ ${expression}.number }}</span>
${indent}  <h2 class="hud-label">{{ ${expression}.title }}</h2>
${indent}  <div class="${dividerClass}"></div>
${indent}</div>`

const multilineNumberHeader = (indent, expression, dividerClass) =>
  `${indent}<div class="flex items-center gap-3">
${indent}  <span class="hud-label text-primary/70">
${indent}    {{ ${expression}.number }}
${indent}  </span>
${indent}  <h2 class="hud-label">{{ ${expression}.title }}</h2>
${indent}  <div class="${dividerClass}"></div>
${indent}</div>`

const migratedHeader = ({indent, expression, dividerClass}) =>
  `${indent}<CadenceFormSectionHeader
${indent}  wrapper-class="flex items-center gap-3"
${indent}  :number="${expression}.number"
${indent}  number-class="hud-label text-primary/70"
${indent}  :title="${expression}.title"
${indent}  title-class="hud-label"
${indent}  divider-class="${dividerClass}"
${indent}/>`

const header = (callSite, indent, expression, dividerClass, original) => ({
  callSite,
  indent,
  expression,
  dividerClass,
  original,
})

const fixtures = Object.freeze([
  {
    name: "ProviderAccountNew",
    path: "../vue/ProviderAccountNew.vue",
    foundationSha256: "89b6a7351c5da7f8226a3289542a60637dfdfe928172bbfadc035b790c410f96",
    headers: [
      header(
        "network identity",
        "        ",
        "form.sections.network_identity",
        "h-px flex-1 bg-base-300/60",
        singleLineHeader(
          "        ",
          "form.sections.network_identity",
          "h-px flex-1 bg-base-300/60",
        ),
      ),
      header(
        "connector configuration section",
        "          ",
        "section",
        "h-px flex-1 bg-base-300/60",
        singleLineHeader("          ", "section", "h-px flex-1 bg-base-300/60"),
      ),
      header(
        "credential registry",
        "        ",
        "form.sections.credential_registry",
        "h-px flex-1 bg-base-300/60",
        multilineNumberHeader(
          "        ",
          "form.sections.credential_registry",
          "h-px flex-1 bg-base-300/60",
        ),
      ),
      header(
        "organization guardrails",
        "        ",
        "form.sections.organization_guardrails",
        "h-px flex-1 bg-base-300/60",
        multilineNumberHeader(
          "        ",
          "form.sections.organization_guardrails",
          "h-px flex-1 bg-base-300/60",
        ),
      ),
    ],
    controls: {input: 5, select: 3, textarea: 1, button: 1},
    vModels: 8,
    inputEvents: 5,
    changeEvents: 3,
    validateChangeEvents: 3,
    hiddenControls: 1,
  },
  {
    name: "SpacecraftTypeNew",
    path: "../vue/SpacecraftTypeNew.vue",
    foundationSha256: "6f5e826e748fa60f8629de201e3f8bf8408b61b7b4df98a388e6f0b8411aab66",
    headers: [
      header(
        "identity",
        "        ",
        "form.sections.identity",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.identity", "flex-1 h-px bg-base-300/60"),
      ),
      header(
        "protocols",
        "        ",
        "form.sections.protocols",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.protocols", "flex-1 h-px bg-base-300/60"),
      ),
      header(
        "frame parameters",
        "        ",
        "form.sections.frame_parameters",
        "flex-1 h-px bg-base-300/60",
        multilineNumberHeader(
          "        ",
          "form.sections.frame_parameters",
          "flex-1 h-px bg-base-300/60",
        ),
      ),
      header(
        "applications",
        "        ",
        "form.sections.applications",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader(
          "        ",
          "form.sections.applications",
          "flex-1 h-px bg-base-300/60",
        ),
      ),
    ],
    controls: {input: 5, select: 4, textarea: 0, button: 1},
    vModels: 8,
    inputEvents: 4,
    changeEvents: 5,
    validateChangeEvents: 4,
    hiddenControls: 0,
  },
  {
    name: "SpacecraftNew",
    path: "../vue/SpacecraftNew.vue",
    foundationSha256: "41a9185c02bd41ef59596e7fb3b1d6e9f147f1b651c30d8db390caa2d0ac1d3d",
    headers: [
      header(
        "identity",
        "        ",
        "form.sections.identity",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.identity", "flex-1 h-px bg-base-300/60"),
      ),
      header(
        "profile",
        "        ",
        "form.sections.profile",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.profile", "flex-1 h-px bg-base-300/60"),
      ),
    ],
    controls: {input: 2, select: 1, textarea: 0, button: 1},
    vModels: 3,
    inputEvents: 2,
    changeEvents: 1,
    validateChangeEvents: 1,
    hiddenControls: 0,
  },
  {
    name: "SpacecraftEdit",
    path: "../vue/SpacecraftEdit.vue",
    foundationSha256: "bac07e262bdb52c6b02518e812607c357ee164c9ee72678d5188838bf5174bd3",
    headers: [
      header(
        "identity",
        "        ",
        "form.sections.identity",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.identity", "flex-1 h-px bg-base-300/60"),
      ),
      header(
        "profile",
        "        ",
        "form.sections.profile",
        "flex-1 h-px bg-base-300/60",
        singleLineHeader("        ", "form.sections.profile", "flex-1 h-px bg-base-300/60"),
      ),
    ],
    controls: {input: 2, select: 1, textarea: 0, button: 1},
    vModels: 3,
    inputEvents: 2,
    changeEvents: 1,
    validateChangeEvents: 1,
    hiddenControls: 0,
  },
])

const occurrences = (source, fragment) => source.split(fragment).length - 1
const tagCount = (source, tag) => source.match(new RegExp(`<${tag}\\b`, "g"))?.length ?? 0

assert.equal(fixtures.length, 4, "all four owned feature sources are inventoried")
assert.equal(
  fixtures.reduce((count, fixture) => count + fixture.headers.length, 0),
  12,
  "all twelve migrated section-header call sites are inventoried",
)

for (const fixture of fixtures) {
  const componentPath = resolve(testDirectory, fixture.path)
  const source = await readFile(componentPath, "utf8")
  const parsed = parse(source, {filename: componentPath})

  assert.deepEqual(parsed.errors, [], `${fixture.name} parses with the pinned Vue compiler`)
  assert.equal(occurrences(source, formChromeImports), 1, `${fixture.name} owns both new imports`)
  assert.equal(
    occurrences(source, "<CadenceFormSectionHeader"),
    fixture.headers.length,
    `${fixture.name} has its complete section-header inventory`,
  )
  assert.equal(occurrences(source, actionOpen), 1, `${fixture.name} has its one action wrapper`)
  assert.equal(occurrences(source, "</CadenceFormActions>"), 1)

  let reconstructedSource = source.replace(formChromeImports, "")

  for (const sectionHeader of fixture.headers) {
    const migrated = migratedHeader(sectionHeader)
    assert.equal(
      occurrences(reconstructedSource, migrated),
      1,
      `${fixture.name} inventories the ${sectionHeader.callSite} header exactly once`,
    )
    reconstructedSource = reconstructedSource.replace(migrated, sectionHeader.original)
  }

  reconstructedSource = reconstructedSource
    .replace(actionOpen, originalActionOpen)
    .replace("      </CadenceFormActions>", "      </div>")

  assert.doesNotMatch(
    reconstructedSource,
    /CadenceForm(?:SectionHeader|Actions)/,
    `${fixture.name} reconstruction removes only the new transparent boundaries and imports`,
  )
  assert.equal(
    createHash("sha256").update(reconstructedSource).digest("hex"),
    fixture.foundationSha256,
    `${fixture.name} reconstructs its immutable 9e3e7ad foundation source byte-for-byte`,
  )

  for (const [tag, expectedCount] of Object.entries(fixture.controls)) {
    assert.equal(
      tagCount(source, tag),
      expectedCount,
      `${fixture.name} keeps all native ${tag} controls caller-owned`,
    )
  }

  assert.equal(occurrences(source, 'v-model="'), fixture.vModels)
  assert.equal(occurrences(source, '@input="validate"'), fixture.inputEvents)
  assert.equal(occurrences(source, '@change="'), fixture.changeEvents)
  assert.equal(occurrences(source, '@change="validate"'), fixture.validateChangeEvents)
  assert.equal(occurrences(source, 'type="hidden"'), fixture.hiddenControls)
  assert.equal(
    occurrences(source, '<form :id="form.id" class="space-y-8" @submit.prevent="save">'),
    1,
    `${fixture.name} keeps the parent form and submit prevention caller-owned`,
  )
  assert.equal(
    occurrences(
      source,
      '<button :id="form.actions.submit.id" type="submit" class="btn btn-primary">',
    ),
    1,
    `${fixture.name} keeps its native submit control in the caller`,
  )
  assert.equal(
    occurrences(
      source,
      `        <a
          :id="form.actions.cancel.id"
          :href="form.actions.cancel.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
        >{{ form.actions.cancel.label }}</a>`,
    ),
    1,
    `${fixture.name} keeps its native redirect control and Phoenix attributes in the caller`,
  )
}

console.log("spacecraft form-chrome migration contracts passed")

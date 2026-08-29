import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  opsDataSourcesFieldImport,
  opsDataSourcesFieldPredecessorCommit,
  opsDataSourcesFields,
  peelOpsDataSourcesCadenceFields,
} from "./ops_data_sources_field_test_support.mjs"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `OpsDataSources CadenceField contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const componentPath = resolve(testDirectory, "../vue/OpsDataSources.vue")
const repositoryPath = "apps/cadence_web/assets/vue/OpsDataSources.vue"
const occurrences = (source, fragment) => source.split(fragment).length - 1
const dom = installDom('<div id="ops-data-sources-field-contract"></div>')
const [source, loaded] = await Promise.all([
  readFile(componentPath, "utf8"),
  loadSfc(componentPath),
])

assert.ok(loaded.component, "OpsDataSources compiles through the real local SFC resolver")
assert.ok(loaded.descriptor.scriptSetup, "OpsDataSources keeps its TypeScript setup authority")
assert.ok(loaded.descriptor.template, "OpsDataSources keeps its real template")
assert.equal(loaded.source, source, "the compiler sees the exact audited caller source")
assert.equal(opsDataSourcesFields.length, 11, "the bounded migration ledger has exactly 11 fields")
assert.deepEqual(
  opsDataSourcesFields.map(({id}) => id),
  [
    "source_data_source_id",
    "source_logical_source",
    "source_kind",
    "source_isolation_level",
    "source_credentials_ref",
    "source_credential_provider",
    "source_endpoint_ref",
    "source_material_env_profile",
    "source_http_endpoint_env",
    "source_storage",
    "binding_data_source_id",
  ],
  "the field order is frozen to the requested registration and binding boundaries",
)
assert.equal(occurrences(source, opsDataSourcesFieldImport), 1, "one normal CadenceField import")
assert.equal(occurrences(source, "<CadenceField\n"), 11, "exact CadenceField opening count")
assert.equal(occurrences(source, "</CadenceField>"), 11, "exact CadenceField closing count")
assert.equal(
  occurrences(source, 'wrapper-class="fieldset mb-3"'),
  11,
  "every boundary passes the exact wrapper class",
)
assert.equal(
  occurrences(source, 'label-class="hud-label block mb-1.5"'),
  11,
  "every boundary passes the exact label class",
)
assert.equal(source.match(/<input\b/g)?.length, 5, "all five native inputs remain in the caller")
assert.equal(source.match(/<select\b/g)?.length, 6, "all six native selects remain in the caller")

for (const boundary of opsDataSourcesFields) {
  assert.equal(
    occurrences(source, `control-id="${boundary.id}"`),
    1,
    `${boundary.id} has one literal control boundary`,
  )
  assert.equal(
    occurrences(source, `id="${boundary.id}"`),
    2,
    `${boundary.id} keeps one component association and one caller-owned native id`,
  )
  assert.equal(
    occurrences(source, `v-model="${boundary.model}"`),
    1,
    `${boundary.id} keeps its exact native v-model`,
  )
  assert.equal(
    occurrences(source, `name="${boundary.name}"`),
    1,
    `${boundary.id} keeps its exact native name`,
  )
}

assert.equal(occurrences(source, '<form\n            :id="page.admin.registration.form.id"'), 1)
assert.equal(occurrences(source, '@submit.prevent="submitRegistration"'), 1)
assert.equal(occurrences(source, '@submit.prevent="submitBinding"'), 1)
assert.equal(occurrences(source, "emit('cancel-register-source', {})"), 2)
assert.equal(occurrences(source, "emit('cancel-change-binding', {})"), 1)
assert.match(
  source,
  /v-for="row in group\.rows"[\s\S]*?:key="row\.binding_id"[\s\S]*?v-if="page\.admin\?\.binding_form\?\.binding_id === row\.binding_id"[\s\S]*?<CadenceField\n\s+control-id="binding_data_source_id"[\s\S]*?<\/CadenceField>\n\s+<p\n\s+v-if="page\.admin\.binding_form\.error"\n\s+:id="`change-binding-error-\$\{row\.binding_id\}`"/,
  "the binding field stays inside its keyed row condition with the adjacent error unchanged",
)

const predecessor = execFileSync(
  "git",
  ["-C", repositoryRoot, "show", `${opsDataSourcesFieldPredecessorCommit}:${repositoryPath}`],
  {encoding: "utf8"},
)
const reconstructed = peelOpsDataSourcesCadenceFields(source)

assert.equal(
  reconstructed,
  predecessor,
  "the 11 exact inverse boundaries reconstruct the base source byte-for-byte",
)
assert.doesNotMatch(reconstructed, /CadenceField/)

dom.window.close()
console.log("ops_data_sources_field_migration_test passed (11 exact native field boundaries)")

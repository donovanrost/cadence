import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {expectedNodeVersion, integrationRequire, loadSfc} from "./reka_adapter_test_support.mjs"
import {
  conditionalKeyedCadenceFieldBoundaries,
  conditionalKeyedFrozenHeadSha256,
  peelConditionalKeyedCadenceFields,
} from "./conditional_keyed_field_test_support.mjs"

assert.equal(process.execPath, "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node")
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(conditionalKeyedCadenceFieldBoundaries.length, 1)
assert.deepEqual(conditionalKeyedCadenceFieldBoundaries.map(({file}) => file), ["OpsDashboardNew.vue"])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const source = await readFile(resolve(testDirectory, "../vue/OpsDashboardNew.vue"), "utf8")
const predecessor = peelConditionalKeyedCadenceFields(source, "OpsDashboardNew.vue")

assert.equal(
  createHash("sha256").update(predecessor).digest("hex"),
  conditionalKeyedFrozenHeadSha256["OpsDashboardNew.vue"],
)
assert.equal(source.match(/import CadenceField from .*CadenceField\.vue/g)?.length, 1)

const {descriptor, component} = await loadSfc(resolve(testDirectory, "../vue/OpsDashboardNew.vue"))
assert.deepEqual(descriptor.errors ?? [], [])
assert.equal(typeof component.setup, "function")
assert.ok(descriptor.scriptSetup)
assert.ok(descriptor.template)

const {compileScript} = integrationRequire("@vue/compiler-sfc")
assert.doesNotThrow(() => compileScript(descriptor, {id: "ops-dashboard-new", inlineTemplate: true}))

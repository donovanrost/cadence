#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion} from "./reka_adapter_test_support.mjs"

assert.equal(process.execPath, "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node")
assert.equal(process.versions.node, expectedNodeVersion)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const source = await readFile(resolve(testDirectory, "../vue/CatalogIndex.vue"), "utf8")

assert.match(source, /<script setup lang="ts">/)
assert.match(source, /defineProps/)
assert.match(source, /<template>/)
assert.match(source, /props\.presentation\.card\.visible/)
assert.match(source, /props\.presentation\.card\.rows/)
assert.doesNotMatch(source, /<script>[^]*<\/script>/)

console.log("catalog_index_test passed (surviving index page contract)")

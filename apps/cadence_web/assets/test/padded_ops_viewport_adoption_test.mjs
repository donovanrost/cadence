#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
} from "./reka_adapter_test_support.mjs"
import {
  paddedOpsViewportCallerNames,
  paddedOpsViewportMigrationFor,
  paddedOpsViewportSha256,
  peelPaddedOpsViewport,
} from "./padded_ops_viewport_test_support.mjs"

assert.equal(process.execPath, "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node")
assert.equal(process.versions.node, expectedNodeVersion)
assert.deepEqual(paddedOpsViewportCallerNames, ["OpsDashboardShare.vue"])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const migration = paddedOpsViewportMigrationFor("OpsDashboardShare.vue")
const source = await readFile(resolve(testDirectory, "../vue", migration.file), "utf8")
const predecessor = peelPaddedOpsViewport(source, migration.file)

assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
assert.equal(paddedOpsViewportSha256(predecessor), migration.predecessorSha256)
assert.match(source, /<CadenceOpsViewport :id="share\.id" class="p-6">/)

console.log("padded_ops_viewport_adoption_test passed (one surviving caller)")

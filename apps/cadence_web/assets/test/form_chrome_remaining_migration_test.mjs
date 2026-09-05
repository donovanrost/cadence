#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {expectedNodeVersion} from "./reka_adapter_test_support.mjs"

assert.equal(process.execPath, "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node")
assert.equal(process.versions.node, expectedNodeVersion)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const callers = Object.freeze([
  {file: "AdminOrganizationInvite.vue", forms: 1, actions: 1},
  {file: "AdminOrganizationNew.vue", forms: 1, actions: 1},
  {file: "MissionNew.vue", forms: 1, actions: 1},
  {file: "OpsDashboardNew.vue", forms: 1, actions: 1},
])

for (const caller of callers) {
  const source = await readFile(resolve(vueDirectory, caller.file), "utf8")
  assert.equal(source.match(/import CadenceFormActions from/g)?.length ?? 0, caller.actions)
  assert.equal(source.match(/<CadenceFormActions\b/g)?.length ?? 0, caller.actions)
  assert.equal(source.match(/<form\b/g)?.length ?? 0, caller.forms)
  assert.match(source, /<button\b[^>]*type="submit"/)
  assert.match(source, /data-phx-link="redirect"/)
}

console.log("form_chrome_remaining_migration_test passed (4 surviving callers)")

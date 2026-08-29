import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  opsListFrameCallerNames,
  peelCadenceOpsListFrame,
} from "./ops_list_frame_test_support.mjs"
import {peelCadenceOpsViewport} from "./ops_viewport_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const base = "f9f36bb729e9f9abb1a2d01c3924bddf3d7eb99a"
const componentImport =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const testDirectory = dirname(fileURLToPath(import.meta.url))
const occurrences = (source, fragment) => source.split(fragment).length - 1
const patternCount = (source, pattern) => source.match(pattern)?.length ?? 0
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

assert.equal(process.execPath, pinnedNode)
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `fleet evidence details migration uses pinned Node ${expectedNodeVersion}`,
)

const callers = Object.freeze([
  Object.freeze({
    name: "OpsCommands.vue",
    baseBytes: 12768,
    baseSha256: "6e61589fb8879c3279b5963b6a46cb4933fc808b2b334c0c3b057a94cd0e2083",
    migratedOpening:
      '            <CadenceDetailsFrame class="xl:col-span-6 border-t border-base-300/50 pt-2">',
    nativeOpening:
      '            <details class="xl:col-span-6 border-t border-base-300/50 pt-2">',
    migratedClosing: "            </CadenceDetailsFrame>",
    nativeClosing: "            </details>",
  }),
  Object.freeze({
    name: "OpsFleetPlanningNew.vue",
    baseBytes: 9929,
    baseSha256: "6453a8524c7f00137bce534b5f46ce28a18ec257c106542261f44cc9020ee9a9",
    migratedOpening:
      '        <CadenceDetailsFrame :id="preview.details.id" class="border-t border-base-300">',
    nativeOpening: '        <details :id="preview.details.id" class="border-t border-base-300">',
    migratedClosing: "        </CadenceDetailsFrame>",
    nativeClosing: "        </details>",
  }),
  Object.freeze({
    name: "OpsFleetPlanningRun.vue",
    baseBytes: 22419,
    baseSha256: "11ff942f8d801ecf3a1e314ce1c5d1e1fb1559980c70c50bed5bf70f110f936f",
    migratedOpening: "              <CadenceDetailsFrame\n",
    nativeOpening: "              <details\n",
    migratedClosing: "              </CadenceDetailsFrame>",
    nativeClosing: "              </details>",
  }),
])

assert.equal(callers.length, 3, "the owned caller ledger remains exactly three files")
assert.equal(
  callers.reduce((count) => count + 1, 0),
  3,
  "the frozen migration target count remains exactly three roots",
)

for (const caller of callers) {
  const path = resolve(testDirectory, `../vue/${caller.name}`)
  const {component, descriptor, source} = await loadSfc(path)

  assert.equal(typeof component.setup, "function", `${caller.name}: actual SFC compiles`)
  assert.ok(descriptor.scriptSetup, `${caller.name}: setup script remains present`)
  assert.ok(descriptor.template, `${caller.name}: template remains present`)

  assert.equal(
    occurrences(source, componentImport),
    1,
    `${caller.name}: imports CadenceDetailsFrame exactly once`,
  )
  assert.equal(
    patternCount(source, /^import CadenceDetailsFrame\b/gm),
    1,
    `${caller.name}: has exactly one CadenceDetailsFrame import declaration`,
  )
  assert.equal(
    patternCount(source, /<CadenceDetailsFrame(?:\s|>)/g),
    1,
    `${caller.name}: has exactly one migrated details root`,
  )
  assert.equal(
    patternCount(source, /<\/CadenceDetailsFrame>/g),
    1,
    `${caller.name}: closes exactly one migrated details root`,
  )
  assert.equal(
    occurrences(source, caller.migratedOpening),
    1,
    `${caller.name}: preserves the exact target opening attributes`,
  )
  assert.equal(
    occurrences(source, caller.migratedClosing),
    1,
    `${caller.name}: has the exact target closing`,
  )
  assert.equal(
    patternCount(source, /<summary(?:\s|>)/g),
    1,
    `${caller.name}: preserves exactly one caller-owned summary opening`,
  )
  assert.equal(
    patternCount(source, /<\/summary>/g),
    1,
    `${caller.name}: preserves exactly one caller-owned summary closing`,
  )
  assert.doesNotMatch(
    source,
    /<\/?details(?:\s|>)/,
    `${caller.name}: excludes residual native details targets`,
  )

  const opsListCompatibleSource = opsListFrameCallerNames.includes(caller.name)
    ? peelCadenceOpsListFrame(source, caller.name)
    : source
  const reconstructed = peelCadenceOpsViewport(opsListCompatibleSource, caller.name)
    .replace(componentImport, "")
    .replace(caller.migratedOpening, caller.nativeOpening)
    .replace(caller.migratedClosing, caller.nativeClosing)

  assert.equal(
    occurrences(reconstructed, "CadenceDetailsFrame"),
    0,
    `${caller.name}: newest import and wrapper peel completely`,
  )
  assert.equal(
    patternCount(reconstructed, /<details(?:\s|>)/g),
    1,
    `${caller.name}: frozen predecessor target count is one opening`,
  )
  assert.equal(
    patternCount(reconstructed, /<\/details>/g),
    1,
    `${caller.name}: frozen predecessor target count is one closing`,
  )
  assert.equal(
    Buffer.byteLength(reconstructed),
    caller.baseBytes,
    `${caller.name}: reconstructed predecessor byte count is frozen`,
  )
  assert.equal(
    sha256(reconstructed),
    caller.baseSha256,
    `${caller.name}: newest-only peel reconstructs ${base} byte-for-byte`,
  )
}

console.log("details_fleet_evidence_migration_test passed (3 real SFCs, 3 roots)")

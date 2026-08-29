import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFileSync, realpathSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const parent = "f9f36bb729e9f9abb1a2d01c3924bddf3d7eb99a"
const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const importLine =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const componentClosing = "</CadenceDetailsFrame>"
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")

const callers = Object.freeze([
  Object.freeze({
    path: "apps/cadence_web/assets/vue/OpsFleetPlanningPolicy.vue",
    baseSha256: "eeeeeecf2d79a27ef6aeea3da5e472cc61e3162ff3f90e504e0aa759a308f6f4",
    baseDetailsCount: 4,
    controlledOpenings: Object.freeze([
      '        <details :open="policy_form.open">',
    ]),
    boundaries: Object.freeze([
      Object.freeze({
        componentOpening:
          '            <CadenceDetailsFrame :id="policy_form.redundancy.id" class="border border-base-300">',
        nativeOpening:
          '            <details :id="policy_form.redundancy.id" class="border border-base-300">',
        componentClosing: "            </CadenceDetailsFrame>",
        nativeClosing: "            </details>",
      }),
      Object.freeze({
        componentOpening: "        <CadenceDetailsFrame>",
        nativeOpening: "        <details>",
        componentClosing: "        </CadenceDetailsFrame>",
        nativeClosing: "        </details>",
      }),
      Object.freeze({
        componentOpening: "        <CadenceDetailsFrame>",
        nativeOpening: "        <details>",
        componentClosing: "        </CadenceDetailsFrame>",
        nativeClosing: "        </details>",
      }),
    ]),
  }),
  Object.freeze({
    path: "apps/cadence_web/assets/vue/OpsDashboardLibrary.vue",
    baseSha256: "03b5d0004874c7903cc919ae2417cc827b532e87fd5c8fd6794813b324555324",
    baseDetailsCount: 3,
    controlledOpenings: Object.freeze([
      `        <details
          :id="create_form.details.id"
          :open="create_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >`,
      `        <details
          :id="version_form.details.id"
          :open="version_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >`,
    ]),
    boundaries: Object.freeze([
      Object.freeze({
        componentOpening:
          '          <CadenceDetailsFrame :id="entry.details.id" class="mt-3 border-t border-base-300/60 pt-3">',
        nativeOpening:
          '          <details :id="entry.details.id" class="mt-3 border-t border-base-300/60 pt-3">',
        componentClosing: "          </CadenceDetailsFrame>",
        nativeClosing: "          </details>",
      }),
    ]),
  }),
])

const occurrences = (source, value) => source.split(value).length - 1
const matchCount = (source, pattern) => source.match(pattern)?.length ?? 0
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

const reconstructParent = (source, caller) => {
  assert.equal(occurrences(source, importLine), 1, `${caller.path} imports the frame once`)
  assert.equal(
    matchCount(source, /^import CadenceDetailsFrame\b/gm),
    1,
    `${caller.path} has exactly one frame import declaration`,
  )
  assert.equal(
    matchCount(source, /<CadenceDetailsFrame\b/g),
    caller.boundaries.length,
    `${caller.path} has its frozen safe-root opening count`,
  )
  assert.equal(
    occurrences(source, componentClosing),
    caller.boundaries.length,
    `${caller.path} closes every safe frame`,
  )
  assert.equal(
    matchCount(source, /<details\b/g),
    caller.controlledOpenings.length,
    `${caller.path} keeps only its excluded controlled roots native`,
  )
  assert.equal(
    occurrences(source, "</details>"),
    caller.controlledOpenings.length,
    `${caller.path} closes every excluded controlled native root`,
  )
  assert.doesNotMatch(
    source,
    /<CadenceDetailsFrame\b[^>]*\s:open=/,
    `${caller.path} does not migrate a controlled open contract`,
  )

  for (const controlledOpening of caller.controlledOpenings) {
    assert.equal(
      occurrences(source, controlledOpening),
      1,
      `${caller.path} preserves each excluded native details opening and :open contract exactly`,
    )
  }

  let reconstructed = source.replace(importLine, "")
  let cursor = 0

  for (const [index, boundary] of caller.boundaries.entries()) {
    const openingIndex = reconstructed.indexOf(boundary.componentOpening, cursor)
    assert.notEqual(openingIndex, -1, `${caller.path} safe boundary ${index + 1} opening is exact`)

    const slotStart = openingIndex + boundary.componentOpening.length
    const closingIndex = reconstructed.indexOf(boundary.componentClosing, slotStart)
    assert.notEqual(closingIndex, -1, `${caller.path} safe boundary ${index + 1} closing is exact`)

    const nestedOpeningIndex = reconstructed.indexOf("<CadenceDetailsFrame", slotStart)
    assert.ok(
      nestedOpeningIndex === -1 || nestedOpeningIndex > closingIndex,
      `${caller.path} safe boundary ${index + 1} pairs with its matching close`,
    )

    const callerOwnedChildren = reconstructed.slice(slotStart, closingIndex)
    reconstructed =
      reconstructed.slice(0, openingIndex) +
      boundary.nativeOpening +
      callerOwnedChildren +
      boundary.nativeClosing +
      reconstructed.slice(closingIndex + boundary.componentClosing.length)
    cursor =
      openingIndex +
      boundary.nativeOpening.length +
      callerOwnedChildren.length +
      boundary.nativeClosing.length
  }

  assert.equal(
    occurrences(reconstructed, "CadenceDetailsFrame"),
    0,
    `${caller.path} inverse peel removes only the newest import and wrappers`,
  )
  assert.equal(
    matchCount(reconstructed, /<details\b/g),
    caller.baseDetailsCount,
    `${caller.path} reconstructs its frozen parent details-opening count`,
  )
  assert.equal(
    occurrences(reconstructed, "</details>"),
    caller.baseDetailsCount,
    `${caller.path} reconstructs its frozen parent details-closing count`,
  )

  return reconstructed
}

assert.equal(process.versions.node, "24.16.0", "migration proof requires Node 24.16.0")
assert.equal(
  realpathSync(process.execPath),
  realpathSync(pinnedNode),
  `migration proof must run with ${pinnedNode}`,
)
assert.equal(callers.length, 2, "the frozen migration ledger contains exactly two callers")
assert.equal(
  callers.reduce((count, caller) => count + caller.boundaries.length, 0),
  4,
  "the frozen migration ledger contains exactly four safe roots",
)
assert.equal(
  callers.reduce((count, caller) => count + caller.controlledOpenings.length, 0),
  3,
  "the frozen exclusion ledger contains exactly three controlled native roots",
)

for (const caller of callers) {
  const componentPath = resolve(repositoryRoot, caller.path)
  const source = readFileSync(componentPath, "utf8")
  const reconstructed = reconstructParent(source, caller)
  const baseSource = execFileSync("git", ["show", `${parent}:${caller.path}`], {
    cwd: repositoryRoot,
    encoding: "utf8",
  })

  assert.equal(sha256(baseSource), caller.baseSha256, `${caller.path} pins the parent bytes`)
  assert.equal(
    sha256(reconstructed),
    caller.baseSha256,
    `${caller.path} inverse peel reconstructs the frozen parent SHA-256`,
  )
  assert.equal(
    reconstructed,
    baseSource,
    `${caller.path} reconstructs ${parent} byte-for-byte`,
  )

  const parsed = parse(source, {filename: componentPath})
  assert.deepEqual(parsed.errors, [], `${caller.path} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${caller.path} retains its script setup block`)
  assert.ok(parsed.descriptor.template, `${caller.path} retains its template block`)
  assert.doesNotThrow(
    () =>
      compileScript(parsed.descriptor, {
        id: `details-controlled-hosts-safe-${caller.path}`,
        inlineTemplate: true,
      }),
    `${caller.path} compiles as its actual SFC`,
  )
}

console.log(
  "details_controlled_hosts_safe_migration_test passed (4 safe roots, 3 controlled exclusions, 2 compiled SFCs)",
)

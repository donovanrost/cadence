import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFileSync, realpathSync} from "node:fs"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"
import {
  opsAuthorHeaderCallerNames,
  peelCadenceOpsAuthorHeader,
} from "./page_header_ops_author_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

const parent = "f9f36bb729e9f9abb1a2d01c3924bddf3d7eb99a"
const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..")
const detailsFrameImportLine =
  'import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"\n'
const detailsFrameClosing = "</CadenceDetailsFrame>"
const cadenceCollapsibleImports = Object.freeze([
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"\n',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"\n',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"\n',
])
const dashboardDisclosureSeedHelper = [
  "const disclosureSeedEpoch = (details: ProgressiveDetails) =>",
  '  `${details.id}:${details.open ? "open" : "closed"}`',
  "",
  "",
].join("\n")
const collapsibleClosing = `            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")

const callers = Object.freeze([
  Object.freeze({
    path: "apps/cadence_web/assets/vue/OpsFleetPlanningPolicy.vue",
    baseSha256: "eeeeeecf2d79a27ef6aeea3da5e472cc61e3162ff3f90e504e0aa759a308f6f4",
    baseDetailsCount: 4,
    disclosureSeedHelper: null,
    controlledDisclosures: Object.freeze([
      Object.freeze({
        label: "policy",
        openingIndent: "        ",
        nativeOpening: '<details :open="policy_form.open">',
        openingSha256: "1c3488bb5db768112ced67f1d1fd2a24716270c13e7ecaf78d4a1afd4f102310",
        nativeSummary: `          <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
            {{ policy_form.summary }}
          </summary>`,
        componentOpening: `        <CadenceCollapsible
          :content-id="policy_form.id"
          :open="policy_form.open"
          client-seeded
          :seed-epoch="\`\${policy_form.id}:\${policy_form.open}\`"
          :unmount-on-hide="false"
        >
          <div>
            <CadenceCollapsibleTrigger>
              <button type="button" class="cursor-pointer px-4 py-3 text-sm font-semibold">
                {{ policy_form.summary }}
              </button>
            </CadenceCollapsibleTrigger>
            <CadenceCollapsibleContent>`,
        componentClosing: collapsibleClosing,
        contentSeparator: "\n",
      }),
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
    disclosureSeedHelper: dashboardDisclosureSeedHelper,
    controlledDisclosures: Object.freeze([
      Object.freeze({
        label: "dashboard create",
        openingIndent: "        ",
        nativeOpening: `<details
          :id="create_form.details.id"
          :open="create_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >`,
        openingSha256: "3c98a4d0cee5edea1d8f05eed91388a37c7228e28ba4302b8fe55ee3f1eb3104",
        nativeSummary: `          <summary
            :id="create_form.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ create_form.details.summary }}</summary>`,
        componentOpening: `        <CadenceCollapsible
          :content-id="create_form.id"
          :open="create_form.details.open"
          client-seeded
          :seed-epoch="disclosureSeedEpoch(create_form.details)"
          :unmount-on-hide="false"
        >
          <div
            :id="create_form.details.id"
            class="border border-base-300 bg-base-200/20 p-4"
          >
            <CadenceCollapsibleTrigger>
              <button
                :id="create_form.details.summary_id"
                type="button"
                class="cursor-pointer font-semibold"
              >{{ create_form.details.summary }}</button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>`,
        componentClosing: collapsibleClosing,
        contentSeparator: "\n\n",
      }),
      Object.freeze({
        label: "dashboard version",
        openingIndent: "        ",
        nativeOpening: `<details
          :id="version_form.details.id"
          :open="version_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >`,
        openingSha256: "a17681f34775420252d7c0ec017c416311f646011bd37abafed1837ab7840bb7",
        nativeSummary: `          <summary
            :id="version_form.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ version_form.details.summary }}</summary>`,
        componentOpening: `        <CadenceCollapsible
          :content-id="version_form.id"
          :open="version_form.details.open"
          client-seeded
          :seed-epoch="disclosureSeedEpoch(version_form.details)"
          :unmount-on-hide="false"
        >
          <div
            :id="version_form.details.id"
            class="border border-base-300 bg-base-200/20 p-4"
          >
            <CadenceCollapsibleTrigger>
              <button
                :id="version_form.details.summary_id"
                type="button"
                class="cursor-pointer font-semibold"
              >{{ version_form.details.summary }}</button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>`,
        componentClosing: collapsibleClosing,
        contentSeparator: "\n\n",
      }),
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

const peelCadenceCollapsibles = (source, caller) => {
  for (const importLine of cadenceCollapsibleImports) {
    assert.equal(
      occurrences(source, importLine),
      1,
      `${caller.path} imports each collapsible adapter once`,
    )
  }
  assert.equal(
    occurrences(source, dashboardDisclosureSeedHelper),
    caller.disclosureSeedHelper === null ? 0 : 1,
    `${caller.path} has its exact disclosure seed-helper count`,
  )
  assert.equal(
    matchCount(source, /<CadenceCollapsible\b/g),
    caller.controlledDisclosures.length,
    `${caller.path} has its exact controlled collapsible opening count`,
  )
  assert.equal(
    occurrences(source, "</CadenceCollapsible>"),
    caller.controlledDisclosures.length,
    `${caller.path} closes every controlled collapsible`,
  )
  assert.equal(
    matchCount(source, /<CadenceCollapsibleTrigger\b/g),
    caller.controlledDisclosures.length,
    `${caller.path} has one collapsible trigger per controlled root`,
  )
  assert.equal(
    matchCount(source, /<CadenceCollapsibleContent\b/g),
    caller.controlledDisclosures.length,
    `${caller.path} has one collapsible content boundary per controlled root`,
  )

  let peeled = source

  for (const [index, disclosure] of caller.controlledDisclosures.entries()) {
    assert.equal(
      sha256(disclosure.nativeOpening),
      disclosure.openingSha256,
      `${caller.path} freezes the retired ${disclosure.label} opening SHA-256`,
    )
    assert.equal(
      occurrences(peeled, disclosure.componentOpening),
      1,
      `${caller.path} controlled boundary ${index + 1} opening is exact`,
    )

    const openingIndex = peeled.indexOf(disclosure.componentOpening)
    const slotStart = openingIndex + disclosure.componentOpening.length
    assert.equal(
      peeled.slice(slotStart, slotStart + 1),
      "\n",
      `${caller.path} controlled boundary ${index + 1} content starts exactly`,
    )

    const callerContentStart = slotStart + 1
    const closingIndex = peeled.indexOf(disclosure.componentClosing, callerContentStart)
    assert.notEqual(
      closingIndex,
      -1,
      `${caller.path} controlled boundary ${index + 1} closing is exact`,
    )

    const nestedOpeningIndex = peeled.indexOf("<CadenceCollapsible", callerContentStart)
    assert.ok(
      nestedOpeningIndex === -1 || nestedOpeningIndex > closingIndex,
      `${caller.path} controlled boundary ${index + 1} pairs with its matching close`,
    )

    const callerOwnedForm = peeled.slice(callerContentStart, closingIndex)
    const nativeDisclosure =
      disclosure.openingIndent +
      disclosure.nativeOpening +
      "\n" +
      disclosure.nativeSummary +
      disclosure.contentSeparator +
      callerOwnedForm +
      disclosure.openingIndent +
      "</details>"

    peeled =
      peeled.slice(0, openingIndex) +
      nativeDisclosure +
      peeled.slice(closingIndex + disclosure.componentClosing.length)
  }

  for (const importLine of cadenceCollapsibleImports) peeled = peeled.replace(importLine, "")
  if (caller.disclosureSeedHelper !== null) {
    peeled = peeled.replace(caller.disclosureSeedHelper, "")
  }

  assert.doesNotMatch(
    peeled,
    /CadenceCollapsible(?:Content|Trigger)?|disclosureSeedEpoch/,
    `${caller.path} inverse peel removes only the newest collapsible layer`,
  )
  assert.equal(
    matchCount(peeled, /<details\b/g),
    caller.controlledDisclosures.length,
    `${caller.path} inverse peel restores its retired controlled details openings`,
  )
  assert.equal(
    occurrences(peeled, "</details>"),
    caller.controlledDisclosures.length,
    `${caller.path} inverse peel restores its retired controlled details closings`,
  )

  for (const disclosure of caller.controlledDisclosures) {
    assert.equal(
      occurrences(peeled, disclosure.openingIndent + disclosure.nativeOpening),
      1,
      `${caller.path} restores the retired ${disclosure.label} opening exactly`,
    )
  }

  return peeled
}

const reconstructParent = (source, caller) => {
  if (opsAuthorHeaderCallerNames.includes(caller.path.split("/").at(-1))) {
    source = peelCadenceOpsAuthorHeader(source, caller.path)
  }
  if (opsViewportCallerNames.includes(caller.path.split("/").at(-1))) {
    source = peelCadenceOpsViewport(source, caller.path)
  }
  source = peelCadenceInlineWarnings(source, caller.path)

  assert.equal(
    occurrences(source, detailsFrameImportLine),
    1,
    `${caller.path} imports the frame once`,
  )
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
    occurrences(source, detailsFrameClosing),
    caller.boundaries.length,
    `${caller.path} closes every safe frame`,
  )
  assert.equal(
    matchCount(source, /<details\b/g),
    0,
    `${caller.path} has zero raw outer controlled roots after the form-host migrations`,
  )
  assert.equal(
    occurrences(source, "</details>"),
    0,
    `${caller.path} has zero raw outer controlled closings after the form-host migrations`,
  )
  assert.doesNotMatch(
    source,
    /<CadenceDetailsFrame\b[^>]*\s:open=/,
    `${caller.path} does not migrate a controlled open contract`,
  )

  for (const disclosure of caller.controlledDisclosures) {
    assert.equal(
      occurrences(source, disclosure.openingIndent + disclosure.nativeOpening),
      0,
      `${caller.path} retires each raw controlled opening from the current source`,
    )
  }

  let reconstructed = peelCadenceCollapsibles(source, caller).replace(detailsFrameImportLine, "")
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
  callers.reduce((count, caller) => count + caller.controlledDisclosures.length, 0),
  3,
  "the frozen predecessor ledger contains exactly three retired controlled native roots",
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
  "details_controlled_hosts_safe_migration_test passed (4 safe roots, 3 controlled roots inverse-reconstructed, 2 compiled SFCs)",
)

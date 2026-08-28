import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import test from "node:test"

assert.equal(
  process.versions.node,
  "24.16.0",
  "page-header migration test must run with pinned Node 24.16.0"
)

const parent = "4a087fc3426b3b21d7c447152e444752947da692"
const componentImport =
  'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"'
const rawOpening =
  '<header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">'

const callers = [
  {
    file: "OpsFleetPlanningNew.vue",
    sha256: "2d59cf31792eca1f2ce3a6a681dc908883f1fa22ff6747c58831a7d7fd30edc6",
    indent: "    "
  },
  {
    file: "OpsFleetPlanningPolicy.vue",
    sha256: "a94e136f6fc5aa1948f6e49c3542ee7b9cab06fdc1875595fde5ac6da47eb597",
    indent: "  "
  },
  {
    file: "OpsCommands.vue",
    sha256: "a67c549398fe9ff931dacf29ba8df9a77a5368f3ec017382159f42d857082d72",
    indent: "    "
  },
  {
    file: "OpsDashboardActivity.vue",
    sha256: "168768d85b04fd897070e2b32e82cc086e048f60d72ede368e2072102cd7c903",
    indent: "  ",
    migratedOpening: '  <CadencePageHeaderFrame v-if="surface === \'header\'" variant="ops">',
    parentOpening: `  <header
    v-if="surface === 'header'"
    class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7"
  >`
  },
  {
    file: "OpsFleetPlanning.vue",
    sha256: "b08d522dbcb02d1c9517b880f42f6fe81cac20d764726d2ac41d030b126282cb",
    indent: "    "
  },
  {
    file: "OpsFleetPlanningRun.vue",
    sha256: "bc18a24b2cfa2f3c829233af17ba68eff049eaf1f79e8a74db4b42d7575ca1ce",
    indent: "    "
  },
  {
    file: "OpsDashboardDirectory.vue",
    sha256: "bd99244b3b4fc0317c698edb691496e3a37aa59b346aeb690dc3b1b6a4f72449",
    indent: "    "
  },
  {
    file: "OpsDashboardSettings.vue",
    sha256: "543079a9f03969da1fdc425a6907f44b684a919dffa11a1c7632da65623f6112",
    indent: "    "
  }
]

const occurrences = (source, token) => source.split(token).length - 1
const sha256 = source => createHash("sha256").update(source).digest("hex")

for (const caller of callers) {
  test(`${caller.file} has one ops page-header frame and reconstructs ${parent}`, async () => {
    const source = await readFile(new URL(`../vue/${caller.file}`, import.meta.url), "utf8")
    const migratedOpening =
      caller.migratedOpening ?? `${caller.indent}<CadencePageHeaderFrame variant="ops">`
    const parentOpening = caller.parentOpening ?? `${caller.indent}${rawOpening}`
    const migratedClosing = `${caller.indent}</CadencePageHeaderFrame>`
    const parentClosing = `${caller.indent}</header>`

    assert.equal(occurrences(source, componentImport), 1, "expected exactly one frame import")
    assert.equal(occurrences(source, "<CadencePageHeaderFrame"), 1, "expected one frame opening")
    assert.equal(occurrences(source, migratedOpening), 1, "expected the exact ops frame opening")
    assert.equal(occurrences(source, migratedClosing), 1, "expected one frame closing")
    assert.equal(occurrences(source, 'variant="ops"'), 1, "expected one ops variant")
    assert.doesNotMatch(source, /<header\b/, "expected no residual native header")

    const reconstructed = source
      .replace(`${componentImport}\n`, "")
      .replace(migratedOpening, parentOpening)
      .replace(migratedClosing, parentClosing)

    assert.equal(
      occurrences(reconstructed, "CadencePageHeaderFrame"),
      0,
      "reconstruction must reverse only this migration"
    )
    assert.equal(
      sha256(reconstructed),
      caller.sha256,
      `reconstructed source must match ${parent}:${caller.file}`
    )
  })
}

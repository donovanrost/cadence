import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const dashboardSettingsSectionFramePredecessorCommit =
  "ac8cbe1fdd07a6022a36b651ff09e359ff2975df"
export const dashboardSettingsSectionFramePath =
  "apps/cadence_web/assets/vue/ui/components/CadenceDashboardSettingsSectionFrame.vue"
export const dashboardSettingsSectionFrameClass =
  "border border-base-300 bg-base-200/20 p-5"
export const dashboardSettingsSectionFrameImport =
  'import CadenceDashboardSettingsSectionFrame from "./ui/components/CadenceDashboardSettingsSectionFrame.vue"\n'

const section = (name, frameOpening, nativeOpening) =>
  Object.freeze({
    name,
    frameOpening,
    nativeOpening,
    frameClosing: "        </CadenceDashboardSettingsSectionFrame>",
    nativeClosing: "        </section>",
  })

export const dashboardSettingsSectionFrameMigrations = Object.freeze([
  Object.freeze({
    file: "OpsDashboardSettings.vue",
    repositoryPath: "apps/cadence_web/assets/vue/OpsDashboardSettings.vue",
    predecessorByteLength: 19323,
    predecessorBlobId: "c29e183412770749d9b1ce1f09400cc19ae7ebd4",
    predecessorSha256:
      "cfba0f95a680912aaa1af19ed449c6b7266aea65429e802412f2bbc027d66713",
    sections: Object.freeze([
      section(
        "sharing",
        '        <CadenceDashboardSettingsSectionFrame :id="page.sharing.id">',
        `        <section :id="page.sharing.id" class="${dashboardSettingsSectionFrameClass}">`,
      ),
      section(
        "snapshots",
        `        <CadenceDashboardSettingsSectionFrame
          :id="page.snapshots.id"
        >`,
        `        <section
          :id="page.snapshots.id"
          class="${dashboardSettingsSectionFrameClass}"
        >`,
      ),
    ]),
  }),
])

export const dashboardSettingsSectionFrameCallerNames = Object.freeze(
  dashboardSettingsSectionFrameMigrations.map(({file}) => file),
)

export const dashboardSettingsSectionFrameSha256 = (source) =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

const migrationFor = (caller) => {
  const file = caller.replaceAll("\\", "/").split("/").at(-1)
  const migration = dashboardSettingsSectionFrameMigrations.find(
    (entry) => entry.file === file,
  )

  assert.ok(migration, `${caller} is an audited dashboard settings section-frame caller`)
  return migration
}

export const peelCadenceDashboardSettingsSectionFrame = (source, caller) => {
  const migration = migrationFor(caller)

  assert.equal(
    occurrences(source, dashboardSettingsSectionFrameImport),
    1,
    `${migration.file} section-frame import count`,
  )

  let predecessor = source.replace(dashboardSettingsSectionFrameImport, "")
  for (const [index, boundary] of migration.sections.entries()) {
    assert.equal(
      occurrences(predecessor, boundary.frameOpening),
      1,
      `${migration.file} ${boundary.name} frame opening`,
    )
    assert.equal(
      occurrences(predecessor, boundary.frameClosing),
      migration.sections.length - index,
      `${migration.file} ${boundary.name} frame closing`,
    )

    predecessor = predecessor
      .replace(boundary.frameOpening, boundary.nativeOpening)
      .replace(boundary.frameClosing, boundary.nativeClosing)
  }

  assert.doesNotMatch(predecessor, /CadenceDashboardSettingsSectionFrame/)
  return predecessor
}

export const peelCadenceDashboardSettingsSectionFrameBeforeOlderLayers = (
  source,
  caller,
) => {
  const file = caller.replaceAll("\\", "/").split("/").at(-1)
  if (!dashboardSettingsSectionFrameCallerNames.includes(file)) return source
  if (occurrences(source, dashboardSettingsSectionFrameImport) === 0) return source
  return peelCadenceDashboardSettingsSectionFrame(source, caller)
}

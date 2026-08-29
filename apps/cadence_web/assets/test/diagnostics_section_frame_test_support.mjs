import assert from "node:assert/strict"

export const diagnosticsSectionPredecessorCommit =
  "230d045e5182192ee707e62a5a1a84633a82c7ec"
export const diagnosticsSectionRootClass =
  "overflow-hidden border border-base-300/80 bg-base-200/30"
export const diagnosticsSectionHeaderClass =
  "grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"
export const diagnosticsSectionExcludedHeaderClass =
  "grid gap-4 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"

export const diagnosticsSectionMigrations = Object.freeze([
  Object.freeze({
    file: "SpacecraftTelemetryDecom.vue",
    sourcePath: "apps/cadence_web/assets/vue/SpacecraftTelemetryDecom.vue",
    predecessorCommit: diagnosticsSectionPredecessorCommit,
    predecessorByteLength: 22628,
    predecessorSha256: "4cab4a5673ea88d9b5ac1e49c8c7c53cd56109a120c6fbd5c460bc2ebcc45d6a",
    importLine:
      'import CadenceDiagnosticsSectionFrame from "./ui/components/CadenceDiagnosticsSectionFrame.vue"\n',
    frameOpening: `                  <CadenceDiagnosticsSectionFrame
                    :id="preview.diagnostics.id"
                    :role="preview.diagnostics.role"
                    aria-live="polite"
                    :data-diagnostic-severity="preview.diagnostics.severity"
                    :data-diagnostic-count="preview.diagnostics.count"
                    :data-diagnostic-total="preview.diagnostics.total_count"
                  >`,
    nativeOpening: `                  <section
                    :id="preview.diagnostics.id"
                    :role="preview.diagnostics.role"
                    aria-live="polite"
                    :data-diagnostic-severity="preview.diagnostics.severity"
                    :data-diagnostic-count="preview.diagnostics.count"
                    :data-diagnostic-total="preview.diagnostics.total_count"
                    class="${diagnosticsSectionRootClass}"
                  >`,
    frameHeaderOpening: "                  <template #header>",
    nativeHeaderOpening: `                  <header class="${diagnosticsSectionHeaderClass}">`,
    frameHeaderClosing: "                  </template>",
    nativeHeaderClosing: "                  </header>",
    frameClosing: "                  </CadenceDiagnosticsSectionFrame>",
    nativeClosing: "                  </section>",
  }),
  Object.freeze({
    file: "application_host/ApplicationDiagnostics.vue",
    sourcePath:
      "apps/cadence_web/assets/vue/application_host/ApplicationDiagnostics.vue",
    predecessorCommit: diagnosticsSectionPredecessorCommit,
    predecessorByteLength: 3814,
    predecessorSha256: "e2c25b861617642f5ca09b9fb26177d063d153f71f1d8652418d7511e7ae69cf",
    importLine:
      'import CadenceDiagnosticsSectionFrame from "../ui/components/CadenceDiagnosticsSectionFrame.vue"\n',
    frameOpening: `  <CadenceDiagnosticsSectionFrame
    :id="diagnostics.id"
    :role="diagnostics.role"
    aria-live="polite"
    :data-diagnostic-severity="diagnostics.severity"
    :data-diagnostic-count="diagnostics.count"
    :data-diagnostic-total="diagnostics.total_count"
  >`,
    nativeOpening: `  <section
    :id="diagnostics.id"
    :role="diagnostics.role"
    aria-live="polite"
    :data-diagnostic-severity="diagnostics.severity"
    :data-diagnostic-count="diagnostics.count"
    :data-diagnostic-total="diagnostics.total_count"
    class="${diagnosticsSectionRootClass}"
  >`,
    frameHeaderOpening: "    <template #header>",
    nativeHeaderOpening: `    <header class="${diagnosticsSectionHeaderClass}">`,
    frameHeaderClosing: "    </template>",
    nativeHeaderClosing: "    </header>",
    frameClosing: "  </CadenceDiagnosticsSectionFrame>",
    nativeClosing: "  </section>",
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

const migrationFor = (caller) => {
  const normalizedCaller = caller.replaceAll("\\", "/")
  return diagnosticsSectionMigrations.find(
    ({file, sourcePath}) =>
      normalizedCaller === file ||
      normalizedCaller === sourcePath ||
      normalizedCaller.endsWith(`/${file}`) ||
      normalizedCaller.endsWith(`/${sourcePath}`),
  )
}

export const peelCadenceDiagnosticsSectionFrame = (source, caller) => {
  const migration = migrationFor(caller)
  if (!migration) return source

  assert.equal(occurrences(source, migration.importLine), 1, `${migration.file} frame import`)
  assert.equal(occurrences(source, migration.frameOpening), 1, `${migration.file} frame opening`)
  assert.equal(
    occurrences(source, migration.frameHeaderOpening),
    1,
    `${migration.file} header slot opening`,
  )
  assert.equal(occurrences(source, migration.frameClosing), 1, `${migration.file} frame closing`)

  const headerStart = source.indexOf(migration.frameHeaderOpening)
  const headerEnd = source.indexOf(
    migration.frameHeaderClosing,
    headerStart + migration.frameHeaderOpening.length,
  )
  assert.notEqual(headerEnd, -1, `${migration.file} header slot closes after its opening`)

  const headerCompatibleSource =
    source.slice(0, headerStart) +
    migration.nativeHeaderOpening +
    source.slice(headerStart + migration.frameHeaderOpening.length, headerEnd) +
    migration.nativeHeaderClosing +
    source.slice(headerEnd + migration.frameHeaderClosing.length)

  const predecessor = headerCompatibleSource
    .replace(migration.importLine, "")
    .replace(migration.frameOpening, migration.nativeOpening)
    .replace(migration.frameClosing, migration.nativeClosing)

  assert.doesNotMatch(predecessor, /CadenceDiagnosticsSectionFrame/)
  return predecessor
}

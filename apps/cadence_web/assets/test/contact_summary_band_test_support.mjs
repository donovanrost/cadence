import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const contactSummaryBandPredecessorCommit =
  "d66a4a709c1b11f36faa8fbc998730e73b72f2f0"
export const contactSummaryBandRootClass = "border border-base-300 bg-base-200/20"
export const contactSummaryBandHeaderClass = "grid gap-4 p-4 sm:grid-cols-3"

const lines = (...sourceLines) => sourceLines.join("\n")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const filenameFor = (path) => path.split("/").at(-1)

const migration = ({
  file,
  path,
  predecessorBlob,
  predecessorByteLength,
  predecessorSha256,
  migrated,
  predecessor,
}) =>
  Object.freeze({
    file,
    path,
    predecessorCommit: contactSummaryBandPredecessorCommit,
    predecessorBlob,
    predecessorByteLength,
    predecessorSha256,
    migrated,
    predecessor,
  })

export const contactSummaryBandPrimitive = Object.freeze({
  path: "apps/cadence_web/assets/vue/ui/components/CadencePanel.vue",
  predecessorCommit: contactSummaryBandPredecessorCommit,
  predecessorBlob: "d28d2af8746336387b7f147c581b1b0dc20d29ad",
  predecessorByteLength: 812,
  predecessorSha256: "e2a883a76407b5efb855299f8fa296f890a8cca255346d5726026b55c088474c",
})

export const contactSummaryBandMigrations = Object.freeze([
  migration({
    file: "OpsContactRequirementShow.vue",
    path: "apps/cadence_web/assets/vue/OpsContactRequirementShow.vue",
    predecessorBlob: "e0791fe2e344dd5d7fb407f470787b0052870a4b",
    predecessorByteLength: 14008,
    predecessorSha256: "643fee60cca931d4f21ad769c0c03eaaf1665f5e9e80e10e3cb5d3dfc73f7c32",
    migrated: lines(
      '        <CadencePanel :id="page.horizon.id" class="border border-base-300 bg-base-200/20" header-class="grid gap-4 p-4 sm:grid-cols-3">',
      "          <template #header>",
      '            <div v-for="field in page.horizon.fields" :key="field.label">',
      '              <p class="hud-label">{{ field.label }}</p>',
      '              <p :class="field.class">',
      "                {{ field.value }}",
      "              </p>",
      "            </div>",
      "          </template>",
      '          <div class="border-t border-base-300 px-4 py-3 text-sm text-base-content/60">',
      "            {{ page.horizon.rationale }}",
      "          </div>",
      "        </CadencePanel>",
    ),
    predecessor: lines(
      '        <section :id="page.horizon.id" class="border border-base-300 bg-base-200/20">',
      '          <div class="grid gap-4 p-4 sm:grid-cols-3">',
      '            <div v-for="field in page.horizon.fields" :key="field.label">',
      '              <p class="hud-label">{{ field.label }}</p>',
      '              <p :class="field.class">',
      "                {{ field.value }}",
      "              </p>",
      "            </div>",
      "          </div>",
      '          <div class="border-t border-base-300 px-4 py-3 text-sm text-base-content/60">',
      "            {{ page.horizon.rationale }}",
      "          </div>",
      "        </section>",
    ),
  }),
  migration({
    file: "OpsContactPlanShow.vue",
    path: "apps/cadence_web/assets/vue/OpsContactPlanShow.vue",
    predecessorBlob: "fef86fe5902353ead24c0df66269a9234092c447",
    predecessorByteLength: 19362,
    predecessorSha256: "22bb0df7ba4f82db1f483f6aee8aa3605c1792d1793bee8a751b5d5acd49686d",
    migrated: lines(
      '        <CadencePanel :id="page.summary.id" class="border border-base-300 bg-base-200/20" header-class="grid gap-4 p-4 sm:grid-cols-3">',
      "          <template #header>",
      "            <div>",
      '              <p class="hud-label">Requirement coverage</p>',
      '              <p :class="page.summary.coverage.class">{{ page.summary.coverage.label }}</p>',
      "            </div>",
      "            <div>",
      '              <p class="hud-label">Selected windows</p>',
      '              <p class="mt-1 font-mono text-sm">{{ page.summary.selected_count }}</p>',
      "            </div>",
      "            <div>",
      '              <p class="hud-label">Approval identity</p>',
      '              <p class="mt-1 font-mono text-sm">{{ page.summary.approval_identity }}</p>',
      "            </div>",
      "          </template>",
      '          <div class="border-t border-base-300 px-4 py-3">',
      '            <p class="hud-label">Exact content hash</p>',
      "            <p",
      '              :id="page.summary.content_hash.id"',
      '              class="mt-1 break-all font-mono text-[0.68rem] text-base-content/55"',
      "            >{{ page.summary.content_hash.value }}</p>",
      "          </div>",
      "        </CadencePanel>",
    ),
    predecessor: lines(
      '        <section :id="page.summary.id" class="border border-base-300 bg-base-200/20">',
      '          <div class="grid gap-4 p-4 sm:grid-cols-3">',
      "            <div>",
      '              <p class="hud-label">Requirement coverage</p>',
      '              <p :class="page.summary.coverage.class">{{ page.summary.coverage.label }}</p>',
      "            </div>",
      "            <div>",
      '              <p class="hud-label">Selected windows</p>',
      '              <p class="mt-1 font-mono text-sm">{{ page.summary.selected_count }}</p>',
      "            </div>",
      "            <div>",
      '              <p class="hud-label">Approval identity</p>',
      '              <p class="mt-1 font-mono text-sm">{{ page.summary.approval_identity }}</p>',
      "            </div>",
      "          </div>",
      '          <div class="border-t border-base-300 px-4 py-3">',
      '            <p class="hud-label">Exact content hash</p>',
      "            <p",
      '              :id="page.summary.content_hash.id"',
      '              class="mt-1 break-all font-mono text-[0.68rem] text-base-content/55"',
      "            >{{ page.summary.content_hash.value }}</p>",
      "          </div>",
      "        </section>",
    ),
  }),
])

export const contactSummaryBandCallerNames = Object.freeze(
  contactSummaryBandMigrations.map(({file}) => file),
)

export const contactSummaryBandMigrationFor = (path) => {
  const filename = filenameFor(path)
  const found = contactSummaryBandMigrations.find(({file}) => file === filename)

  assert.ok(found, `${path} is an audited contact summary band caller`)
  return found
}

export const peelContactSummaryBand = (source, path) => {
  const filename = filenameFor(path)
  const migrationEntry = contactSummaryBandMigrations.find(({file}) => file === filename)
  if (!migrationEntry) return source

  assert.equal(
    occurrences(source, migrationEntry.migrated),
    1,
    `${filename} exact newest summary band boundary`,
  )
  assert.equal(
    occurrences(source, migrationEntry.predecessor),
    0,
    `${filename} has no residual predecessor summary band`,
  )

  const predecessor = source.replace(migrationEntry.migrated, migrationEntry.predecessor)

  assert.equal(
    sha256(predecessor),
    migrationEntry.predecessorSha256,
    `${filename} reconstructs the fixed current predecessor SHA-256`,
  )
  assert.equal(
    Buffer.byteLength(predecessor),
    migrationEntry.predecessorByteLength,
    `${filename} reconstructs the fixed current predecessor bytes`,
  )
  return predecessor
}

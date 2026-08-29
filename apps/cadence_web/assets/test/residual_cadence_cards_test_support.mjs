import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {peelCadenceFormSectionFrameBeforeOlderLayers} from "./form_section_frame_test_support.mjs"

const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1

export const residualCadenceCardMigrations = Object.freeze([
  Object.freeze({
    file: "AdminHome.vue",
    opening: `        <CadenceCard
          class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
          body-class="card-body p-6"
        >
`,
    predecessorOpening: `        <section
          class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
        >
          <div class="card-body p-6">
`,
    closing: "        </CadenceCard>",
    predecessorClosing: "          </div>\n        </section>",
    slotIndent: "          ",
    predecessorSha256: "7105d5b5d2b5ed957cff8048c6317055ec4e8fc682c46bc188b34252620a17d0",
  }),
  Object.freeze({
    file: "CatalogArtifactShow.vue",
    opening: `      <CadenceCard
        v-else
        id="catalog-artifact-runs-card"
        class="card border border-base-300 bg-base-200"
        body-class="card-body p-0"
      >
`,
    predecessorOpening: `      <section
        v-else
        id="catalog-artifact-runs-card"
        class="card border border-base-300 bg-base-200"
      >
        <div class="card-body p-0">
`,
    closing: "      </CadenceCard>",
    predecessorClosing: "        </div>\n      </section>",
    slotIndent: "        ",
    predecessorSha256: "84769db44a68400f6f3c4b51a6e4d1b9d264438628374b999fe6420d8b7bcb89",
  }),
  Object.freeze({
    file: "CommsTransportNew.vue",
    opening: `        <CadenceCard
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
          body-class="card-body p-0"
        >
`,
    predecessorOpening: `        <section
          :id="form.review.configuration_summary_id"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body p-0">
`,
    closing: "        </CadenceCard>",
    predecessorClosing: "          </div>\n        </section>",
    slotIndent: "          ",
    predecessorSha256: "36b9648365d47a9c88fdfa28bd73bee28d0264effd75cb1214ab978130cb8de8",
  }),
])

export const residualCadenceCardCallerNames = Object.freeze(
  residualCadenceCardMigrations.map(({file}) => file),
)

export const residualCadenceCardMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const migration = residualCadenceCardMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited residual CadenceCard caller`)
  return migration
}

export const peelResidualCadenceCard = (source, caller) => {
  const migration = residualCadenceCardMigrationFor(caller)
  const formSectionFrameCompatibleSource = peelCadenceFormSectionFrameBeforeOlderLayers(
    source,
    caller,
  )

  assert.equal(
    occurrences(formSectionFrameCompatibleSource, cardImport),
    1,
    `${migration.file} retains its one pre-existing CadenceCard import`,
  )
  assert.equal(
    formSectionFrameCompatibleSource.match(/^import CadenceCard\b/gm)?.length,
    1,
    `${migration.file} retains one CadenceCard import declaration`,
  )
  assert.equal(
    occurrences(formSectionFrameCompatibleSource, migration.opening),
    1,
    `${migration.file} has exactly one residual CadenceCard opening boundary`,
  )

  const openingIndex = formSectionFrameCompatibleSource.indexOf(migration.opening)
  const slotStart = openingIndex + migration.opening.length
  const closingToken = `\n${migration.closing}`
  const closingIndex = formSectionFrameCompatibleSource.indexOf(closingToken, slotStart)

  assert.ok(closingIndex > slotStart, `${migration.file} residual CadenceCard closes after its slot`)

  const callerSlot = formSectionFrameCompatibleSource.slice(slotStart, closingIndex)

  assert.doesNotMatch(
    callerSlot,
    /<\/?CadenceCard\b/,
    `${migration.file} residual boundary contains no nested CadenceCard`,
  )
  for (const line of callerSlot.split("\n")) {
    assert.ok(
      line.startsWith(migration.slotIndent),
      `${migration.file} caller slot indentation stays exact`,
    )
  }

  const predecessorSlot = callerSlot
    .split("\n")
    .map((line) => `  ${line}`)
    .join("\n")
  const predecessor =
    formSectionFrameCompatibleSource.slice(0, openingIndex) +
    migration.predecessorOpening +
    predecessorSlot +
    `\n${migration.predecessorClosing}` +
    formSectionFrameCompatibleSource.slice(closingIndex + closingToken.length)

  assert.equal(
    occurrences(predecessor, cardImport),
    1,
    `${migration.file} inverse peel does not remove the pre-existing CadenceCard import`,
  )
  assert.equal(
    sha256(predecessor),
    migration.predecessorSha256,
    `${migration.file} reconstructs its frozen immediate predecessor byte-for-byte`,
  )
  return predecessor
}

export const peelResidualCadenceCardBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  const migration = residualCadenceCardMigrations.find((entry) => entry.file === file)

  if (!migration || occurrences(source, migration.opening) === 0) return source
  return peelResidualCadenceCard(source, caller)
}

import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const definitionListPanelPredecessorCommit =
  "a08c00387f4acbfe3020ebe825ef4a22d4d4a98c"
export const definitionListPanelPredecessorBlob =
  "ccf5f77121a04ab0a1a7114c89b93ec70f75791f"
export const definitionListPanelPredecessorBytes = 41192
export const definitionListPanelPredecessorSha256 =
  "96ca907929d48ef771689ed43a21b743e0722c344a4f42fc1bb2c9b710328bc5"
export const definitionListPanelCaller = "OpsTelemetryExplore.vue"
export const definitionListPanelRepositoryPath =
  "apps/cadence_web/assets/vue/OpsTelemetryExplore.vue"
export const definitionListPanelPrimitiveRepositoryPath =
  "apps/cadence_web/assets/vue/ui/components/CadenceDefinitionListPanel.vue"
export const definitionListPanelImport =
  'import CadenceDefinitionListPanel from "./ui/components/CadenceDefinitionListPanel.vue"\n'
export const definitionListPanelClass = "border border-base-300/70 bg-base-100/40 p-4"
export const definitionListPanelHeadingClass = "hud-label"
export const definitionListPanelListClass =
  "mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs"

const boundary = ({componentOpening, nativeOpening}) =>
  Object.freeze({
    componentOpening,
    nativeOpening,
    componentClosing: `              </template>
            </CadenceDefinitionListPanel>`,
    nativeClosing: `              </dl>
            </section>`,
  })

export const definitionListPanelBoundaries = Object.freeze([
  boundary({
    componentOpening: `            <CadenceDefinitionListPanel id="telemetry-explore-context-card">
              <template #heading>Context</template>
              <template #default>`,
    nativeOpening: `            <section id="telemetry-explore-context-card" class="${definitionListPanelClass}">
              <h2 class="${definitionListPanelHeadingClass}">Context</h2>
              <dl class="${definitionListPanelListClass}">`,
  }),
  boundary({
    componentOpening: `            <CadenceDefinitionListPanel :id="diagnostics.id">
              <template #heading>Read Diagnostics</template>
              <template #default>`,
    nativeOpening: `            <section :id="diagnostics.id" class="${definitionListPanelClass}">
              <h2 class="${definitionListPanelHeadingClass}">Read Diagnostics</h2>
              <dl class="${definitionListPanelListClass}">`,
  }),
])

export const definitionListPanelSha256 = (source) =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const peelCadenceDefinitionListPanel = (source, caller) => {
  const file = caller.split("/").at(-1)

  assert.equal(file, definitionListPanelCaller, `${caller} is the exact definition-list caller`)
  assert.equal(occurrences(source, definitionListPanelImport), 1, "exact singular import")
  assert.equal(source.match(/^import CadenceDefinitionListPanel\b/gm)?.length, 1)
  assert.equal(source.match(/<CadenceDefinitionListPanel\b/g)?.length, 2)
  assert.equal(source.match(/<\/CadenceDefinitionListPanel>/g)?.length, 2)

  let predecessor = source.replace(definitionListPanelImport, "")

  for (const [index, entry] of definitionListPanelBoundaries.entries()) {
    assert.equal(
      occurrences(predecessor, entry.componentOpening),
      1,
      `definition-list opening ${index + 1} is exact`,
    )
    assert.equal(occurrences(predecessor, entry.nativeOpening), 0)

    const openingStart = predecessor.indexOf(entry.componentOpening)
    const slotStart = openingStart + entry.componentOpening.length
    const closingStart = predecessor.indexOf(entry.componentClosing, slotStart)

    assert.ok(closingStart > slotStart, `definition-list boundary ${index + 1} closes exactly`)
    predecessor =
      predecessor.slice(0, openingStart) +
      entry.nativeOpening +
      predecessor.slice(slotStart, closingStart) +
      entry.nativeClosing +
      predecessor.slice(closingStart + entry.componentClosing.length)
  }

  assert.doesNotMatch(predecessor, /CadenceDefinitionListPanel/)
  assert.equal(Buffer.byteLength(predecessor), definitionListPanelPredecessorBytes)
  assert.equal(
    definitionListPanelSha256(predecessor),
    definitionListPanelPredecessorSha256,
    "definition-list inverse reconstructs the frozen immediate predecessor SHA-256",
  )
  return predecessor
}

export const peelCadenceDefinitionListPanelBeforeOlderLayers = (source, caller) => {
  const file = caller.split("/").at(-1)
  if (file !== definitionListPanelCaller || occurrences(source, definitionListPanelImport) === 0) {
    return source
  }

  return peelCadenceDefinitionListPanel(source, caller)
}

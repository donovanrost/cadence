import assert from "node:assert/strict"
import {createHash} from "node:crypto"

export const formSectionFramePredecessorCommit =
  "1a545085f1ef4c080bcd99c6ed5c3d3775b3e762"
export const formSectionFrameImport =
  'import CadenceFormSectionFrame from "./ui/components/CadenceFormSectionFrame.vue"\n'
export const formSectionFrameClass = "space-y-4"

const root = ({boundary, opening, predecessorOpening, closing = "      </CadenceFormSectionFrame>"}) =>
  Object.freeze({
    boundary,
    opening,
    predecessorOpening,
    closing,
    predecessorClosing: closing.replace("CadenceFormSectionFrame", "section"),
  })

const migration = ({file, predecessorByteLength, predecessorBlobId, predecessorSha256, roots}) =>
  Object.freeze({
    file,
    repositoryPath: `apps/cadence_web/assets/vue/${file}`,
    predecessorByteLength,
    predecessorBlobId,
    predecessorSha256,
    roots: Object.freeze(roots),
  })

export const formSectionFrameMigrations = Object.freeze([
  migration({
    file: "CommsGroundStationForm.vue",
    predecessorByteLength: 10_094,
    predecessorBlobId: "47ae20f85d35ba5b8c3260b4691c4bf5cfac266e",
    predecessorSha256:
      "88aa1721b14d42f158ac4640c2068af59313d613c5feb824832147febf986d39",
    roots: [
      root({
        boundary: 168,
        opening: '      <CadenceFormSectionFrame :id="form.sections.identity.id">',
        predecessorOpening: '      <section :id="form.sections.identity.id" class="space-y-4">',
      }),
      root({
        boundary: 217,
        opening: '      <CadenceFormSectionFrame :id="form.sections.network.id">',
        predecessorOpening: '      <section :id="form.sections.network.id" class="space-y-4">',
      }),
      root({
        boundary: 266,
        opening: '      <CadenceFormSectionFrame :id="form.sections.metadata.id">',
        predecessorOpening: '      <section :id="form.sections.metadata.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "CommsProviderNew.vue",
    predecessorByteLength: 14_731,
    predecessorBlobId: "464ec673751eea88f1bbdf3168733d7464c473ca",
    predecessorSha256:
      "a2d6937f98d77372226f0f3b3b7224dae00338c963da25cc4628f6801ae3223a",
    roots: [
      root({
        boundary: 256,
        opening: '      <CadenceFormSectionFrame :id="form.sections.binding.id">',
        predecessorOpening: '      <section :id="form.sections.binding.id" class="space-y-4">',
      }),
      root({
        boundary: 338,
        opening: '      <CadenceFormSectionFrame :id="form.sections.resource_scope.id">',
        predecessorOpening:
          '      <section :id="form.sections.resource_scope.id" class="space-y-4">',
      }),
      root({
        boundary: 373,
        opening: '      <CadenceFormSectionFrame :id="form.sections.delivery_policy.id">',
        predecessorOpening:
          '      <section :id="form.sections.delivery_policy.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "CommsRoutingNew.vue",
    predecessorByteLength: 11_584,
    predecessorBlobId: "a6d6d7b739e16622316ea2c4017d39464297258f",
    predecessorSha256:
      "5ba60fb7ebb775eeea0927c10cbd8bb269b730dff586f63284d7f3a3174ce729",
    roots: [
      root({
        boundary: 207,
        opening: '      <CadenceFormSectionFrame id="routing-rule-intent-section">',
        predecessorOpening:
          '      <section id="routing-rule-intent-section" class="space-y-4">',
      }),
      root({
        boundary: 252,
        opening: '      <CadenceFormSectionFrame id="routing-rule-transport-section">',
        predecessorOpening:
          '      <section id="routing-rule-transport-section" class="space-y-4">',
      }),
      root({
        boundary: 307,
        opening: '      <CadenceFormSectionFrame id="routing-rule-policy-section">',
        predecessorOpening:
          '      <section id="routing-rule-policy-section" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "CommsTransportNew.vue",
    predecessorByteLength: 29_200,
    predecessorBlobId: "5fc0f740a673b7c10d6a43fad1bc209bab0069c7",
    predecessorSha256:
      "6aae5a50c304208f1fc95b9419919830dfe5dd181d4662ea08d72075b5f5f8be",
    roots: [
      root({
        boundary: 374,
        opening: '      <CadenceFormSectionFrame :id="form.sections.identity.id">',
        predecessorOpening: '      <section :id="form.sections.identity.id" class="space-y-4">',
      }),
      root({
        boundary: 401,
        opening: '      <CadenceFormSectionFrame :id="form.sections.origin.id">',
        predecessorOpening: '      <section :id="form.sections.origin.id" class="space-y-4">',
      }),
      root({
        boundary: 447,
        opening: '      <CadenceFormSectionFrame :id="form.sections.source.id">',
        predecessorOpening: '      <section :id="form.sections.source.id" class="space-y-4">',
      }),
      root({
        boundary: 542,
        opening: `        <CadenceFormSectionFrame
          v-for="section in form.direct_configuration.sections"
          :id="section.id"
          :key="section.id"
        >`,
        predecessorOpening: `        <section
          v-for="section in form.direct_configuration.sections"
          :id="section.id"
          :key="section.id"
          class="space-y-4"
        >`,
        closing: "        </CadenceFormSectionFrame>",
      }),
      root({
        boundary: 629,
        opening: '        <CadenceFormSectionFrame :id="form.sections.provider_capability.id">',
        predecessorOpening:
          '        <section :id="form.sections.provider_capability.id" class="space-y-4">',
        closing: "        </CadenceFormSectionFrame>",
      }),
      root({
        boundary: 723,
        opening: '        <CadenceFormSectionFrame :id="form.provider_derived.id">',
        predecessorOpening: '        <section :id="form.provider_derived.id" class="space-y-4">',
        closing: "        </CadenceFormSectionFrame>",
      }),
      root({
        boundary: 761,
        opening: '      <CadenceFormSectionFrame :id="form.sections.review.id">',
        predecessorOpening: '      <section :id="form.sections.review.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "ProviderAccountNew.vue",
    predecessorByteLength: 16_832,
    predecessorBlobId: "40e5f623b1bbf58881c5890a3d2f65001b434de8",
    predecessorSha256:
      "69d6a4485b685ddf6c1c386baa3b33a1a697f63ed2fd977585a3c8de1a4a407b",
    roots: [
      root({
        boundary: 248,
        opening: '      <CadenceFormSectionFrame :id="form.sections.network_identity.id">',
        predecessorOpening:
          '      <section :id="form.sections.network_identity.id" class="space-y-4">',
      }),
      root({
        boundary: 337,
        opening: `        <CadenceFormSectionFrame
          v-for="section in form.connector.configuration.sections"
          :id="section.id"
          :key="section.id"
        >`,
        predecessorOpening: `        <section
          v-for="section in form.connector.configuration.sections"
          :id="section.id"
          :key="section.id"
          class="space-y-4"
        >`,
        closing: "        </CadenceFormSectionFrame>",
      }),
      root({
        boundary: 417,
        opening: '      <CadenceFormSectionFrame :id="form.sections.credential_registry.id">',
        predecessorOpening:
          '      <section :id="form.sections.credential_registry.id" class="space-y-4">',
      }),
      root({
        boundary: 472,
        opening: '      <CadenceFormSectionFrame :id="form.sections.organization_guardrails.id">',
        predecessorOpening:
          '      <section :id="form.sections.organization_guardrails.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "SpacecraftEdit.vue",
    predecessorByteLength: 7_872,
    predecessorBlobId: "970a1a4d7ec7acd12debb4e0a90b9c11611c871c",
    predecessorSha256:
      "7746bd4fa6897a20744d33e7409524471191258781f99c6faf704c380a389bee",
    roots: [
      root({
        boundary: 174,
        opening: '      <CadenceFormSectionFrame :id="form.sections.identity.id">',
        predecessorOpening: '      <section :id="form.sections.identity.id" class="space-y-4">',
      }),
      root({
        boundary: 219,
        opening: '      <CadenceFormSectionFrame :id="form.sections.profile.id">',
        predecessorOpening: '      <section :id="form.sections.profile.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "SpacecraftNew.vue",
    predecessorByteLength: 8_399,
    predecessorBlobId: "534102f7f9d3f142ea8f9eda12399847882a0193",
    predecessorSha256:
      "64541054eadde7f40764860a10ed4e34e4a3cf29b2af8fd8c0532c1682bacf69",
    roots: [
      root({
        boundary: 174,
        opening: '      <CadenceFormSectionFrame :id="form.sections.identity.id">',
        predecessorOpening: '      <section :id="form.sections.identity.id" class="space-y-4">',
      }),
      root({
        boundary: 219,
        opening: '      <CadenceFormSectionFrame :id="form.sections.profile.id">',
        predecessorOpening: '      <section :id="form.sections.profile.id" class="space-y-4">',
      }),
    ],
  }),
  migration({
    file: "SpacecraftTypeNew.vue",
    predecessorByteLength: 17_768,
    predecessorBlobId: "e7ffffeca33fb4e9e89e4aeaa6eeaa2bd4192600",
    predecessorSha256:
      "2ff7c47ec43df0d98095235c62e1e73788b89427eb14434861f0444f0c3b7561",
    roots: [
      root({
        boundary: 280,
        opening: '      <CadenceFormSectionFrame :id="form.sections.identity.id">',
        predecessorOpening: '      <section :id="form.sections.identity.id" class="space-y-4">',
      }),
      root({
        boundary: 308,
        opening: '      <CadenceFormSectionFrame :id="form.sections.protocols.id">',
        predecessorOpening: '      <section :id="form.sections.protocols.id" class="space-y-4">',
      }),
      root({
        boundary: 363,
        opening: '      <CadenceFormSectionFrame :id="form.sections.frame_parameters.id">',
        predecessorOpening:
          '      <section :id="form.sections.frame_parameters.id" class="space-y-4">',
      }),
      root({
        boundary: 476,
        opening: '      <CadenceFormSectionFrame :id="form.sections.applications.id">',
        predecessorOpening:
          '      <section :id="form.sections.applications.id" class="space-y-4">',
      }),
    ],
  }),
])

export const formSectionFrameCallerNames = Object.freeze(
  formSectionFrameMigrations.map(({file}) => file),
)

export const formSectionFrameSha256 = source =>
  createHash("sha256").update(source).digest("hex")

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const formSectionFrameMigrationFor = caller => {
  const file = caller.split("/").at(-1)
  const migrationEntry = formSectionFrameMigrations.find(entry => entry.file === file)

  assert.ok(migrationEntry, `${caller} is an audited CadenceFormSectionFrame caller`)
  return migrationEntry
}

export const peelCadenceFormSectionFrame = (source, caller) => {
  const migrationEntry = formSectionFrameMigrationFor(caller)
  assert.equal(occurrences(source, formSectionFrameImport), 1, `${migrationEntry.file} frame import`)

  let predecessor = source.replace(formSectionFrameImport, "")
  for (const frameRoot of migrationEntry.roots) {
    assert.equal(
      occurrences(predecessor, frameRoot.opening),
      1,
      `${migrationEntry.file}:${frameRoot.boundary} frame opening`,
    )
    assert.equal(
      predecessor.indexOf(frameRoot.closing, predecessor.indexOf(frameRoot.opening) + frameRoot.opening.length) >= 0,
      true,
      `${migrationEntry.file}:${frameRoot.boundary} frame closing`,
    )
    const openingStart = predecessor.indexOf(frameRoot.opening)
    const closingStart = predecessor.indexOf(
      frameRoot.closing,
      openingStart + frameRoot.opening.length,
    )
    predecessor =
      predecessor.slice(0, openingStart) +
      frameRoot.predecessorOpening +
      predecessor.slice(openingStart + frameRoot.opening.length, closingStart) +
      frameRoot.predecessorClosing +
      predecessor.slice(closingStart + frameRoot.closing.length)
  }

  assert.doesNotMatch(predecessor, /CadenceFormSectionFrame/)
  return predecessor
}

export const peelCadenceFormSectionFrameBeforeOlderLayers = (source, caller) => {
  if (!formSectionFrameCallerNames.includes(caller.split("/").at(-1))) return source
  if (occurrences(source, formSectionFrameImport) === 0) return source
  return peelCadenceFormSectionFrame(source, caller)
}

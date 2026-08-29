import assert from "node:assert/strict"
import {createHash} from "node:crypto"

const noticeFrameImport =
  'import CadenceNoticeFrame from "./ui/components/CadenceNoticeFrame.vue"\n'
const lines = (...sourceLines) => sourceLines.join("\n")
const digest = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1

const boundary = (migrated, predecessor) => Object.freeze({migrated, predecessor})

export const noticeFrameCallerLedger = Object.freeze({
  "ProviderAccountNew.vue": Object.freeze({
    sha256: "cae02c196fc073c985a1f5003b158a0c484ccfc9a8c0921a99418e32e9bf7aa1",
    boundaries: Object.freeze([
      boundary(
        lines(
          "        <CadenceNoticeFrame",
          '          tone="info"',
          '          :id="form.connector.boundary.id"',
          "        >",
          "          {{ form.connector.boundary.text }}",
          "        </CadenceNoticeFrame>",
        ),
        lines(
          "        <div",
          '          :id="form.connector.boundary.id"',
          '          class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"',
          "        >",
          "          {{ form.connector.boundary.text }}",
          "        </div>",
        ),
      ),
    ]),
  }),
  "CommsProviderNew.vue": Object.freeze({
    sha256: "ffedf35b357318de713debb8de369d6918035f05cf7840ad3dcc6de94ea05e4e",
    boundaries: Object.freeze([
      boundary(
        lines(
          "        <CadenceNoticeFrame",
          '          v-if="visible(form.conditional.approval_guidance.visible_when)"',
          '          tone="info"',
          '          :id="form.conditional.approval_guidance.id"',
          "        >",
          "          {{ form.conditional.approval_guidance.text }}",
          "        </CadenceNoticeFrame>",
        ),
        lines(
          "        <div",
          '          v-if="visible(form.conditional.approval_guidance.visible_when)"',
          '          :id="form.conditional.approval_guidance.id"',
          '          class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"',
          "        >",
          "          {{ form.conditional.approval_guidance.text }}",
          "        </div>",
        ),
      ),
    ]),
  }),
  "CommsTransportNew.vue": Object.freeze({
    sha256: "eff7002986ca248c39bf9ff07f29e4cd8339a3d1d087cdc9ac93b31a8a1f5cec",
    boundaries: Object.freeze([
      boundary(
        lines(
          "          <CadenceNoticeFrame",
          '            v-if="form.provider.empty_state.visible"',
          '            tone="warning"',
          '            :id="form.provider.empty_state.id"',
          "          >",
          "            {{ form.provider.empty_state.message }}",
          "            <a",
          '              :href="form.provider.empty_state.action.href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="ml-1 text-primary hover:underline"',
          "            >{{ form.provider.empty_state.action.label }}</a>",
          "          </CadenceNoticeFrame>",
        ),
        lines(
          "          <div",
          '            v-if="form.provider.empty_state.visible"',
          '            :id="form.provider.empty_state.id"',
          '            class="border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70"',
          "          >",
          "            {{ form.provider.empty_state.message }}",
          "            <a",
          '              :href="form.provider.empty_state.action.href"',
          '              data-phx-link="redirect"',
          '              data-phx-link-state="push"',
          '              class="ml-1 text-primary hover:underline"',
          "            >{{ form.provider.empty_state.action.label }}</a>",
          "          </div>",
        ),
      ),
      boundary(
        lines(
          "            <CadenceNoticeFrame",
          '              v-if="form.provider.derivation_error"',
          '              tone="warning"',
          '              id="transport-provider-derivation-error"',
          "            >",
          "              {{ form.provider.derivation_error }}",
          "            </CadenceNoticeFrame>",
        ),
        lines(
          "            <div",
          '              v-if="form.provider.derivation_error"',
          '              id="transport-provider-derivation-error"',
          '              class="border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70"',
          "            >",
          "              {{ form.provider.derivation_error }}",
          "            </div>",
        ),
      ),
    ]),
  }),
})

export const peelCadenceNoticeFrames = (source, filename) => {
  const contract = noticeFrameCallerLedger[filename]
  if (!contract) return source

  assert.equal(occurrences(source, noticeFrameImport), 1, `${filename} notice import count`)
  assert.equal(
    occurrences(source, "<CadenceNoticeFrame\n"),
    contract.boundaries.length,
    `${filename} notice opening count`,
  )
  assert.equal(
    occurrences(source, "</CadenceNoticeFrame>"),
    contract.boundaries.length,
    `${filename} notice closing count`,
  )

  let reconstructed = source.replace(noticeFrameImport, "")

  for (const [index, contractBoundary] of contract.boundaries.entries()) {
    assert.equal(
      occurrences(reconstructed, contractBoundary.migrated),
      1,
      `${filename} notice boundary ${index + 1} migrated count`,
    )
    reconstructed = reconstructed.replace(contractBoundary.migrated, contractBoundary.predecessor)
  }

  assert.equal(
    occurrences(reconstructed, "CadenceNoticeFrame"),
    0,
    `${filename} has zero residual notice tokens`,
  )
  assert.equal(digest(reconstructed), contract.sha256, `${filename} preserves its frozen SHA-256`)
  return reconstructed
}

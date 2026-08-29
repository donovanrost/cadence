import assert from "node:assert/strict"
import {createHash} from "node:crypto"

const inlineWarningImport =
  'import CadenceInlineWarning from "./ui/components/CadenceInlineWarning.vue"\n'
const lines = (...sourceLines) => sourceLines.join("\n")
const digest = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const filenameFor = (path) => path.split("/").at(-1)

const boundary = (migrated, predecessor) => Object.freeze({migrated, predecessor})

export const inlineWarningCallerLedger = Object.freeze({
  "OpsContactRequirementTemplate.vue": Object.freeze({
    sha256: "45847b54ec2b5844e3770ff0ebd9e8d9f983f75b74e3bbbabb06628eedcfca40",
    boundaries: Object.freeze([
      boundary(
        lines(
          "        <CadenceInlineWarning",
          '          v-if="authorization.admin_required"',
          '          :id="authorization.admin_required.id"',
          "        >",
          "          {{ authorization.admin_required.copy }}",
          "        </CadenceInlineWarning>",
        ),
        lines(
          "        <p",
          '          v-if="authorization.admin_required"',
          '          :id="authorization.admin_required.id"',
          '          class="border-l-2 border-warning px-3 text-xs text-warning"',
          "        >",
          "          {{ authorization.admin_required.copy }}",
          "        </p>",
        ),
      ),
    ]),
  }),
  "OpsFleetPlanningPolicy.vue": Object.freeze({
    sha256: "5edf1caf91373f205de342638c071cb802f374d3675ca8230ae416b5bcf0b2aa",
    boundaries: Object.freeze([
      boundary(
        lines(
          "      <CadenceInlineWarning",
          '        v-if="authorization.admin_required"',
          "      >",
          "        {{ authorization.admin_required.copy }}",
          "      </CadenceInlineWarning>",
        ),
        lines(
          "      <p",
          '        v-if="authorization.admin_required"',
          '        class="border-l-2 border-warning px-3 text-xs text-warning"',
          "      >",
          "        {{ authorization.admin_required.copy }}",
          "      </p>",
        ),
      ),
    ]),
  }),
  "OpsContactPlanShow.vue": Object.freeze({
    sha256: "b8ceff7cb6e1fd083d0b7864aba44ceb32bbb56f7ef07f9d1cf2616a1f8ec2c9",
    boundaries: Object.freeze([
      boundary(
        lines(
          "          <CadenceInlineWarning",
          '            v-else-if="page.decision.admin_required !== null"',
          '            :id="page.decision.admin_required.id"',
          '            class="mt-4"',
          "          >{{ page.decision.admin_required.message }}</CadenceInlineWarning>",
        ),
        lines(
          "          <p",
          '            v-else-if="page.decision.admin_required !== null"',
          '            :id="page.decision.admin_required.id"',
          '            class="mt-4 border-l-2 border-warning px-3 text-xs text-warning"',
          "          >{{ page.decision.admin_required.message }}</p>",
        ),
      ),
    ]),
  }),
})

export const peelCadenceInlineWarnings = (source, path) => {
  const filename = filenameFor(path)
  const contract = inlineWarningCallerLedger[filename]
  if (!contract) return source

  assert.equal(occurrences(source, inlineWarningImport), 1, `${filename} inline warning import count`)
  assert.equal(
    occurrences(source, "<CadenceInlineWarning\n"),
    contract.boundaries.length,
    `${filename} inline warning opening count`,
  )
  assert.equal(
    occurrences(source, "</CadenceInlineWarning>"),
    contract.boundaries.length,
    `${filename} inline warning closing count`,
  )

  let reconstructed = source.replace(inlineWarningImport, "")

  for (const [index, contractBoundary] of contract.boundaries.entries()) {
    assert.equal(
      occurrences(reconstructed, contractBoundary.migrated),
      1,
      `${filename} inline warning boundary ${index + 1} migrated count`,
    )
    reconstructed = reconstructed.replace(contractBoundary.migrated, contractBoundary.predecessor)
  }

  assert.equal(
    occurrences(reconstructed, "CadenceInlineWarning"),
    0,
    `${filename} has zero residual inline warning tokens`,
  )
  assert.equal(digest(reconstructed), contract.sha256, `${filename} preserves its frozen SHA-256`)
  return reconstructed
}

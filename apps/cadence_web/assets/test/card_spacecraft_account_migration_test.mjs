import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {integrationRequire} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  "24.16.0",
  "spacecraft/account card migration contracts use pinned Node 24.16.0",
)

const base = "00c264585863a89a76d55484b777a7e73eda7fa5"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const panelImport = 'import CadencePanel from "./ui/components/CadencePanel.vue"\n'
const panelHeaderClass =
  "flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
const digest = (value) => createHash("sha256").update(value).digest("hex")
const count = (value, pattern) => value.match(pattern)?.length ?? 0
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")

const files = Object.freeze([
  {
    name: "ProviderAccountShow",
    filename: "ProviderAccountShow.vue",
    boundaryCount: 3,
    baseSha256: "0d6ae51559c3856d3e26b0f5913138304e72632ce2c57cdffc1ac89df8db4a13",
  },
  {
    name: "SpacecraftShow",
    filename: "SpacecraftShow.vue",
    boundaryCount: 4,
    baseSha256: "39b89791f1ba5110ec6f6780e5fba45ab6456f266e86d26478bb072ff29ac07b",
  },
  {
    name: "SpacecraftApplications",
    filename: "SpacecraftApplications.vue",
    boundaryCount: 3,
    baseSha256: "e77b860a9f5950a4b668139b049a030f6f5475972961a0f0afba7938284ab9d4",
  },
  {
    name: "SpacecraftTypeShow",
    filename: "SpacecraftTypeShow.vue",
    boundaryCount: 3,
    baseSha256: "f6f23fdc8dd91883af0fdb1e6df43196fb63841186918c2aafc4c22cf70c6776",
  },
  {
    name: "SpacecraftCommanding",
    filename: "SpacecraftCommanding.vue",
    boundaryCount: 2,
    baseSha256: "6f11a40fdfc320663ece11112e57c01b95253e499ae1cd8fda492a3492213472",
  },
  {
    name: "SpacecraftReadiness",
    filename: "SpacecraftReadiness.vue",
    boundaryCount: 1,
    baseSha256: "6e9d139ed3e5b09b334d28ee6438d44130350cbe4371a5838ee5b96647fc4543",
  },
  {
    name: "SpacecraftTelemetryDecom",
    filename: "SpacecraftTelemetryDecom.vue",
    boundaryCount: 1,
    baseSha256: "183b330cf3782d41e2da88b00a2c2455e6a05a1befe109f489bf20a3e58e9a22",
  },
])

assert.deepEqual(
  files.map(({boundaryCount}) => boundaryCount),
  [3, 4, 3, 3, 2, 1, 1],
  "the immutable per-file migration ledger stays exact",
)
assert.equal(
  files.reduce((total, {boundaryCount}) => total + boundaryCount, 0),
  17,
  "exactly seventeen conventional card boundaries migrate",
)

const multilineOpening = /^([ ]*)<CadenceCard$/
const inlineOpening = /^([ ]*)<CadenceCard ([^\n]+) body-class="card-body p-6">$/
const closingBoundary = /^([ ]*)<\/CadenceCard>$/

const peelCadencePanels = (source, name) => {
  if (name !== "ProviderAccountShow") return source

  let reconstructed = source.replace(panelImport, "")

  for (const id of ["page.grants.card_id", "page.grant_form_card.id", "page.audit.card_id"]) {
    reconstructed = reconstructed.replace(
      `        <CadencePanel
          :id="${id}"
          class="card bg-base-200 border border-base-300"
          header-class="${panelHeaderClass}"
        >
          <template #header>`,
      `        <section :id="${id}" class="card bg-base-200 border border-base-300">
          <div class="${panelHeaderClass}">`,
    )
  }

  return reconstructed
    .replaceAll(
      '          </template>\n          <div class="card-body p-0">',
      '          </div>\n          <div class="card-body p-0">',
    )
    .replace(
      '          </template>\n          <div class="card-body p-6">',
      '          </div>\n          <div class="card-body p-6">',
    )
    .replaceAll("        </CadencePanel>", "        </section>")
}

const countConventionalRawShells = (source) => {
  const lines = source.split("\n")
  let rawShells = 0

  for (let index = 0; index < lines.length; index += 1) {
    const multilineSection = lines[index].match(/^([ ]*)<section$/)
    const inlineSection = lines[index].match(/^([ ]*)<section\b.*>$/)

    if (multilineSection) {
      const indent = multilineSection[1]
      let boundaryEnd = index + 1

      while (boundaryEnd < lines.length && lines[boundaryEnd] !== `${indent}>`) {
        boundaryEnd += 1
      }

      if (lines[boundaryEnd + 1] === `${indent}  <div class="card-body p-6">`) {
        rawShells += 1
      }
    } else if (
      inlineSection &&
      lines[index + 1] === `${inlineSection[1]}  <div class="card-body p-6">`
    ) {
      rawShells += 1
    }
  }

  return rawShells
}

const reconstructBase = (source, expectedBoundaries, name) => {
  assert.equal(source.split(cardImport).length - 1, 1, `${name} imports CadenceCard once`)

  const lines = source.replace(cardImport, "").split("\n")
  const reconstructed = []
  let openingCount = 0
  let closingCount = 0

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const multiline = line.match(multilineOpening)
    const inline = line.match(inlineOpening)
    const closing = line.match(closingBoundary)

    if (multiline) {
      const indent = multiline[1]
      const attributes = []

      index += 1
      while (lines[index] !== `${indent}  body-class="card-body p-6"`) {
        assert.ok(
          lines[index]?.startsWith(`${indent}  `),
          `${name} keeps each multiline root attribute on the native boundary`,
        )
        attributes.push(lines[index])
        index += 1
      }

      index += 1
      assert.equal(lines[index], `${indent}>`, `${name} keeps the exact root indentation`)
      assert.ok(attributes.length > 0, `${name} keeps caller-owned root attributes`)
      reconstructed.push(
        `${indent}<section`,
        ...attributes,
        `${indent}>`,
        `${indent}  <div class="card-body p-6">`,
      )
      openingCount += 1
      continue
    }

    if (inline) {
      const [, indent, attributes] = inline

      reconstructed.push(
        `${indent}<section ${attributes}>`,
        `${indent}  <div class="card-body p-6">`,
      )
      openingCount += 1
      continue
    }

    if (closing) {
      const indent = closing[1]

      reconstructed.push(`${indent}  </div>`, `${indent}</section>`)
      closingCount += 1
      continue
    }

    reconstructed.push(line)
  }

  assert.equal(openingCount, expectedBoundaries, `${name} strips only its migrated openings`)
  assert.equal(closingCount, expectedBoundaries, `${name} strips only its migrated closings`)
  const reconstructedSource = reconstructed.join("\n")

  assert.doesNotMatch(reconstructedSource, /CadenceCard/)

  return reconstructedSource
}

for (const file of files) {
  const sourcePath = resolve(testDirectory, `../vue/${file.filename}`)
  const source = await readFile(sourcePath, "utf8")

  assert.equal(
    count(source, /<CadenceCard\b/g),
    file.boundaryCount,
    `${file.name} has its exact CadenceCard opening count`,
  )
  assert.equal(
    count(source, /<\/CadenceCard>/g),
    file.boundaryCount,
    `${file.name} has its exact CadenceCard closing count`,
  )
  assert.equal(
    count(source, /body-class="card-body p-6"/g),
    file.boundaryCount,
    `${file.name} passes the exact caller-authored body classes`,
  )
  assert.equal(
    countConventionalRawShells(source),
    0,
    `${file.name} leaves no conventional immediate raw p-6 shell`,
  )

  const reconstructed = reconstructBase(
    peelCadencePanels(source, file.name),
    file.boundaryCount,
    file.name,
  )

  assert.equal(
    digest(reconstructed),
    file.baseSha256,
    `${file.name} reconstructs source bytes from base ${base}`,
  )

  const parsed = parse(source, {filename: sourcePath})

  assert.deepEqual(parsed.errors, [], `${file.name} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${file.name} keeps script setup`)
  assert.ok(parsed.descriptor.template, `${file.name} keeps a template`)

  const compiled = compileScript(parsed.descriptor, {
    id: `card-spacecraft-account-${file.name}`,
    inlineTemplate: true,
  })

  assert.match(compiled.content, /render|_sfc_render/, `${file.name} compiles its inline template`)
}

console.log(
  "card_spacecraft_account_migration_test passed (17 boundaries, 7 exact base reconstructions)",
)

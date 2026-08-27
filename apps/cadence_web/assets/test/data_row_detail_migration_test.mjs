import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "detail migration uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const cardImport = 'import CadenceCard from "./ui/components/CadenceCard.vue"\n'
const dataRowImport = 'import CadenceDataRow from "./ui/components/CadenceDataRow.vue"\n'

const boundary = ({indent, attributes, baseOpen, label}) => ({
  componentOpen: [
    `${indent}<CadenceDataRow`,
    ...attributes.map(attribute => `${indent}  ${attribute}`),
    `${indent}>`,
  ].join("\n"),
  componentClose: `${indent}</CadenceDataRow>`,
  baseOpen,
  baseLabel: `${indent}  <span class="hud-data-label">${label}</span>`,
  baseClose: `${indent}</div>`,
})

const files = [
  {
    name: "SpacecraftShow.vue",
    path: resolve(testDirectory, "../vue/SpacecraftShow.vue"),
    baseHash: "85eecba9eae7b352f4e83650683597eeee8dcf61e5c5022ed9c6f757178996a3",
    cardCount: 4,
    rowCount: 5,
    boundaries: [
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="overview.scid.label"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ overview.scid.label }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="overview.display_name.label"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ overview.display_name.label }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="overview.spacecraft_id.label"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ overview.spacecraft_id.label }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="overview.mission.label"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ overview.mission.label }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row md:col-span-2"',
          'label-class="hud-data-label"',
          ':label="overview.organization_id.label"',
        ],
        baseOpen: '          <div class="hud-data-row md:col-span-2">',
        label: "{{ overview.organization_id.label }}",
      }),
    ],
  },
  {
    name: "ProviderAccountShow.vue",
    path: resolve(testDirectory, "../vue/ProviderAccountShow.vue"),
    baseHash: "4140d931337f0b58b40e76bdf3c8ceac5d9f1be92f41b65a5de972253f958721",
    cardCount: 3,
    rowCount: 4,
    boundaries: [
      boundary({
        indent: "              ",
        attributes: [
          'v-for="row in configuration.rows"',
          ':key="row.label"',
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="row.label"',
        ],
        baseOpen:
          '              <div v-for="row in configuration.rows" :key="row.label" class="hud-data-row">',
        label: "{{ row.label }}",
      }),
      boundary({
        indent: "                  ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="row.label"',
        ],
        baseOpen: '                  <div class="hud-data-row">',
        label: "{{ row.label }}",
      }),
      boundary({
        indent: "                ",
        attributes: [
          "v-else",
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="row.label"',
        ],
        baseOpen: '                <div v-else class="hud-data-row">',
        label: "{{ row.label }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'v-for="row in column"',
          ':key="row.label"',
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="row.label"',
        ],
        baseOpen:
          '          <div v-for="row in column" :key="row.label" class="hud-data-row">',
        label: "{{ row.label }}",
      }),
    ],
  },
  {
    name: "SpacecraftTypeShow.vue",
    path: resolve(testDirectory, "../vue/SpacecraftTypeShow.vue"),
    baseHash: "4abfa68e6fe35e677bb945d313381bb6273e7499247ceaf3f29c31b63625565f",
    cardCount: 3,
    rowCount: 5,
    boundaries: [
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="labels.downlink_protocol"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ labels.downlink_protocol }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="labels.uplink_protocol"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ labels.uplink_protocol }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="labels.packet_protocol"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ labels.packet_protocol }}",
      }),
      boundary({
        indent: "          ",
        attributes: [
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="labels.lifecycle"',
        ],
        baseOpen: '          <div class="hud-data-row">',
        label: "{{ labels.lifecycle }}",
      }),
      boundary({
        indent: "            ",
        attributes: [
          'v-for="parameter in profile.frame_parameters"',
          ':key="parameter.id"',
          ':row-id="parameter.id"',
          'row-class="hud-data-row"',
          'label-class="hud-data-label"',
          ':label="parameter.label"',
        ],
        baseOpen: [
          "            <div",
          '              v-for="parameter in profile.frame_parameters"',
          '              :id="parameter.id"',
          '              :key="parameter.id"',
          '              class="hud-data-row"',
          "            >",
        ].join("\n"),
        label: "{{ parameter.label }}",
      }),
    ],
  },
]

const rawRowRoot = /<div\b[^>]*\bclass="hud-data-row(?:\s[^"]*)?"[^>]*>/g
const multilineCardOpen = /^([ ]*)<CadenceCard$/
const inlineCardOpen = /^([ ]*)<CadenceCard ([^\n]+) body-class="card-body p-6">$/
const cardClose = /^([ ]*)<\/CadenceCard>$/

const reconstructCards = (source, expectedCardCount, fileName) => {
  assert.equal(source.split(cardImport).length - 1, 1, `${fileName} adds one card import`)
  assert.equal(source.match(/<CadenceCard\b/g)?.length, expectedCardCount)
  assert.equal(source.match(/<\/CadenceCard>/g)?.length, expectedCardCount)

  const lines = source.replace(cardImport, "").split("\n")
  const reconstructed = []
  let openingCount = 0
  let closingCount = 0

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const multiline = line.match(multilineCardOpen)
    const inline = line.match(inlineCardOpen)
    const closing = line.match(cardClose)

    if (multiline) {
      const indent = multiline[1]
      const attributes = []

      index += 1
      while (lines[index] !== `${indent}  body-class="card-body p-6"`) {
        assert.ok(
          lines[index]?.startsWith(`${indent}  `),
          `${fileName} keeps each multiline card attribute on its boundary`,
        )
        attributes.push(lines[index])
        index += 1
      }

      index += 1
      assert.equal(lines[index], `${indent}>`, `${fileName} keeps each card root indentation`)
      assert.ok(attributes.length > 0, `${fileName} keeps caller-owned card attributes`)
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

  assert.equal(openingCount, expectedCardCount, `${fileName} reconstructs every card opening`)
  assert.equal(closingCount, expectedCardCount, `${fileName} reconstructs every card closing`)

  const reconstructedSource = reconstructed.join("\n")

  assert.doesNotMatch(reconstructedSource, /CadenceCard/)

  return reconstructedSource
}

const reconstructBoundary = (source, rowBoundary, fileName) => {
  assert.equal(
    source.split(rowBoundary.componentOpen).length - 1,
    1,
    `${fileName} keeps each expected component opening exactly once`,
  )

  const openIndex = source.indexOf(rowBoundary.componentOpen)
  const slotStart = openIndex + rowBoundary.componentOpen.length
  const closeIndex = source.indexOf(rowBoundary.componentClose, slotStart)

  assert.ok(closeIndex > slotStart, `${fileName} keeps the expected component closing`)

  const callerOwnedValue = source.slice(slotStart, closeIndex)

  assert.match(callerOwnedValue, /^\n\s+<(?:a|span)\b/)
  assert.doesNotMatch(callerOwnedValue, /class="hud-data-label"/)

  const baseBoundary =
    rowBoundary.baseOpen +
    `\n${rowBoundary.baseLabel}` +
    callerOwnedValue +
    rowBoundary.baseClose

  return (
    source.slice(0, openIndex) +
    baseBoundary +
    source.slice(closeIndex + rowBoundary.componentClose.length)
  )
}

for (const file of files) {
  const source = await readFile(file.path, "utf8")

  assert.equal(file.boundaries.length, file.rowCount)
  assert.equal(source.split(dataRowImport).length - 1, 1, `${file.name} adds one import`)
  assert.equal(source.match(/<CadenceDataRow\b/g)?.length, file.rowCount)
  assert.equal(source.match(/row-class="hud-data-row(?:\s[^"]*)?"/g)?.length, file.rowCount)
  assert.equal(source.match(rawRowRoot)?.length ?? 0, 0, `${file.name} has no raw row roots`)

  let reconstructed = reconstructCards(source, file.cardCount, file.name).replace(
    dataRowImport,
    "",
  )

  for (const rowBoundary of file.boundaries) {
    reconstructed = reconstructBoundary(reconstructed, rowBoundary, file.name)
  }

  assert.doesNotMatch(reconstructed, /CadenceDataRow/)
  assert.equal(reconstructed.match(rawRowRoot)?.length, file.rowCount)
  assert.equal(
    createHash("sha256").update(reconstructed).digest("hex"),
    file.baseHash,
    `${file.name} reconstructs its immutable base byte-for-byte`,
  )
}

const spacecraftType = await readFile(files[2].path, "utf8")
const reconstructedSpacecraftType = files[2].boundaries.reduce(
  (source, rowBoundary) => reconstructBoundary(source, rowBoundary, files[2].name),
  reconstructCards(spacecraftType, files[2].cardCount, files[2].name).replace(dataRowImport, ""),
)

assert.equal(spacecraftType.match(/:row-id="parameter\.id"/g)?.length, 1)
assert.equal(spacecraftType.match(/:id="parameter\.id"/g)?.length ?? 0, 0)
assert.match(
  spacecraftType,
  /v-for="parameter in profile\.frame_parameters"\n\s+:key="parameter\.id"\n\s+:row-id="parameter\.id"/,
)
assert.equal(reconstructedSpacecraftType.match(/:id="parameter\.id"/g)?.length, 1)
assert.equal(reconstructedSpacecraftType.match(/:row-id="parameter\.id"/g)?.length ?? 0, 0)

assert.equal(files.reduce((count, file) => count + file.rowCount, 0), 14)
console.log("data_row_detail_migration_test passed (14 unique reconstructed rows)")

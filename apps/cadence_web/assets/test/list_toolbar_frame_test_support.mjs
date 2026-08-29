import assert from "node:assert/strict"

export const listToolbarFrameClass =
  "flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-2"

export const listToolbarFrameMigrations = Object.freeze([
  Object.freeze({
    file: "CommsGroundStationList.vue",
    importLine:
      'import CadenceListToolbarFrame from "./ui/components/CadenceListToolbarFrame.vue"\n',
    opening: '    <CadenceListToolbarFrame id="ground-stations-toolbar">',
    predecessorOpening: `    <div
      id="ground-stations-toolbar"
      class="${listToolbarFrameClass}"
    >`,
    closing: "    </CadenceListToolbarFrame>",
    predecessorClosing: "    </div>",
    currentSha256: "72435e60587d54aa25c7c1e0fca0ebe38b5de8a38312720e886ef7a51d68718e",
  }),
  Object.freeze({
    file: "CommsTransportList.vue",
    importLine:
      'import CadenceListToolbarFrame from "./ui/components/CadenceListToolbarFrame.vue";\n',
    opening: '    <CadenceListToolbarFrame id="transports-toolbar">',
    predecessorOpening: `    <div
      id="transports-toolbar"
      class="${listToolbarFrameClass}"
    >`,
    closing: "    </CadenceListToolbarFrame>",
    predecessorClosing: "    </div>",
    currentSha256: "16380da7163768eb6d09f12fe16dac75d5c3b97b0a6fa60bef7257a4f55727ae",
  }),
  Object.freeze({
    file: "SpacecraftList.vue",
    importLine:
      'import CadenceListToolbarFrame from "./ui/components/CadenceListToolbarFrame.vue"\n',
    opening: '          <CadenceListToolbarFrame id="spacecraft-roster-toolbar">',
    predecessorOpening: `          <div
            id="spacecraft-roster-toolbar"
            class="${listToolbarFrameClass}"
          >`,
    closing: "          </CadenceListToolbarFrame>",
    predecessorClosing: "          </div>",
    currentSha256: "e8cacfac123f4f92547045131ba28a651095a7cbcf2bcc959853f6afb617d318",
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const listToolbarFrameMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const migration = listToolbarFrameMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadenceListToolbarFrame caller`)
  return migration
}

export const peelCadenceListToolbarFrame = (source, caller) => {
  const migration = listToolbarFrameMigrationFor(caller)

  assert.equal(
    occurrences(source, migration.importLine),
    1,
    `${migration.file} has one exact CadenceListToolbarFrame import`,
  )
  assert.equal(
    source.match(/^import CadenceListToolbarFrame\b/gm)?.length,
    1,
    `${migration.file} has one CadenceListToolbarFrame import declaration`,
  )
  assert.equal(
    occurrences(source, migration.opening),
    1,
    `${migration.file} has one exact CadenceListToolbarFrame opening`,
  )
  assert.equal(
    occurrences(source, migration.closing),
    1,
    `${migration.file} has one exact CadenceListToolbarFrame closing`,
  )
  assert.equal(source.match(/<CadenceListToolbarFrame\b/g)?.length, 1)
  assert.equal(source.match(/<\/CadenceListToolbarFrame>/g)?.length, 1)

  const predecessor = source
    .replace(migration.importLine, "")
    .replace(migration.opening, migration.predecessorOpening)
    .replace(migration.closing, migration.predecessorClosing)

  assert.doesNotMatch(
    predecessor,
    /CadenceListToolbarFrame/,
    `${migration.file} toolbar peel leaves no residual frame`,
  )
  return predecessor
}

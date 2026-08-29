import assert from "node:assert/strict"
import {peelCompactTableFrames} from "./compact_table_frame_test_support.mjs"

export const paginationFrameClass =
  "flex items-center justify-between border-t border-base-300 px-4 py-2"

export const paginationFrameMigrations = Object.freeze([
  Object.freeze({
    file: "ApplicationHost.vue",
    importLine:
      'import CadencePaginationFrame from "./ui/components/CadencePaginationFrame.vue"\n',
    opening: `      <CadencePaginationFrame
        v-if="declarative_surface.table.pagination.visible"
        :id="declarative_surface.table.pagination.id"
      >`,
    predecessorOpening: `      <div
        v-if="declarative_surface.table.pagination.visible"
        :id="declarative_surface.table.pagination.id"
        class="${paginationFrameClass}"
      >`,
    closing: "      </CadencePaginationFrame>",
    predecessorClosing: "      </div>",
    parentSha256: "f96ee00476b6fac942be371363fbf0bde5840f55627dd3dbca60234bedb08fbf",
  }),
  Object.freeze({
    file: "CommsGroundStationList.vue",
    importLine:
      'import CadencePaginationFrame from "./ui/components/CadencePaginationFrame.vue"\n',
    opening: `    <CadencePaginationFrame
      v-if="total_count > page_size"
      id="ground-stations-pagination"
    >`,
    predecessorOpening: `    <div
      v-if="total_count > page_size"
      id="ground-stations-pagination"
      class="${paginationFrameClass}"
    >`,
    closing: "    </CadencePaginationFrame>",
    predecessorClosing: "    </div>",
    parentSha256: "32e919c9c0b9a848d84b0f364181342d7c8215380d4a14b4a7a0106a9978750c",
  }),
  Object.freeze({
    file: "CommsTransportList.vue",
    importLine:
      'import CadencePaginationFrame from "./ui/components/CadencePaginationFrame.vue";\n',
    opening: `    <CadencePaginationFrame
      v-if="total_count > page_size"
      id="transports-pagination"
    >`,
    predecessorOpening: `    <div
      v-if="total_count > page_size"
      id="transports-pagination"
      class="${paginationFrameClass}"
    >`,
    closing: "    </CadencePaginationFrame>",
    predecessorClosing: "    </div>",
    parentSha256: "5e049e6597d23ab0667458537d0c19a5ad90a37db4bf0c28cb4358bf44186941",
  }),
  Object.freeze({
    file: "SpacecraftList.vue",
    importLine:
      'import CadencePaginationFrame from "./ui/components/CadencePaginationFrame.vue"\n',
    opening: `          <CadencePaginationFrame
            v-if="roster.pagination_visible"
            id="spacecraft-roster-pagination"
          >`,
    predecessorOpening: `          <div
            v-if="roster.pagination_visible"
            id="spacecraft-roster-pagination"
            class="${paginationFrameClass}"
          >`,
    closing: "          </CadencePaginationFrame>",
    predecessorClosing: "          </div>",
    parentSha256: "8767b643d1b39c8ce3151aa0b60134839d776c7d319d7ec463df7cbb66128b78",
  }),
])

const occurrences = (source, fragment) => source.split(fragment).length - 1

export const paginationFrameMigrationFor = (caller) => {
  const file = caller.split("/").at(-1)
  const migration = paginationFrameMigrations.find((entry) => entry.file === file)

  assert.ok(migration, `${caller} is an audited CadencePaginationFrame caller`)
  return migration
}

export const peelCadencePaginationFrame = (source, caller) => {
  const migration = paginationFrameMigrationFor(caller)
  const predecessorCompatibleSource = peelCompactTableFrames(source, caller)

  assert.equal(
    occurrences(predecessorCompatibleSource, migration.importLine),
    1,
    `${migration.file} has one exact CadencePaginationFrame import`,
  )
  assert.equal(
    predecessorCompatibleSource.match(/^import CadencePaginationFrame\b/gm)?.length,
    1,
    `${migration.file} has one CadencePaginationFrame import declaration`,
  )
  assert.equal(
    occurrences(predecessorCompatibleSource, migration.opening),
    1,
    `${migration.file} has one exact CadencePaginationFrame opening`,
  )
  assert.equal(
    occurrences(predecessorCompatibleSource, migration.closing),
    1,
    `${migration.file} has one exact CadencePaginationFrame closing`,
  )
  assert.equal(predecessorCompatibleSource.match(/<CadencePaginationFrame\b/g)?.length, 1)
  assert.equal(predecessorCompatibleSource.match(/<\/CadencePaginationFrame>/g)?.length, 1)

  const predecessor = predecessorCompatibleSource
    .replace(migration.importLine, "")
    .replace(migration.opening, migration.predecessorOpening)
    .replace(migration.closing, migration.predecessorClosing)

  assert.doesNotMatch(
    predecessor,
    /CadencePaginationFrame/,
    `${migration.file} pagination peel leaves no residual frame`,
  )
  return predecessor
}

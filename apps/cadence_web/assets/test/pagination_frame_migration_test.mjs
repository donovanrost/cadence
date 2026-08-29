import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readdir, readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  paginationFrameClass,
  paginationFrameMigrations,
  peelCadencePaginationFrame,
} from "./pagination_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `pagination migration contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const expectedCallers = paginationFrameMigrations.map(({file}) => file).sort()
const vueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter((path) => path.endsWith(".vue"))
  .sort()
const sources = await Promise.all(
  vueFiles.map(async (relativePath) => ({
    relativePath,
    source: await readFile(resolve(vueDirectory, relativePath), "utf8"),
  })),
)
const migratedSources = sources.filter(({source}) => /<CadencePaginationFrame\b/.test(source))

assert.deepEqual(
  migratedSources.map(({relativePath}) => relativePath).sort(),
  expectedCallers,
  "exactly the four audited callers use CadencePaginationFrame",
)
assert.equal(
  sources.reduce(
    (total, {source}) =>
      total + (source.match(/^import CadencePaginationFrame\b/gm)?.length ?? 0),
    0,
  ),
  4,
  "the Vue source tree has no other CadencePaginationFrame importer",
)
assert.equal(
  sources.reduce(
    (total, {source}) => total + (source.match(/<CadencePaginationFrame\b/g)?.length ?? 0),
    0,
  ),
  4,
  "the Vue source tree has no other CadencePaginationFrame opening",
)
assert.equal(
  sources.reduce(
    (total, {source}) => total + (source.match(/<\/CadencePaginationFrame>/g)?.length ?? 0),
    0,
  ),
  4,
  "the Vue source tree has no other CadencePaginationFrame closing",
)

const dom = installDom('<div id="pagination-migration-compiler"></div>')
const reconstructedHashes = {}

for (const migration of paginationFrameMigrations) {
  const callerPath = resolve(vueDirectory, migration.file)
  const callerSource = await readFile(callerPath, "utf8")
  const slotStart = callerSource.indexOf(migration.opening) + migration.opening.length
  const slotEnd = callerSource.indexOf(migration.closing, slotStart)

  assert.ok(slotStart >= migration.opening.length, `${migration.file} opening remains exact`)
  assert.ok(slotEnd > slotStart, `${migration.file} closing follows its opening`)
  assert.equal(
    callerSource.match(/^import CadencePaginationFrame\b/gm)?.length,
    1,
    `${migration.file} imports the frame exactly once`,
  )
  assert.equal(callerSource.match(/<CadencePaginationFrame\b/g)?.length, 1)
  assert.equal(callerSource.match(/<\/CadencePaginationFrame>/g)?.length, 1)
  assert.equal(
    callerSource.split(`class="${paginationFrameClass}"`).length - 1,
    0,
    `${migration.file} transfers only the canonical class`,
  )

  const callerSlot = callerSource.slice(slotStart, slotEnd)

  assert.equal(callerSlot.match(/<span\b/g)?.length, 1, `${migration.file} keeps its range span`)
  assert.equal(
    callerSlot.match(/<div class="flex items-center gap-1">/g)?.length,
    1,
    `${migration.file} keeps its action cluster div`,
  )
  assert.equal(
    callerSlot.match(/<button\b/g)?.length,
    2,
    `${migration.file} keeps both native buttons`,
  )
  assert.doesNotMatch(callerSlot, /<Cadence(?:Button|PaginationValue)/)

  const predecessor = peelCadencePaginationFrame(callerSource, migration.file)
  const reconstructedHash = sha256(predecessor)

  assert.equal(
    reconstructedHash,
    migration.parentSha256,
    `${migration.file} reconstructs its exact 021468f source`,
  )
  reconstructedHashes[migration.file] = reconstructedHash

  const {component, descriptor} = await loadSfc(callerPath)

  assert.equal(typeof component, "object", `${migration.file} loads as an actual SFC`)
  assert.ok(descriptor.scriptSetup, `${migration.file} retains script setup`)
  assert.ok(descriptor.template, `${migration.file} retains its template`)
}

assert.deepEqual(reconstructedHashes, {
  "ApplicationHost.vue": "f96ee00476b6fac942be371363fbf0bde5840f55627dd3dbca60234bedb08fbf",
  "CommsGroundStationList.vue":
    "32e919c9c0b9a848d84b0f364181342d7c8215380d4a14b4a7a0106a9978750c",
  "CommsTransportList.vue":
    "5e049e6597d23ab0667458537d0c19a5ad90a37db4bf0c28cb4358bf44186941",
  "SpacecraftList.vue": "8767b643d1b39c8ce3151aa0b60134839d776c7d319d7ec463df7cbb66128b78",
})

dom.window.close()

console.log(
  "pagination_frame_migration_test passed (4 actual SFCs + 4 exact 021468f reconstructions)",
)

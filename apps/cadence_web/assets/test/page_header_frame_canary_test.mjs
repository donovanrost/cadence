import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(
  process.versions.node,
  "24.16.0",
  "page-header source canaries use pinned Node 24.16.0",
)

const parent = "da0c3b3abc92adcba09cc8450ffa2008b7066972"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const digest = value => createHash("sha256").update(value).digest("hex")
const count = (value, pattern) => value.match(pattern)?.length ?? 0

const migrations = Object.freeze([
  {
    name: "AdminHome compact header",
    path: resolve(testDirectory, "../vue/AdminHome.vue"),
    importLine:
      'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n',
    opening: '    <CadencePageHeaderFrame variant="compact">',
    originalOpening: '    <header class="border-b border-primary/20 pb-4">',
    closing: "    </CadencePageHeaderFrame>",
    originalClosing: "    </header>",
    parentSha256: "2c00619683ce2d78032115c3098dbaf57cc53856aaa69a842201a7e16dc6b82b",
  },
  {
    name: "OpsAlarms ops header",
    path: resolve(testDirectory, "../vue/OpsAlarms.vue"),
    importLine:
      'import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"\n',
    opening: '    <CadencePageHeaderFrame variant="ops">',
    originalOpening:
      '    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">',
    closing: "    </CadencePageHeaderFrame>",
    originalClosing: "    </header>",
    parentSha256: "690b780a665b1dab8fb8b27e17f8d596b7911ec118fc12ef2c2c3d7ceb9733c3",
  },
])

for (const migration of migrations) {
  const source = await readFile(migration.path, "utf8")

  assert.equal(source.split(migration.importLine).length - 1, 1, `${migration.name} import count`)
  assert.equal(source.split(migration.opening).length - 1, 1, `${migration.name} opening count`)
  assert.equal(source.split(migration.closing).length - 1, 1, `${migration.name} closing count`)
  assert.equal(count(source, /<CadencePageHeaderFrame\b/g), 1, `${migration.name} frame count`)
  assert.equal(count(source, /<header\b/g), 0, `${migration.name} has no residual native header`)

  const reconstructed = source
    .replace(migration.importLine, "")
    .replace(migration.opening, migration.originalOpening)
    .replace(migration.closing, migration.originalClosing)

  assert.doesNotMatch(reconstructed, /CadencePageHeaderFrame/)
  assert.equal(
    digest(reconstructed),
    migration.parentSha256,
    `${migration.name} reconstructs byte-for-byte to immutable parent ${parent}`,
  )
}

assert.equal(migrations.length, 2)
console.log(`page_header_frame_canary_test passed (2 immutable ${parent} reconstructions)`)

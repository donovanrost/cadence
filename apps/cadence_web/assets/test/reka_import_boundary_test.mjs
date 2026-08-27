import assert from "node:assert/strict"
import {readdir, readFile} from "node:fs/promises"
import {dirname, extname, join, posix, relative, resolve, sep} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "Reka import boundary uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueRoot = resolve(testDirectory, "../vue")
const adapterBoundary = "ui/reka/"

const deferredFeatureImporters = new Map()

const migratedFeatureConsumers = Object.freeze([
  "CatalogArtifactShow.vue",
  "CatalogDatabaseTable.vue",
  "CatalogDatabaseShow.vue",
  "DashboardToolbarMenu.vue",
  "MissionOverview.vue",
  "OpsContactRequirementShow.vue",
  "OpsDashboardDirectory.vue",
  "SpacecraftList.vue",
  "WidgetForm.vue",
])

const walkVueFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  entries.sort((left, right) => left.name.localeCompare(right.name))

  const nestedFiles = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name)
      if (entry.isDirectory()) return walkVueFiles(path)
      return entry.isFile() && extname(entry.name) === ".vue" ? [path] : []
    }),
  )

  return nestedFiles.flat()
}

const tokenizeJavaScript = (source) => {
  const tokens = []
  let index = 0

  while (index < source.length) {
    const character = source[index]
    const nextCharacter = source[index + 1]

    if (/\s/.test(character)) {
      index += 1
      continue
    }

    if (character === "/" && nextCharacter === "/") {
      index = source.indexOf("\n", index + 2)
      if (index === -1) break
      continue
    }

    if (character === "/" && nextCharacter === "*") {
      const commentEnd = source.indexOf("*/", index + 2)
      index = commentEnd === -1 ? source.length : commentEnd + 2
      continue
    }

    if (character === '"' || character === "'") {
      const quote = character
      let value = ""
      index += 1

      while (index < source.length && source[index] !== quote) {
        if (source[index] === "\\" && index + 1 < source.length) {
          value += source[index + 1]
          index += 2
        } else {
          value += source[index]
          index += 1
        }
      }

      tokens.push({type: "string", value})
      index += 1
      continue
    }

    if (/[A-Za-z_$]/.test(character)) {
      let identifierEnd = index + 1
      while (identifierEnd < source.length && /[A-Za-z0-9_$]/.test(source[identifierEnd])) {
        identifierEnd += 1
      }

      tokens.push({type: "identifier", value: source.slice(index, identifierEnd)})
      index = identifierEnd
      continue
    }

    tokens.push({type: "punctuator", value: character})
    index += 1
  }

  return tokens
}

const scriptBlocks = (source) =>
  [...source.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)].map((match) => match[1])

const directlyImportsReka = (source) =>
  scriptBlocks(source).some((script) => {
    const tokens = tokenizeJavaScript(script)

    return tokens.some((token, index) => {
      if (token.type !== "string" || token.value !== "reka-ui") return false

      const previous = tokens[index - 1]
      const beforePrevious = tokens[index - 2]

      return (
        previous?.value === "from" ||
        previous?.value === "import" ||
        (previous?.value === "(" && beforePrevious?.value === "import")
      )
    })
  })

assert.equal(
  directlyImportsReka(`<script setup>\nimport {\n  Toggle\n} from 'reka-ui'\n</script>`),
  true,
  "the scanner recognizes multiline single-quoted imports",
)
assert.equal(
  directlyImportsReka('<script setup>\nimport "reka-ui"\n</script>'),
  true,
  "the scanner recognizes double-quoted side-effect imports",
)
assert.equal(
  directlyImportsReka(`<script setup>\n// import {Toggle} from "reka-ui"\nconst name = 'reka-ui'\n</script>`),
  false,
  "comments and ordinary strings do not count as direct imports",
)

const vueFiles = await walkVueFiles(vueRoot)
const directImporters = (
  await Promise.all(
    vueFiles.map(async (path) => ({
      path: relative(vueRoot, path).split(sep).join(posix.sep).replaceAll("\\", "/"),
      source: await readFile(path, "utf8"),
    })),
  )
)
  .filter(({source}) => directlyImportsReka(source))
  .map(({path}) => path)
  .sort()

const directFeatureImporters = directImporters.filter((path) => !path.startsWith(adapterBoundary))
const expectedFeatureImporters = [...deferredFeatureImporters.keys()].sort()
const unapprovedFeatureImporters = directFeatureImporters.filter(
  (path) => !deferredFeatureImporters.has(path),
)
const missingDeferredImporters = expectedFeatureImporters.filter(
  (path) => !directFeatureImporters.includes(path),
)

if (unapprovedFeatureImporters.length > 0 || missingDeferredImporters.length > 0) {
  const formatEntries = (entries) =>
    entries.length > 0 ? entries.map((entry) => `  - ${entry}`).join("\n") : "  - (none)"

  assert.fail(
    [
      "Direct reka-ui feature importer boundary mismatch.",
      "Unapproved direct feature importers:",
      formatEntries(unapprovedFeatureImporters),
      "Missing explicitly deferred feature importers:",
      formatEntries(missingDeferredImporters),
      "Deferred entries are temporary defects, not safety or migration claims:",
      ...[...deferredFeatureImporters].map(([path, reason]) => `  - ${path}: ${reason}`),
    ].join("\n"),
  )
}

assert.deepEqual(directFeatureImporters, expectedFeatureImporters)

const migratedRegressions = migratedFeatureConsumers.filter((path) =>
  directImporters.includes(path),
)
assert.deepEqual(
  migratedRegressions,
  [],
  `Migrated feature consumers must not import reka-ui directly: ${migratedRegressions.join(", ")}`,
)

console.log(
  `reka_import_boundary_test passed; direct feature importers: ${directFeatureImporters.join(", ")}`,
)

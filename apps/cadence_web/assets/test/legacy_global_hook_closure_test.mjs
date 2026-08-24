import assert from "node:assert/strict"
import {constants} from "node:fs"
import {access, readdir, readFile} from "node:fs/promises"
import {dirname, extname, join, relative, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "closure contract uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const cadenceWebRoot = resolve(testDirectory, "../..")
const appPath = resolve(cadenceWebRoot, "assets/js/app.js")
const designSystemReadmePath = resolve(cadenceWebRoot, "design-system/README.md")
const tableDesignCardPath = resolve(cadenceWebRoot, "design-system/components/table.html")
const runtimeRoots = [
  resolve(cadenceWebRoot, "assets/js"),
  resolve(cadenceWebRoot, "lib/cadence_web"),
]
const retiredSourcePaths = [
  resolve(cadenceWebRoot, "assets/js/hooks/overlay.js"),
  resolve(cadenceWebRoot, "assets/js/hooks/resizable_panel.js"),
  resolve(cadenceWebRoot, "design-system/components/action-menu.html"),
  resolve(cadenceWebRoot, "lib/cadence_web/components/overlay.ex"),
  resolve(cadenceWebRoot, "lib/cadence_web/live/spacecraft_list_components.ex"),
]

const sourceExtensions = new Set([".ex", ".heex", ".js", ".mjs", ".ts"])

const walkSourceFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name)
      if (entry.isDirectory()) return walkSourceFiles(path)
      return sourceExtensions.has(extname(entry.name)) ? [path] : []
    }),
  )

  return nested.flat()
}

for (const path of retiredSourcePaths) {
  await assert.rejects(access(path, constants.F_OK), {code: "ENOENT"})
}

const appSource = await readFile(appPath, "utf8")
assert.doesNotMatch(appSource, /hooks\/(?:overlay|resizable_panel)/)
assert.doesNotMatch(appSource, /\b(?:Overlay|ResizablePanel)\b/)
assert.match(appSource, /const Hooks = \{\s*LiveToast: createLiveToastHook\(\)\s*\}/)
assert.match(appSource, /hooks: \{\.\.\.Hooks, \.\.\.getHooks\(liveVueApp\)\}/)

const [designSystemReadmeSource, tableDesignCardSource] = await Promise.all([
  readFile(designSystemReadmePath, "utf8"),
  readFile(tableDesignCardPath, "utf8"),
])

assert.doesNotMatch(designSystemReadmeSource, /\.action_menu\b/)
assert.doesNotMatch(tableDesignCardSource, /\.action_menu\b/)

const runtimeFiles = (await Promise.all(runtimeRoots.map(walkSourceFiles))).flat()
const runtimeSources = await Promise.all(
  runtimeFiles.map(async (path) => ({path, source: await readFile(path, "utf8")})),
)
const forbiddenRuntimeSurfaces = [
  ["legacy hook import", /hooks\/(?:overlay|resizable_panel)/],
  ["legacy HEEx hook renderer", /phx-hook\s*=\s*["'](?:Overlay|ResizablePanel)["']/],
  ["retired component caller", /<\.(?:action_menu|resizable_split)\b/],
  ["retired component API", /CadenceWeb\.CoreComponents\.(?:action_menu|resizable_split)\b/],
  ["retired overlay module", /CadenceWeb\.Components\.Overlay\b/],
  ["orphan spacecraft component module", /CadenceWeb\.SpacecraftListComponents\b/],
]

const violations = runtimeSources.flatMap(({path, source}) =>
  forbiddenRuntimeSurfaces.flatMap(([surface, pattern]) =>
    pattern.test(source) ? [`${relative(cadenceWebRoot, path)}: ${surface}`] : [],
  ),
)

assert.deepEqual(violations, [])

console.log("legacy_global_hook_closure_test passed")

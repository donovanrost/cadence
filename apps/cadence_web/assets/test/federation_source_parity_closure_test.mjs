import assert from "node:assert/strict"
import {readdir, readFile} from "node:fs/promises"
import {dirname, extname, join, relative, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "source closure uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const webRoot = resolve(testDirectory, "../..")
const policy = JSON.parse(
  await readFile(resolve(webRoot, "assets/federation-host-owned-surfaces.json"), "utf8"),
)

const walkFiles = async (directory) => {
  const entries = await readdir(directory, {withFileTypes: true})
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name)
      return entry.isDirectory() ? walkFiles(path) : [path]
    }),
  )

  return nested.flat()
}

const sourceFiles = (await walkFiles(resolve(webRoot, "lib/cadence_web"))).filter((path) =>
  [".ex", ".heex"].includes(extname(path)),
)
const sourceByPath = new Map()
const mounts = []

for (const path of sourceFiles) {
  const source = await readFile(path, "utf8")
  sourceByPath.set(path, source)

  for (const match of source.matchAll(/<\.vue\b([\s\S]*?)\/>/g)) {
    const component = match[1].match(/\bv-component="([^"]+)"/)?.[1]
    assert.ok(component, `${relative(webRoot, path)} has a named v-component mount`)
    mounts.push({
      component,
      path,
      line: source.slice(0, match.index).split("\n").length,
    })
  }
}

const federatedMounts = mounts.filter(({component}) => component === policy.federated_component)
const directRouteShellMounts = federatedMounts.filter(
  ({path}) => !path.endsWith("/live/application_host_live.ex"),
)
assert.equal(
  directRouteShellMounts.length,
  78,
  "source contains 78 direct first-party FederatedFullPageSurface route-shell mounts",
)

const policyFallbackNames = new Set(policy.local_fallbacks.map(({component}) => component))
const localMounts = mounts.filter(({component}) => component !== policy.federated_component)
for (const {component, path, line} of localMounts) {
  assert.equal(
    policyFallbackNames.has(component),
    true,
    `${relative(webRoot, path)}:${line} uses a policy-approved local fallback`,
  )
}
assert.deepEqual(
  [...new Set(localMounts.map(({component}) => component))].sort(),
  [...policyFallbackNames].sort(),
  "local mount occurrences reduce to exactly the policy fallback names",
)

for (const path of new Set(directRouteShellMounts.map(({path}) => path))) {
  const source = sourceByPath.get(path)
  assert.doesNotMatch(source, /\bhandle_(?:event|info|async)\b/)
  assert.doesNotMatch(source, /\bv-on(?::|\s*=)/)
  assert.equal(
    mounts.some(
      (mount) => mount.path === path && mount.component !== policy.federated_component,
    ),
    false,
    `${relative(webRoot, path)} has no legacy page SFC reference`,
  )
}

console.log("federation_source_parity_closure_test passed")

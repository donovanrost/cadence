import assert from "node:assert/strict"
import {access, readdir, readFile} from "node:fs/promises"
import {dirname, extname, join, relative, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "identity contract uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const webRoot = resolve(testDirectory, "../..")
const policyPath = resolve(webRoot, "assets/federation-host-owned-surfaces.json")
const policy = JSON.parse(await readFile(policyPath, "utf8"))

assert.equal(policy.schema, "cadence.federation-host-owned-surfaces.v1")
assert.deepEqual(policy.surface_classifications, {
  organization_admin: "organization_admin",
  telemetry_decom: "nested",
})
assert.ok(Array.isArray(policy.surface_identities))
assert.ok(policy.surface_identities.length > 0)
assert.equal(policy.surface_identities.length, 86, "policy contains the complete 86-identity set")

const expectedApplications = {
  mission_catalog: {
    release: /^mission-catalog-[a-z0-9_]+-v1$/,
    remote: "cadence_mission_catalog",
    manifest: "/assets/application-host/mission-catalog/mf-manifest.json",
    classification: "full_page",
  },
  spacecraft: {
    release: /^spacecraft-v1$/,
    remote: "cadence_spacecraft",
    manifest: "/assets/application-host/spacecraft/mf-manifest.json",
    classification: "full_page",
  },
  comms: {
    release: /^comms-v1$/,
    remote: "cadence_comms",
    manifest: "/assets/application-host/comms/mf-manifest.json",
    classification: "full_page",
  },
  ops_console: {
    release: /^ops-console-v1$/,
    remote: "cadence_ops_console",
    manifest: "/assets/application-host/ops-console/mf-manifest.json",
    classification: "full_page",
  },
  organization_admin: {
    release: /^organization-admin-v1$/,
    remote: "cadence_organization_admin",
    manifest: "/assets/application-host/organization-admin/mf-manifest.json",
    classification: "organization_admin",
  },
  telemetry_decom: {
    release: /^telemetry-decom-v1$/,
    remote: "cadence_telemetry_decom",
    manifest: "/assets/application-host/telemetry-decom/mf-manifest.json",
    classification: "nested",
  },
}

const identityKeys = new Set()
const identitiesByApplication = new Map()

for (const identity of policy.surface_identities) {
  assert.deepEqual(
    Object.keys(identity).sort(),
    [
      "application_key",
      "application_version",
      "classification",
      "exposed_module",
      "manifest_path",
      "query_id",
      "query_version",
      "release_id",
      "remote_name",
      "surface_id",
      "surface_version",
    ].sort(),
    `identity fields are complete for ${identity.application_key}/${identity.surface_id}`,
  )

  const application = expectedApplications[identity.application_key]
  assert.ok(application, `identity application is registered: ${identity.application_key}`)
  assert.equal(identity.application_version, 1)
  assert.equal(identity.surface_version, 1)
  assert.equal(identity.query_version, 1)
  assert.match(identity.surface_id, /^[a-z][a-z0-9_]*$/)
  assert.match(identity.query_id, /^cadence\.[a-z0-9_]+\.[a-z0-9_.]+$/)
  assert.equal(identity.release_id.match(application.release)?.[0], identity.release_id)
  assert.equal(identity.remote_name, application.remote)
  assert.equal(identity.manifest_path, application.manifest)
  assert.equal(identity.exposed_module, "./Application")
  const classification = identity.surface_id === "telemetry_decom" ? "nested" : application.classification
  assert.equal(identity.classification, classification)

  const key = `${identity.application_key}/${identity.surface_id}`
  assert.equal(identityKeys.has(key), false, `duplicate host surface identity: ${key}`)
  identityKeys.add(key)
  const surfaces = identitiesByApplication.get(identity.application_key) || []
  surfaces.push(identity)
  identitiesByApplication.set(identity.application_key, surfaces)
}

assert.deepEqual([...identitiesByApplication.keys()].sort(), Object.keys(expectedApplications).sort())
const expectedSurfaceCounts = {
  mission_catalog: 10,
  spacecraft: 12,
  comms: 15,
  ops_console: 35,
  organization_admin: 12,
  telemetry_decom: 2,
}
assert.deepEqual(
  Object.fromEntries(
    [...identitiesByApplication.entries()]
      .map(([applicationKey, surfaces]) => [applicationKey, surfaces.length])
      .sort(([left], [right]) => left.localeCompare(right)),
  ),
  expectedSurfaceCounts,
  "policy surface counts match the authoritative application ledgers",
)
assert.deepEqual(
  identitiesByApplication.get("telemetry_decom")?.map(({surface_id}) => surface_id),
  ["manage", "packet_bindings"],
  "nested telemetry_decom keeps both released surfaces",
)
assert.equal(
  policy.surface_identities.find(
    ({application_key, surface_id}) => application_key === "spacecraft" && surface_id === "telemetry_decom",
  )?.classification,
  "nested",
  "the spacecraft-hosted telemetry_decom surface is explicitly nested",
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

const runtimeSourceFiles = (await walkFiles(resolve(webRoot, "lib/cadence_web"))).filter((path) =>
  [".ex", ".heex"].includes(extname(path)),
)
const sourceMounts = []
const sourceByPath = new Map()

for (const path of runtimeSourceFiles) {
  const source = await readFile(path, "utf8")
  sourceByPath.set(path, source)

  for (const match of source.matchAll(/<\.vue\b([\s\S]*?)\/>/g)) {
    const component = match[1].match(/\bv-component="([^"]+)"/)?.[1]
    assert.ok(component, `${relative(webRoot, path)} has a named v-component mount`)
    sourceMounts.push({
      component,
      path,
      line: source.slice(0, match.index).split("\n").length,
    })
  }
}

const federatedMounts = sourceMounts.filter(
  ({component}) => component === policy.federated_component,
)
const directRouteShellFederatedMounts = federatedMounts.filter(
  ({path}) => !path.endsWith("/live/application_host_live.ex"),
)
assert.equal(
  directRouteShellFederatedMounts.length,
  78,
  "first-party route shells keep 78 direct FederatedFullPageSurface mounts",
)

const fallbackNames = new Set(policy.local_fallbacks.map(({component}) => component))
const localMounts = sourceMounts.filter(({component}) => component !== policy.federated_component)
const discoveredFallbackNames = new Set(localMounts.map(({component}) => component))
assert.equal(policy.local_fallbacks.length, 14, "fallback policy has 14 unique records")
assert.equal(fallbackNames.size, 14, "fallback policy records are unique component names")
for (const {component, path, line} of localMounts) {
  assert.equal(
    fallbackNames.has(component),
    true,
    `${relative(webRoot, path)}:${line} uses a policy-approved local fallback`,
  )
}
assert.deepEqual(
  [...discoveredFallbackNames].sort(),
  [...fallbackNames].sort(),
  "discovered local fallback mounts reduce exactly to the policy fallback names",
)

for (const path of new Set(directRouteShellFederatedMounts.map(({path}) => path))) {
  const source = sourceByPath.get(path)
  assert.doesNotMatch(source, /\bhandle_(?:event|info|async)\b/)
  assert.doesNotMatch(source, /\bv-on(?::|\s*=)/)
  assert.equal(
    sourceMounts.some(
      (mount) => mount.path === path && mount.component !== policy.federated_component,
    ),
    false,
    `${relative(webRoot, path)} has no legacy page SFC mount alongside its federated surface`,
  )
}

const vueRoot = resolve(webRoot, "assets/vue")
const reachableSfcPaths = new Map()
const missingVueImports = []

const visitSfc = async (path) => {
  if (reachableSfcPaths.has(path)) return

  const source = await readFile(path, "utf8")
  const imports = []
  for (const match of source.matchAll(/(?:from\s+|import\s*\(\s*)(["'])([^"']+)\1/g)) {
    const specifier = match[2]
    if (!specifier.startsWith(".") || !specifier.endsWith(".vue")) continue

    const importedPath = resolve(dirname(path), specifier)
    try {
      await access(importedPath)
    } catch {
      missingVueImports.push(`${relative(vueRoot, path)} -> ${specifier}`)
      continue
    }
    imports.push(importedPath)
  }

  reachableSfcPaths.set(path, imports)
  await Promise.all(imports.map(visitSfc))
}

for (const component of discoveredFallbackNames) {
  await visitSfc(resolve(vueRoot, `${component}.vue`))
}

const allSfcPaths = (await walkFiles(vueRoot)).filter((path) => extname(path) === ".vue")
const unreachableSfcPaths = allSfcPaths.filter((path) => !reachableSfcPaths.has(path))
assert.equal(reachableSfcPaths.size, 32, "local fallback roots reach exactly 32 Vue SFCs")
assert.deepEqual(missingVueImports, [], "local fallback SFC imports are complete")
assert.deepEqual(
  unreachableSfcPaths,
  [],
  "every Vue SFC is reachable from a discovered local fallback root",
)

const retiredComponents = [
  "CatalogDatabaseTable",
  "CatalogUploadForm",
  "OpsAlarms",
  "OpsCommands",
  "OpsContactDetail",
  "OpsContactPlanShow",
  "OpsContactRecord",
  "OpsContactRequirementList",
  "OpsContactRequirementNew",
  "OpsContactRequirementShow",
  "OpsContactRequirementTemplate",
  "OpsContactSchedule",
  "OpsDashboardActivity",
  "OpsDashboardDiagnostics",
  "OpsDashboardSnapshot",
  "OpsDataOperations",
  "OpsDataSources",
  "OpsFleetPlanning",
  "OpsFleetPlanningNew",
  "OpsFleetPlanningPolicy",
  "OpsFleetPlanningRun",
  "OpsTelemetryExplore",
  "OpsTimeline",
]
assert.equal(
  policy.local_fallbacks.filter(({component}) => component === "ApplicationHost").length,
  1,
  "ApplicationHost has one unique policy record",
)
for (const component of retiredComponents) {
  assert.equal(fallbackNames.has(component), false, `${component} has no stale local fallback policy entry`)
  await assert.rejects(
    import(`../vue/${component}.vue`),
    /Unknown file extension|ERR_UNKNOWN_FILE_EXTENSION|Cannot find module/,
    `${component} has no local SFC artifact`,
  )
}

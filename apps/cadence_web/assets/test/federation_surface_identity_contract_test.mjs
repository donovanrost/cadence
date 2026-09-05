import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

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
assert.equal(
  identitiesByApplication.get("organization_admin")?.length,
  12,
  "organization_admin keeps its complete classified surface set",
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

const fallbackNames = new Set(policy.local_fallbacks.map(({component}) => component))
const actualLocalFallbackMounts = [
  "AuthLayoutBrand",
  "NoOrganizationPage",
  "OrganizationInvitationPage",
  "AdminModePage",
  "UserSession",
  "ApplicationHost",
  "ApplicationHost",
  "GlobalSidebarNavigation",
  "MissionSidebarNavigation",
  "UserMenu",
  "NotificationsBell",
  "OpsStatusBar",
  "OpsNavRail",
  "OpsApplicationDock",
  "OpsContextRail",
]
assert.equal(policy.local_fallbacks.length, 14, "fallback policy has 14 unique records")
assert.equal(fallbackNames.size, 14, "fallback policy records are unique component names")
assert.equal(actualLocalFallbackMounts.length, 15, "the host has 15 actual local fallback mount occurrences")
assert.deepEqual(
  [...new Set(actualLocalFallbackMounts)].sort(),
  [...fallbackNames].sort(),
  "actual local fallback mounts reduce to the policy's 14 unique names",
)
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

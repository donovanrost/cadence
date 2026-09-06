import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {createRequire} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {installDom, integrationRequire, flushVue} from "./reka_adapter_test_support.mjs"

assert.equal(process.versions.node, "24.16.0", "federation adapter uses pinned Node 24.16.0")

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/federated_full_page_surface.ts")
const componentSource = await readFile(componentPath, "utf8")
const {transformSync} = integrationRequire("esbuild")
const moduleRequire = createRequire(componentPath)
const transformed = transformSync(componentSource, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})

const dom = installDom('<div id="app"></div>')
const loadedModule = {exports: {}}
new Function("require", "module", "exports", transformed.code)(
  moduleRequire,
  loadedModule,
  loadedModule.exports,
)

const {FederatedFullPageSurface, catalogUrlForPlacement} = loadedModule.exports
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")

const missionId = "mission/with spaces"
const spacecraftId = "spacecraft?primary"
const organizationId = "organization/primary"
const userId = "user?primary"
const applicationKey = "ops/console"
const surfaceId = "dashboard directory"
const filter = new URLSearchParams({application_key: applicationKey, surface_id: surfaceId}).toString()
const genericUrl = `/api/cadence/application-host/v1/catalog?${filter}`
const placements = [
  ["organization", `${genericUrl}&scope=organization&organization_id=${encodeURIComponent(organizationId)}`],
  ["user", `${genericUrl}&scope=user&user_id=${encodeURIComponent(userId)}`],
  ["admin", `${genericUrl}&scope=admin`],
  [
    "mission",
    `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog?${filter}&scope=mission&${new URLSearchParams({mission_id: missionId})}`,
  ],
  [
    "spacecraft",
    `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog?${filter}&scope=spacecraft&${new URLSearchParams({mission_id: missionId, spacecraft_id: spacecraftId})}`,
  ],
]

assert.equal(placements.length, 5)
for (const [hostScope, expectedCatalogUrl] of placements) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.append(host)
  const app = createApp(
    defineComponent({
      setup: () => () =>
        h(FederatedFullPageSurface, {
          applicationKey,
          surfaceId,
          hostScope,
          organizationId: hostScope === "organization" ? organizationId : undefined,
          userId: hostScope === "user" ? userId : undefined,
          missionId: hostScope === "organization" || hostScope === "user" || hostScope === "admin" ? undefined : missionId,
          spacecraftId: hostScope === "spacecraft" ? spacecraftId : undefined,
          class: "caller-owned-class",
          style: "display: block",
        }),
    }),
  )

  app.mount(host)
  await flushVue(nextTick)
  const root = host.querySelector("#cadence-federation-root")

  assert.ok(root, `${hostScope} placement renders its federation root`)
  assert.equal(root.getAttribute("data-host-scope"), hostScope)
  assert.equal(root.getAttribute("data-catalog-url"), expectedCatalogUrl)
  assert.equal(root.getAttribute("class"), "caller-owned-class")
  assert.equal(root.getAttribute("style"), "display: block;")
  app.unmount()
  host.remove()
}

assert.equal(
  catalogUrlForPlacement(
    "organization",
    applicationKey,
    surfaceId,
    undefined,
    undefined,
    organizationId,
  ),
  `${genericUrl}&scope=organization&organization_id=${encodeURIComponent(organizationId)}`,
)
assert.equal(
  catalogUrlForPlacement("mission", applicationKey, surfaceId, missionId),
  `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/catalog?${filter}&scope=mission&${new URLSearchParams({mission_id: missionId})}`,
)
assert.equal(
  catalogUrlForPlacement("spacecraft", applicationKey, surfaceId, missionId, spacecraftId),
  `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/catalog?${filter}&scope=spacecraft&${new URLSearchParams({mission_id: missionId, spacecraft_id: spacecraftId})}`,
)
assert.equal(catalogUrlForPlacement("mission", applicationKey, surfaceId), genericUrl)
assert.equal(catalogUrlForPlacement("spacecraft", applicationKey, surfaceId, missionId), genericUrl)

console.log("federated_full_page_surface_adapter_test passed")

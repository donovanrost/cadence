import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {readFile} from "node:fs/promises"
import {dirname, extname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  peelResidualCadenceCard,
  residualCadenceCardMigrations,
} from "./residual_cadence_cards_test_support.mjs"

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
const scenarios = Object.freeze([
  "the real three caller SFCs compile only after JSDOM globals exist",
  "each newest-first inverse peel reconstructs one frozen immediate predecessor boundary",
  "the pre-existing CadenceCard import stays singular and unpeeled",
  "each migrated shell serializes exactly like its immediate predecessor",
  "root attributes and the catalog v-else branch forward to one native section",
  "each body remains one native div with its exact caller-selected class",
  "caller descendants retain native identity across reactive updates",
  "the admin Phoenix redirect anchor remains outside and owns the card",
  "the catalog conditional table keyed row menu trigger and redirect remain caller-owned",
  "the catalog Reka menu keeps its public IDREFs and portaled native action",
  "the comms summary keeps its dynamic ID values and status class",
  "the three caller imports and surrounding presentation topology remain source-auditable",
])

assert.equal(process.execPath, pinnedNode)
assert.equal(process.versions.node, expectedNodeVersion)
assert.equal(scenarios.length, 12)
assert.equal(residualCadenceCardMigrations.length, 3)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const dom = installDom(
  '<main id="residual-cards-oracle"><div id="admin-host"></div><div id="catalog-host"></div><div id="comms-host"></div></main>',
)

for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLAnchorElement",
  "HTMLButtonElement",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "FormData",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const {createApp, defineComponent, h, nextTick, reactive, ref} = integrationRequire("vue")

const compileCaller = (source, filename, id) => {
  const moduleCache = new Map()

  const loadLocalModule = (modulePath) => {
    if (moduleCache.has(modulePath)) return moduleCache.get(modulePath).exports

    const loadedModule = {exports: {}}
    moduleCache.set(modulePath, loadedModule)
    const extension = extname(modulePath)
    let moduleSource = readFileSync(modulePath, "utf8")
    let loader = extension === ".ts" ? "ts" : "js"

    if (extension === ".vue") {
      const parsed = parse(moduleSource, {filename: modulePath})
      assert.deepEqual(parsed.errors, [], `${modulePath} parses as a real local dependency`)
      moduleSource = compileScript(parsed.descriptor, {
        id: `residual-card-dependency-${modulePath.split("/").at(-1)}`,
        inlineTemplate: true,
      }).content
      loader = "ts"
    }

    const transformed = transformSync(moduleSource, {
      format: "cjs",
      loader,
      platform: "node",
      target: "node24",
    })
    const localRequire = (specifier) =>
      specifier.startsWith(".")
        ? loadLocalModule(resolve(dirname(modulePath), specifier))
        : integrationRequire(specifier)

    new Function("require", "module", "exports", transformed.code)(
      localRequire,
      loadedModule,
      loadedModule.exports,
    )
    return loadedModule.exports
  }

  const parsed = parse(source, {filename})
  assert.deepEqual(parsed.errors, [], `${filename} parses for the exact-DOM mount`)
  assert.ok(parsed.descriptor.scriptSetup, `${filename} retains its real setup script`)
  assert.ok(parsed.descriptor.template, `${filename} retains its real template`)

  const compiled = compileScript(parsed.descriptor, {id, inlineTemplate: true})
  const transformed = transformSync(compiled.content, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) =>
    specifier.startsWith(".")
      ? loadLocalModule(resolve(dirname(filename), specifier))
      : integrationRequire(specifier)

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )
  return loadedModule.exports.default
}

const sources = new Map()
const components = new Map()

for (const migration of residualCadenceCardMigrations) {
  const callerPath = resolve(vueDirectory, migration.file)
  const source = await readFile(callerPath, "utf8")
  const predecessor = peelResidualCadenceCard(source, migration.file)

  sources.set(migration.file, source)
  components.set(migration.file, {
    current: compileCaller(source, callerPath, `residual-card-current-${migration.file}`),
    predecessor: compileCaller(
      predecessor,
      callerPath,
      `residual-card-predecessor-${migration.file}`,
    ),
  })
}

const adminSource = sources.get("AdminHome.vue")
const adminOpening = residualCadenceCardMigrations[0].opening
const adminAnchorOpening = `      <a
        id="admin-home-create-organization-link"
        :href="navigation.create_organization_href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="block"
      >`
const adminAnchorStart = adminSource.indexOf(adminAnchorOpening)
const adminBoundaryStart = adminSource.indexOf(adminOpening)
const adminBoundaryEnd = adminSource.indexOf("        </CadenceCard>", adminBoundaryStart)
const adminAnchorEnd = adminSource.indexOf("      </a>", adminBoundaryEnd)

assert.ok(
  adminAnchorStart < adminBoundaryStart &&
    adminBoundaryStart < adminBoundaryEnd &&
    adminBoundaryEnd < adminAnchorEnd,
  "AdminHome keeps the PHX redirect anchor physically outside the residual CadenceCard",
)
assert.match(
  adminSource.slice(adminBoundaryStart, adminBoundaryEnd),
  /presentation\.quick_actions\.create_organization_(?:title|description)/,
)

const catalogSource = sources.get("CatalogArtifactShow.vue")
const catalogOpening = residualCadenceCardMigrations[1].opening
const catalogBoundaryStart = catalogSource.indexOf(catalogOpening)
const catalogBoundaryEnd = catalogSource.indexOf("      </CadenceCard>", catalogBoundaryStart)
const catalogSlot = catalogSource.slice(catalogBoundaryStart, catalogBoundaryEnd)

for (const callerOwnedSource of [
  '<CadenceTableFrame id="catalog-artifact-runs-table">',
  '<tbody id="catalog-artifact-runs-table-body">',
  '<tr v-for="run in runs" :id="run.id" :key="run.id">',
  '<CadenceModalMenu side="bottom" align="end" :side-offset="4">',
  ':id="`${run.actions_id}-trigger`"',
  'data-phx-link="redirect"',
  'data-phx-link-state="push"',
]) {
  assert.ok(catalogSlot.includes(callerOwnedSource), `${callerOwnedSource} stays in the catalog slot`)
}

const commsSource = sources.get("CommsTransportNew.vue")
const commsOpening = residualCadenceCardMigrations[2].opening
const commsBoundaryStart = commsSource.indexOf(commsOpening)
const commsBoundaryEnd = commsSource.indexOf("        </CadenceCard>", commsBoundaryStart)
const commsSlot = commsSource.slice(commsBoundaryStart, commsBoundaryEnd)

for (const callerOwnedSource of [
  "{{ form.review.ownership.value }}",
  "{{ form.review.ownership.source }}",
  "statusClass(form.review.readiness.status)",
  "{{ form.review.readiness.value }}",
  "{{ form.review.readiness.endpoint }}",
]) {
  assert.ok(commsSlot.includes(callerOwnedSource), `${callerOwnedSource} stays in the comms slot`)
}

const resetHost = (selector) => {
  const host = dom.window.document.querySelector(selector)
  host.replaceChildren()
  return host
}

const mountAdmin = async (component, assertIdentity) => {
  const host = resetHost("#admin-host")
  const state = reactive({
    organization_count: 7,
    user_count: 3,
    presentation: {
      title: "Administration",
      subtitle: "Control plane",
      organizations: {title: "Organizations", action_label: "Manage organizations"},
      users: {title: "Users", action_label: "Manage users", coming_soon: "Coming soon"},
      runtime: {
        title: "Runtime",
        description: "Inspect runtime health",
        action_label: "Open runtime",
      },
      quick_actions: {
        title: "Quick actions",
        create_organization_title: "Create organization",
        create_organization_description: "Add a new organization",
      },
    },
    navigation: {
      organizations_href: "/admin/organizations",
      runtime_href: "/admin/runtime",
      create_organization_href: "/admin/organizations/new?from=home&mode=quick",
    },
  })
  const Harness = defineComponent({
    setup: () => () => h(component, state),
  })
  const app = createApp(Harness)
  app.mount(host)
  await flushVue(nextTick)

  const anchor = host.querySelector("#admin-home-create-organization-link")
  const section = anchor.firstElementChild
  const body = section.firstElementChild
  const content = body.firstElementChild
  const heading = section.querySelector("h3")
  const description = section.querySelector("p")

  assert.ok(anchor instanceof dom.window.HTMLAnchorElement)
  assert.equal(section.tagName, "SECTION")
  assert.equal(section.parentElement, anchor)
  assert.deepEqual(elementAttributes(anchor), {
    class: "block",
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    href: "/admin/organizations/new?from=home&mode=quick",
    id: "admin-home-create-organization-link",
  })
  assert.deepEqual(elementAttributes(section), {
    class:
      "card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]",
  })
  assert.deepEqual(elementAttributes(body), {class: "card-body p-6"})
  assert.equal(section.children.length, 1)
  assert.equal(body.children.length, 1)
  assert.equal(content.className, "flex items-center gap-4")

  const initial = section.outerHTML
  state.presentation = {
    ...state.presentation,
    quick_actions: {
      ...state.presentation.quick_actions,
      create_organization_title: "Create mission organization",
      create_organization_description: "Provision an organization for Mission Two",
    },
  }
  state.navigation = {
    ...state.navigation,
    create_organization_href: "/admin/organizations/new?from=updated&mode=full",
  }
  await flushVue(nextTick)

  if (assertIdentity) {
    assert.strictEqual(host.querySelector("#admin-home-create-organization-link"), anchor)
    assert.strictEqual(anchor.firstElementChild, section)
    assert.strictEqual(section.firstElementChild, body)
    assert.strictEqual(body.firstElementChild, content)
    assert.strictEqual(section.querySelector("h3"), heading)
    assert.strictEqual(section.querySelector("p"), description)
  }
  assert.equal(anchor.getAttribute("href"), "/admin/organizations/new?from=updated&mode=full")
  assert.equal(heading.textContent.trim(), "Create mission organization")
  assert.equal(description.textContent.trim(), "Provision an organization for Mission Two")

  const updated = section.outerHTML
  const owner = anchor.outerHTML
  app.unmount()
  return {initial, updated, owner}
}

const artifact = Object.freeze({
  format_key: "yaml",
  media_type: "text/yaml",
  content_sha256: "abc123",
  uploaded_at: "2026-08-29T12:00:00Z",
  download_href: "/missions/mission-1/catalog/artifacts/artifact-1/download",
})
const initialRun = Object.freeze({
  id: "artifact-run-1",
  actions_id: "artifact-run-1-actions",
  status: "ready",
  status_label: "Ready",
  started_at: "12:00",
  completed_at: "12:01",
  href: "/missions/mission-1/catalog/imports/run-1",
})
const updatedRun = Object.freeze({
  ...initialRun,
  status: "blocked",
  status_label: "Blocked",
  started_at: "12:02",
  completed_at: "12:03",
  href: "/missions/mission-1/catalog/imports/run-1?state=blocked",
})

const mountCatalog = async (component, assertIdentity) => {
  const host = resetHost("#catalog-host")
  const runs = ref([])
  const Harness = defineComponent({
    setup: () => () => h(component, {artifact, runs: runs.value}),
  })
  const app = createApp(Harness)
  app.mount(host)
  await flushVue(nextTick)

  assert.ok(host.querySelector("#catalog-artifact-runs-empty"))
  assert.equal(host.querySelector("#catalog-artifact-runs-card"), null)

  runs.value = [initialRun]
  await flushVue(nextTick)

  const section = host.querySelector("#catalog-artifact-runs-card")
  const body = section.firstElementChild
  const table = body.firstElementChild
  const tbody = table.querySelector("#catalog-artifact-runs-table-body")
  const row = tbody.firstElementChild
  const actionWrapper = row.querySelector("#artifact-run-1-actions")
  const trigger = actionWrapper.querySelector("#artifact-run-1-actions-trigger")

  assert.equal(host.querySelector("#catalog-artifact-runs-empty"), null)
  assert.equal(section.tagName, "SECTION")
  assert.deepEqual(elementAttributes(section), {
    class: "card border border-base-300 bg-base-200",
    id: "catalog-artifact-runs-card",
  })
  assert.deepEqual(elementAttributes(body), {class: "card-body p-0"})
  assert.equal(section.children.length, 1)
  assert.equal(body.children.length, 1)
  assert.equal(table.tagName, "TABLE")
  assert.equal(table.id, "catalog-artifact-runs-table")
  assert.equal(row.tagName, "TR")
  assert.equal(row.id, initialRun.id)
  assert.equal(row.hasAttribute("key"), false)
  assert.equal(actionWrapper.className, "cadence-overlay")
  assert.equal(trigger.tagName, "BUTTON")
  assert.equal(trigger.getAttribute("type"), "button")
  assert.equal(trigger.closest("tr"), row)

  const initial = section.outerHTML
  trigger.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true, cancelable: true, button: 0}))
  await flushVue(nextTick)

  const menu = dom.window.document.getElementById("artifact-run-1-actions-menu")
  const link = menu.querySelector("a")

  assert.equal(trigger.getAttribute("aria-controls"), menu.id)
  assert.equal(menu.getAttribute("aria-labelledby"), trigger.id)
  assert.equal(host.contains(menu), false)
  assert.equal(link.parentElement, menu)
  assert.deepEqual(elementAttributes(link), {
    class:
      "block cursor-pointer rounded px-3 py-2 text-sm outline-none hover:bg-base-200",
    "data-phx-link": "redirect",
    "data-phx-link-state": "push",
    "data-reka-collection-item": "",
    href: initialRun.href,
    role: "menuitem",
    tabindex: "-1",
  })

  runs.value = [updatedRun]
  await flushVue(nextTick)

  if (assertIdentity) {
    assert.strictEqual(host.querySelector("#catalog-artifact-runs-card"), section)
    assert.strictEqual(section.firstElementChild, body)
    assert.strictEqual(body.firstElementChild, table)
    assert.strictEqual(table.querySelector("#catalog-artifact-runs-table-body"), tbody)
    assert.strictEqual(tbody.firstElementChild, row)
    assert.strictEqual(row.querySelector("#artifact-run-1-actions"), actionWrapper)
    assert.strictEqual(actionWrapper.querySelector("button"), trigger)
    assert.strictEqual(menu.querySelector("a"), link)
  }
  assert.equal(row.children[1].textContent.trim(), "12:02")
  assert.equal(row.children[2].textContent.trim(), "12:03")
  assert.equal(row.textContent.includes("Blocked"), true)
  assert.equal(link.getAttribute("href"), updatedRun.href)

  const updated = section.outerHTML
  const action = menu.outerHTML
  app.unmount()
  await flushVue(nextTick)
  return {initial, updated, action}
}

const transportPage = Object.freeze({
  id: "comms-transport-new-page",
  title: "New Transport",
  subtitle: "Describe a durable byte-moving capability.",
  breadcrumbs: Object.freeze([
    Object.freeze({label: "Mission One", href: "/missions/mission-1"}),
    Object.freeze({label: "New Transport", href: null}),
  ]),
})
const option = (label, value) => ({label, value, disabled: false})
const field = (key, id, type, label, value, options = []) => ({
  key,
  id,
  name: `transport[${key}]`,
  type,
  label,
  required: true,
  placeholder: null,
  options,
  value,
  provider_managed_id: null,
})
const transportForm = (review) => ({
  id: "transport-form",
  selected_origin: "direct",
  can_submit: true,
  sections: {
    identity: {id: "transport-identity-section", number: "01", title: "Identity"},
    origin: {id: "transport-origin-section", number: "02", title: "Origin"},
    source: {id: "transport-source-section", number: "03", title: "Source"},
    provider_capability: {id: "transport-capability-section", number: "04", title: "Capability"},
    review: {id: "transport-summary-section", number: "06", title: "Review"},
  },
  fields: {
    display_name: field("display_name", "transport-display-name", "text", "Display Name", "Relay TCP"),
    origin: field("origin", "transport-origin", "select", "Configuration Owner", "direct", [
      option("Direct", "direct"),
      option("Provider", "provider_managed"),
    ]),
    transport_kind: field(
      "transport_kind",
      "transport-kind",
      "select",
      "Transport Kind",
      "tcp_socket",
      [option("TCP socket", "tcp_socket")],
    ),
  },
  origin_cards: [{value: "direct", label: "Direct", description: "Cadence owns the endpoint."}],
  direct_configuration: {
    id: "transport-direct-configuration",
    kind: "transport_kind",
    description: "Cadence owns this endpoint.",
    active: true,
    sections: [],
  },
  provider: {
    active: false,
    profile_fields_id: "transport-provider-profile-fields",
    ready_count: 0,
    selected: null,
    empty_state: {
      id: "transport-provider-empty-state",
      visible: false,
      message: "No providers",
      action: {label: "Review providers", href: "/missions/mission-1/comms/providers"},
    },
    operator_summary: null,
    derivation_error: null,
  },
  provider_derived: {
    active: false,
    id: "transport-provider-derived-section",
    number: "05",
    title: "Provider runtime",
    description: "Provider-owned runtime.",
    configuration: {
      id: "transport-provider-derived-configuration",
      rows: [],
      empty_text: "No provider runtime",
    },
  },
  review,
  actions: {
    submit: {id: "create-transport-button", label: "Create Transport"},
    cancel: {
      id: "cancel-transport-link",
      label: "Cancel",
      href: "/missions/mission-1/comms/transports",
    },
  },
})
const initialReview = Object.freeze({
  configuration_summary_id: "transport-configuration-summary",
  ownership: {label: "Ownership", value: "Direct", source: "Cadence"},
  readiness: {
    label: "Readiness",
    status: "ready",
    value: "Ready to save",
    endpoint: "0.0.0.0:5001",
  },
  error: null,
  error_id: "transport-form-error",
  diagnostics: {
    id: "transport-admin-diagnostics",
    label: "Administrator Diagnostics",
    json_id: "transport-admin-diagnostics-json",
    json: "{}",
  },
})
const updatedReview = Object.freeze({
  ...initialReview,
  configuration_summary_id: "transport-configuration-summary-updated",
  ownership: {label: "Ownership", value: "Provider managed", source: "Mission provider"},
  readiness: {
    label: "Readiness",
    status: "attention",
    value: "Needs review",
    endpoint: "provider.example:5100",
  },
})

const mountComms = async (component, assertIdentity) => {
  const host = resetHost("#comms-host")
  const state = reactive({page: transportPage, form: transportForm(initialReview)})
  const Harness = defineComponent({
    setup: () => () => h(component, state),
  })
  const app = createApp(Harness)
  app.mount(host)
  await flushVue(nextTick)

  const section = host.querySelector("#transport-configuration-summary")
  const body = section.firstElementChild
  const grid = body.firstElementChild
  const ownershipValue = grid.children[0].children[1]
  const status = grid.children[1].querySelector("span")
  const endpoint = grid.children[1].lastElementChild

  assert.equal(section.tagName, "SECTION")
  assert.deepEqual(elementAttributes(section), {
    class: "card bg-base-200 border border-base-300",
    id: "transport-configuration-summary",
  })
  assert.deepEqual(elementAttributes(body), {class: "card-body p-0"})
  assert.equal(section.children.length, 1)
  assert.equal(body.children.length, 1)
  assert.equal(
    status.className,
    "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-success/20 text-success",
  )

  const initial = section.outerHTML
  state.form = transportForm(updatedReview)
  await flushVue(nextTick)

  if (assertIdentity) {
    assert.strictEqual(host.querySelector("#transport-configuration-summary-updated"), section)
    assert.strictEqual(section.firstElementChild, body)
    assert.strictEqual(body.firstElementChild, grid)
    assert.strictEqual(grid.children[0].children[1], ownershipValue)
    assert.strictEqual(grid.children[1].querySelector("span"), status)
    assert.strictEqual(grid.children[1].lastElementChild, endpoint)
  }
  assert.equal(section.id, "transport-configuration-summary-updated")
  assert.equal(ownershipValue.textContent.trim(), "Provider managed")
  assert.equal(grid.children[0].lastElementChild.textContent.trim(), "Mission provider")
  assert.equal(status.textContent.trim(), "Needs review")
  assert.equal(
    status.className,
    "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-warning/20 text-warning",
  )
  assert.equal(endpoint.textContent.trim(), "provider.example:5100")

  const updated = section.outerHTML
  app.unmount()
  return {initial, updated}
}

const adminPredecessor = await mountAdmin(components.get("AdminHome.vue").predecessor, false)
const adminCurrent = await mountAdmin(components.get("AdminHome.vue").current, true)
assert.deepEqual(adminCurrent, adminPredecessor)

const catalogPredecessor = await mountCatalog(
  components.get("CatalogArtifactShow.vue").predecessor,
  false,
)
const catalogCurrent = await mountCatalog(components.get("CatalogArtifactShow.vue").current, true)
assert.deepEqual(catalogCurrent, catalogPredecessor)

const commsPredecessor = await mountComms(
  components.get("CommsTransportNew.vue").predecessor,
  false,
)
const commsCurrent = await mountComms(components.get("CommsTransportNew.vue").current, true)
assert.deepEqual(commsCurrent, commsPredecessor)

dom.window.close()

console.log(
  "residual_cadence_cards_migration_test passed (3 real current/predecessor SFC pairs + 3 exact inverse peels)",
)

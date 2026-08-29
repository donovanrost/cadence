#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelContactSummaryBand} from "./contact_summary_band_test_support.mjs"
import {
  inlineWarningCallerLedger,
  peelCadenceInlineWarnings,
} from "./inline_warning_test_support.mjs"
import {
  opsViewportCallerNames,
  peelCadenceOpsViewport,
} from "./ops_viewport_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceInlineWarning contracts use pinned Node ${expectedNodeVersion}`,
)

const baseClass = "border-l-2 border-warning px-3 text-xs text-warning"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const componentPath = resolve(vueDirectory, "ui/components/CadenceInlineWarning.vue")
const callerPaths = Object.keys(inlineWarningCallerLedger).map((filename) => ({
  filename,
  path: resolve(vueDirectory, filename),
}))

assert.equal(callerPaths.length, 3, "the frozen caller ledger contains exactly three callers")
assert.deepEqual(
  callerPaths.map(({filename}) => inlineWarningCallerLedger[filename].boundaries.length),
  [1, 1, 1],
  "the frozen caller ledger contains explicit 1/1/1 boundary mappings",
)

const componentSource = await readFile(componentPath, "utf8")
assert.match(componentSource, /name: "CadenceInlineWarning"/)
assert.match(componentSource, /inheritAttrs: false/)
assert.equal(componentSource.match(/h\(\s*"p"/g)?.length, 1, "the primitive owns one P root")
assert.equal(
  componentSource.match(new RegExp(baseClass, "g"))?.length,
  1,
  "the primitive owns the exact base class once",
)
assert.match(componentSource, /class: \[attrs\.class, inlineWarningClass\]/)
assert.doesNotMatch(componentSource, /defineProps|\bprops\s*:|defineEmits|\bemits\s*:/)
assert.doesNotMatch(componentSource, /\b(?:tone|role|aria-live|aria-atomic)\b/)

for (const caller of callerPaths) {
  const source = await readFile(caller.path, "utf8")
  const contactSummaryCompatibleSource = peelContactSummaryBand(source, caller.filename)
  const opsViewportCompatibleSource = opsViewportCallerNames.includes(caller.filename)
    ? peelCadenceOpsViewport(contactSummaryCompatibleSource, caller.filename)
    : contactSummaryCompatibleSource
  peelCadenceInlineWarnings(opsViewportCompatibleSource, caller.filename)
  assert.equal(source.split("<CadenceInlineWarning\n").length - 1, 1)
  assert.equal(source.split("</CadenceInlineWarning>").length - 1, 1)
  assert.equal(source.includes(`class="${baseClass}"`), false)

  if (caller.filename === "OpsContactPlanShow.vue") {
    assert.equal(
      source.split(
        '</template>\n          <CadenceInlineWarning\n            v-else-if="page.decision.admin_required !== null"',
      ).length - 1,
      1,
      "the contact-plan v-if/v-else-if branches remain directly adjacent",
    )
  }
}

const dom = installDom(
  [
    '<div id="inline-warning-contract"></div>',
    '<div id="requirement-warning-contract"></div>',
    '<div id="fleet-warning-contract"></div>',
    '<div id="contact-plan-warning-contract"></div>',
  ].join(""),
)
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLParagraphElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsedPrimitive = parse(componentSource, {filename: componentPath})
assert.deepEqual(parsedPrimitive.errors, [])
assert.ok(parsedPrimitive.descriptor.script)
assert.equal(parsedPrimitive.descriptor.scriptSetup, null)
assert.equal(parsedPrimitive.descriptor.template, null)

const compiledPrimitive = compileScript(parsedPrimitive.descriptor, {
  id: "cadence-inline-warning-contract",
})
const transformedPrimitive = transformSync(compiledPrimitive.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedPrimitive = {exports: {}}
const evaluatePrimitive = new Function(
  "require",
  "module",
  "exports",
  transformedPrimitive.code,
)
evaluatePrimitive(integrationRequire, loadedPrimitive, loadedPrimitive.exports)
const CadenceInlineWarning = loadedPrimitive.exports.default
assert.equal(CadenceInlineWarning.inheritAttrs, false)
assert.equal(Object.hasOwn(CadenceInlineWarning, "props"), false, "the primitive exposes zero props")
assert.equal(Object.hasOwn(CadenceInlineWarning, "emits"), false, "the primitive exposes zero emits")

const {Fragment, createApp, defineComponent, h, nextTick, reactive, ref} =
  integrationRequire("vue")
const primitiveState = reactive({proof: "caller-owned", text: "alpha"})
let clickCount = 0
const PrimitiveOracle = defineComponent({
  setup() {
    return () =>
      h(
        CadenceInlineWarning,
        {
          id: "inline-warning-proof",
          class: "caller-class",
          "data-proof": primitiveState.proof,
          onClick: () => {
            clickCount += 1
          },
        },
        {
          default: () => [
            primitiveState.text,
            [
              h(Fragment, null, [
                h("span", {id: "inline-warning-fragment-span"}, "beta"),
                [
                  h(Fragment, null, [
                    "gamma",
                    h("a", {id: "inline-warning-fragment-link"}, "delta"),
                  ]),
                ],
              ]),
            ],
          ],
        },
      )
  },
})

const primitiveHost = dom.window.document.querySelector("#inline-warning-contract")
const primitiveApp = createApp(PrimitiveOracle)
primitiveApp.mount(primitiveHost)

const primitiveWarning = primitiveHost.firstElementChild
assert.ok(primitiveWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(primitiveHost.children.length, 1, "the primitive adds no wrapper")
assert.equal(primitiveWarning.tagName, "P")
assert.deepEqual(elementAttributes(primitiveWarning), {
  class: `caller-class ${baseClass}`,
  "data-proof": "caller-owned",
  id: "inline-warning-proof",
})
assert.equal(primitiveWarning.hasAttribute("role"), false)
assert.equal(primitiveWarning.hasAttribute("aria-live"), false)
assert.equal(primitiveWarning.attributes.length, 3, "the primitive adds no semantic attributes")
assert.deepEqual(
  [...primitiveWarning.childNodes].map((node) => node.nodeName),
  ["#text", "SPAN", "#text", "A"],
)
assert.deepEqual(
  [...primitiveWarning.childNodes].map((node) => node.textContent),
  ["alpha", "beta", "gamma", "delta"],
)
assert.strictEqual(
  primitiveWarning.children[0],
  primitiveHost.querySelector("#inline-warning-fragment-span"),
)
assert.strictEqual(
  primitiveWarning.children[1],
  primitiveHost.querySelector("#inline-warning-fragment-link"),
)

primitiveWarning.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(clickCount, 1, "the caller listener reaches the native P")

const primitiveChildNodes = [...primitiveWarning.childNodes]
primitiveState.proof = "reconciled"
primitiveState.text = "omega"
await nextTick()
assert.strictEqual(primitiveHost.firstElementChild, primitiveWarning)
for (const [index, childNode] of primitiveChildNodes.entries()) {
  assert.strictEqual(primitiveWarning.childNodes[index], childNode)
}
assert.equal(primitiveWarning.getAttribute("data-proof"), "reconciled")
assert.deepEqual(
  [...primitiveWarning.childNodes].map((node) => node.textContent),
  ["omega", "beta", "gamma", "delta"],
)

const loadedCallers = Object.fromEntries(
  await Promise.all(
    callerPaths.map(async ({filename, path}) => [filename, (await loadSfc(path)).component]),
  ),
)

const requirementAuthorization = reactive({organization_admin: true, admin_required: null})
const requirementProps = {
  page: {
    id: "contact-template-page",
    back: {href: "/ops/requirements", icon: "hero-arrow-left", label: "Back"},
    header: {eyebrow: "Ops", title: "Templates", copy: "Template copy"},
  },
  ledger: {
    eyebrow: "Templates",
    copy: "Ledger copy",
    count: 0,
    count_label: "0 templates",
    list_id: "contact-template-list",
    stream_empty_id: "contact-template-empty",
    empty: null,
  },
  template_form: null,
  templates: [],
}
const RequirementOracle = defineComponent({
  setup() {
    return () =>
      h(loadedCallers["OpsContactRequirementTemplate.vue"], {
        ...requirementProps,
        authorization: requirementAuthorization,
      })
  },
})
const requirementHost = dom.window.document.querySelector("#requirement-warning-contract")
const requirementApp = createApp(RequirementOracle)
requirementApp.mount(requirementHost)
assert.equal(requirementHost.querySelector("#requirement-template-admin-required"), null)

requirementAuthorization.organization_admin = false
requirementAuthorization.admin_required = {
  id: "requirement-template-admin-required",
  copy: "Organization administrator authority is required to manage recurring demand.",
}
await nextTick()
const requirementWarning = requirementHost.querySelector("#requirement-template-admin-required")
assert.ok(requirementWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(requirementWarning.className, baseClass)
assert.equal(requirementWarning.textContent, requirementAuthorization.admin_required.copy)
assert.equal(requirementWarning.children.length, 0)

requirementAuthorization.admin_required = null
await nextTick()
assert.equal(requirementHost.querySelector("#requirement-template-admin-required"), null)

const fleetAuthorization = reactive({organization_admin: true, admin_required: null})
const fleetProps = {
  page: {
    back: {href: "/ops/planning", icon: "hero-arrow-left", label: "Back"},
    header: {eyebrow: "Policy", title: "Fleet policy", copy: "Policy copy"},
    state: {id: "fleet-policy-state", label: "Draft", class: "badge"},
    manifest: {
      id: "fleet-policy-manifest",
      version_label: "not configured",
      content_sha256: null,
      sections: [],
      empty: null,
    },
  },
  policy_form: null,
  approval_form: null,
  grant_ledger: {
    id: "fleet-policy-grant-ledger",
    list_id: "fleet-policy-grant-list",
    empty: {id: "fleet-policy-grant-empty", copy: "No grants"},
    active_count: 0,
    active_label: "0 active",
  },
  grant_form: null,
  revocation_form: null,
  automation_grants: [],
}
const FleetOracle = defineComponent({
  setup() {
    return () =>
      h(loadedCallers["OpsFleetPlanningPolicy.vue"], {
        ...fleetProps,
        authorization: fleetAuthorization,
      })
  },
})
const fleetHost = dom.window.document.querySelector("#fleet-warning-contract")
const fleetApp = createApp(FleetOracle)
fleetApp.mount(fleetHost)
assert.equal(fleetHost.querySelector(`p[class="${baseClass}"]`), null)

fleetAuthorization.organization_admin = false
fleetAuthorization.admin_required = {
  copy: "Organization administrator authority is required to change policy or grants.",
}
await nextTick()
const fleetWarning = fleetHost.querySelector(`p[class="${baseClass}"]`)
assert.ok(fleetWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(fleetWarning.hasAttribute("id"), false, "the fleet warning deliberately remains ID-less")
assert.equal(fleetWarning.attributes.length, 1)
assert.equal(fleetWarning.textContent, fleetAuthorization.admin_required.copy)

fleetAuthorization.admin_required = null
await nextTick()
assert.equal(fleetHost.querySelector(`p[class="${baseClass}"]`), null)

const contactPlanPage = reactive({
  id: "contact-plan-page",
  back_action: {label: "Back", href: "/ops/requirements"},
  header: {
    state: {label: "Pending approval", class: "badge"},
    version_label: "v1",
    heading: "Contact plan",
    description: "Plan description",
    execute_action: null,
  },
  summary: {
    id: "contact-plan-summary",
    coverage: {label: "Satisfied", class: "badge"},
    selected_count: 0,
    approval_identity: "Not approved",
    content_hash: {id: "contact-plan-hash", value: "hash"},
  },
  selections: {
    id: "contact-plan-selections",
    empty: {id: "contact-plan-selections-empty", message: "No selections"},
  },
  unsatisfied: null,
  policy: {id: "contact-plan-policy", summary: "Policy", selections: []},
  execution: {
    id: "contact-plan-execution",
    heading: "Execution",
    description: "Execution description",
    empty: {id: "contact-plan-execution-empty", message: "No execution"},
  },
  submission: null,
  decision: {
    heading: "Administrator decision",
    description: "Approval description",
    admin_required: {
      id: "contact-plan-admin-required",
      message: "Organization administrator approval required.",
    },
  },
  approval_evidence: {
    id: "contact-plan-approval-evidence",
    heading: "Approval evidence",
    empty: {id: "contact-plan-approval-empty", message: "No approval"},
  },
  rationale: {heading: "Rationale", value: "Plan rationale", plan_id: "plan-1"},
})
const contactPlanAdminControls = ref(null)
const contactPlanProps = {
  submission_form: null,
  selected_opportunities: [],
  execution_items: [],
  approvals: [],
}
const reasonForm = (namespace) => ({
  id: `${namespace}-form`,
  field: {
    id: `${namespace}-reason`,
    name: `${namespace}[reason]`,
    type: "textarea",
    label: "Reason",
    required: true,
    value: "",
  },
  action: {id: `${namespace}-submit`, label: "Submit"},
})
const adminControls = {
  approve_form: reasonForm("contact-plan-approve"),
  rejection: {
    id: "contact-plan-rejection",
    summary: "Reject plan",
    form: reasonForm("contact-plan-reject"),
  },
}
const ContactPlanOracle = defineComponent({
  setup() {
    return () =>
      h(loadedCallers["OpsContactPlanShow.vue"], {
        ...contactPlanProps,
        page: contactPlanPage,
        admin_controls: contactPlanAdminControls.value,
      })
  },
})
const contactPlanHost = dom.window.document.querySelector("#contact-plan-warning-contract")
const contactPlanApp = createApp(ContactPlanOracle)
contactPlanApp.mount(contactPlanHost)
await nextTick()

let contactPlanWarning = contactPlanHost.querySelector("#contact-plan-admin-required")
assert.ok(contactPlanWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(contactPlanWarning.className, `mt-4 ${baseClass}`)
assert.equal(contactPlanWarning.textContent, contactPlanPage.decision.admin_required.message)
assert.equal(contactPlanHost.querySelector("#contact-plan-approve-form"), null)

contactPlanAdminControls.value = adminControls
await nextTick()
assert.equal(contactPlanHost.querySelector("#contact-plan-admin-required"), null)
assert.ok(contactPlanHost.querySelector("#contact-plan-approve-form"))
assert.ok(contactPlanHost.querySelector("#contact-plan-reject-form"))

contactPlanAdminControls.value = null
contactPlanPage.decision.admin_required = null
await nextTick()
assert.equal(contactPlanHost.querySelector("#contact-plan-admin-required"), null)
assert.equal(contactPlanHost.querySelector("#contact-plan-approve-form"), null)

contactPlanPage.decision.admin_required = {
  id: "contact-plan-admin-required",
  message: "Organization administrator approval required.",
}
await nextTick()
contactPlanWarning = contactPlanHost.querySelector("#contact-plan-admin-required")
assert.ok(contactPlanWarning instanceof dom.window.HTMLParagraphElement)
assert.equal(contactPlanWarning.className, `mt-4 ${baseClass}`)

contactPlanApp.unmount()
fleetApp.unmount()
requirementApp.unmount()
primitiveApp.unmount()
assert.equal(dom.window.document.querySelectorAll(`p[class*="${baseClass}"]`).length, 0)
dom.window.close()

console.log("inline_warning_migration_test passed (3 exact callers, 1/1/1 frozen boundaries)")

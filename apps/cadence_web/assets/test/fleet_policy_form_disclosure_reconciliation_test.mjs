import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {peelConditionalKeyedCadenceFields} from "./conditional_keyed_field_test_support.mjs"
import {peelCadenceInlineWarnings} from "./inline_warning_test_support.mjs"

const scenarios = Object.freeze([
  "the actual fleet policy SFC mounts through the real Cadence collapsible adapter graph",
  "native button clicks toggle client-owned disclosure state immediately",
  "same-epoch whole-policy-form replacement retains local disclosure state",
  "a changed server-open epoch intentionally reseeds local disclosure state",
  "keep-mounted form and edited input preserve exact DOM identity and value",
  "caller-owned IDs, names, action absence, hidden fields, and nested details remain exact",
  "the existing validate and submit events retain their exact normalized payloads",
  "the frozen native details opening and complete predecessor source reconstruct byte-for-byte",
])
const separateGates = Object.freeze([
  "BROWSER GATE: keyboard, focus, layout, and hydration require real-browser verification",
  "LIVEVUE GATE: transport reconciliation and Phoenix acknowledgement require integration verification",
  "CSRF GATE: native transport submission and CSRF behavior require Phoenix integration verification",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `fleet policy disclosure contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 8)
assert.equal(separateGates.length, 3)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const componentRelativePath = "apps/cadence_web/assets/vue/OpsFleetPlanningPolicy.vue"
const componentPath = resolve(repositoryRoot, componentRelativePath)
const liveViewPath = resolve(
  repositoryRoot,
  "apps/cadence_web/lib/cadence_web/live/ops_fleet_planning_policy_live.ex",
)
const adapterPaths = {
  root: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsible.vue"),
  trigger: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleTrigger.vue"),
  content: resolve(testDirectory, "../vue/ui/reka/CadenceCollapsibleContent.vue"),
}
const baseHead = "666f58ed058b033630bb2aeb4f572df5b23ae58c"
const baseSha256 = "58fde897de9c355b6c4da0c1ec743730f7983f43a2b085392d6e2f6922ae5bf5"
const cadenceCollapsibleImports = Object.freeze([
  'import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"\n',
  'import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"\n',
  'import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"\n',
])
const frozenPolicyDetailsOpening = '<details :open="policy_form.open">'
const policyCollapsibleOpening = `        <CadenceCollapsible
          :content-id="policy_form.id"
          :open="policy_form.open"
          client-seeded
          :seed-epoch="\`\${policy_form.id}:\${policy_form.open}\`"
          :unmount-on-hide="false"
        >
          <div>
            <CadenceCollapsibleTrigger>
              <button type="button" class="cursor-pointer px-4 py-3 text-sm font-semibold">
                {{ policy_form.summary }}
              </button>
            </CadenceCollapsibleTrigger>
            <CadenceCollapsibleContent>`
const policyNativeOpening = `        ${frozenPolicyDetailsOpening}
          <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
            {{ policy_form.summary }}
          </summary>`
const policyCollapsibleClosing = `            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`
const occurrences = (source, value) => source.split(value).length - 1
const sha256 = (source) => createHash("sha256").update(source).digest("hex")

assert.equal(
  sha256(frozenPolicyDetailsOpening),
  "1c3488bb5db768112ced67f1d1fd2a24716270c13e7ecaf78d4a1afd4f102310",
  "the retired policy details opening remains frozen byte-for-byte",
)

const reconstructPredecessor = (source) => {
  source = peelConditionalKeyedCadenceFields(source, "OpsFleetPlanningPolicy.vue")
  source = peelCadenceInlineWarnings(source, "OpsFleetPlanningPolicy.vue")

  for (const importLine of cadenceCollapsibleImports) {
    assert.equal(occurrences(source, importLine), 1, "each Cadence collapsible import is exact")
  }
  assert.equal(occurrences(source, policyCollapsibleOpening), 1, "the migration opening is exact")
  assert.equal(occurrences(source, policyCollapsibleClosing), 1, "the migration closing is exact")

  let reconstructed = source
  for (const importLine of cadenceCollapsibleImports) {
    reconstructed = reconstructed.replace(importLine, "")
  }
  reconstructed = reconstructed
    .replace(policyCollapsibleOpening, policyNativeOpening)
    .replace(policyCollapsibleClosing, "        </details>")

  assert.doesNotMatch(reconstructed, /CadenceCollapsible(?:Content|Trigger)?/)
  assert.equal(occurrences(reconstructed, `        ${frozenPolicyDetailsOpening}`), 1)
  return reconstructed
}

await assertPinnedAdapterRuntime(packageLockPath)

const dom = installDom('<div id="fleet-policy-disclosure-contract"></div>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLAnchorElement",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLTextAreaElement",
  "HTMLOptionElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const [policySfc, rootSfc, triggerSfc, contentSfc, liveViewSource] = await Promise.all([
  loadSfc(componentPath),
  loadSfc(adapterPaths.root),
  loadSfc(adapterPaths.trigger),
  loadSfc(adapterPaths.content),
  readFile(liveViewPath, "utf8"),
])
const baseSource = execFileSync("git", ["show", `${baseHead}:${componentRelativePath}`], {
  cwd: repositoryRoot,
  encoding: "utf8",
})

assert.equal(sha256(baseSource), baseSha256, "the attested base source SHA-256 is exact")
assert.equal(
  reconstructPredecessor(policySfc.source),
  baseSource,
  "the newest disclosure peel reconstructs the attested base source byte-for-byte",
)
assert.doesNotMatch(policySfc.source, /<details\b/, "the one residual raw details root is retired")
assert.equal(occurrences(policySfc.source, "<CadenceDetailsFrame"), 3)
assert.equal(occurrences(policySfc.source, "</CadenceDetailsFrame>"), 3)
assert.doesNotMatch(policySfc.source, /from "reka-ui"/, "the caller has no direct Reka import")
assert.match(rootSfc.source, /^import \{CollapsibleRoot\} from "reka-ui"$/m)
assert.match(rootSfc.source, /CadencePrimitiveChild/)
assert.match(triggerSfc.source, /^import \{CollapsibleTrigger\} from "reka-ui"$/m)
assert.match(triggerSfc.source, /CadencePrimitiveChild/)
assert.match(contentSfc.source, /^import \{CollapsibleContent\} from "reka-ui"$/m)
assert.match(contentSfc.source, /CadencePrimitiveChild/)

const liveVueHostStart = liveViewSource.indexOf(
  '          <.vue\n            id="ops-fleet-planning-policy-component"',
)
const liveVueHostEnd = liveViewSource.indexOf("\n          />", liveVueHostStart)
assert.ok(liveVueHostStart >= 0 && liveVueHostEnd > liveVueHostStart)
const liveVueHost = liveViewSource.slice(liveVueHostStart, liveVueHostEnd)
assert.doesNotMatch(policySfc.source, /phx-hook|phxHook/)
assert.doesNotMatch(liveVueHost, /phx-hook|phxHook/)

const formField = (
  key,
  id,
  {type = "number", value = "1", required = true, min = 0, options = []} = {},
) => ({
  id,
  name: `policy[${key}]`,
  type,
  label: key,
  required,
  min,
  options,
  value,
  errors: [],
})

const checkboxField = (key, id, value) => ({
  id,
  name: `policy[${key}]`,
  type: "checkbox",
  label: key,
  value,
  errors: [],
})

const policyForm = ({
  open = true,
  summary = "Create the initial policy",
  maxContacts = "12",
} = {}) => ({
  panel_id: "fleet-policy-editor",
  id: "fleet-policy-form",
  open,
  summary,
  fields: {
    max_horizon_hours: formField("max_horizon_hours", "policy-max-horizon-hours", {
      value: "24",
      min: 1,
    }),
    requirement_concurrency: formField(
      "requirement_concurrency",
      "policy-requirement-concurrency",
      {value: "3", min: 1},
    ),
    provider_search_concurrency: formField(
      "provider_search_concurrency",
      "policy-provider-concurrency",
      {value: "4", min: 1},
    ),
    reuse_freshness_seconds: formField("reuse_freshness_seconds", "policy-reuse-seconds", {
      value: "300",
    }),
    max_contacts: formField("max_contacts", "policy-max-contacts", {
      value: maxContacts,
      min: 1,
    }),
    max_estimated_cost_micros: formField("max_estimated_cost_micros", "policy-max-cost", {
      value: "500000",
      required: false,
    }),
    currency: formField("currency", "policy-currency", {
      type: "text",
      value: "USD",
      required: false,
      min: null,
    }),
    critical_contact_reserve: formField(
      "critical_contact_reserve",
      "policy-critical-reserve",
      {value: "2"},
    ),
    automation_mode: formField("automation_mode", "policy-automation-mode", {
      type: "select",
      value: "bounded_automatic",
      required: false,
      min: null,
      options: [
        {label: "Advisory", value: "advisory"},
        {label: "Approval required", value: "approval_required"},
        {label: "Bounded automatic", value: "bounded_automatic"},
      ],
    }),
    execution_concurrency: formField("execution_concurrency", "policy-execution-concurrency", {
      value: "2",
      min: 1,
    }),
    max_repair_attempts: formField("max_repair_attempts", "policy-repair-attempts", {
      value: "1",
    }),
    repair_horizon_hours: formField("repair_horizon_hours", "policy-repair-horizon-hours", {
      value: "6",
      min: 1,
    }),
    automatic_submission: checkboxField(
      "automatic_submission",
      "policy-automatic-submission",
      true,
    ),
    distinct_provider_required: checkboxField(
      "distinct_provider_required",
      "policy-distinct-provider",
      true,
    ),
    distinct_station_required: checkboxField(
      "distinct_station_required",
      "policy-distinct-station",
      false,
    ),
    distinct_service_pool_required: checkboxField(
      "distinct_service_pool_required",
      "policy-distinct-pool",
      true,
    ),
  },
  redundancy: {id: "fleet-policy-redundancy-details", summary: "Redundancy constraints"},
  submit: {id: "save-fleet-policy", label: "Create draft policy"},
})

const staticProps = {
  page: {
    back: {href: "/missions/mission-canary/ops/planning", icon: "hero-arrow-left", label: "Back"},
    header: {
      eyebrow: "Administrative boundary",
      title: "Fleet Policy & Automation",
      copy: "Server-owned policy copy",
    },
    state: {id: "fleet-policy-state", label: "Draft", class: "badge"},
    manifest: {
      id: "fleet-policy-manifest",
      version_label: "not configured",
      content_sha256: null,
      sections: [],
      empty: null,
    },
  },
  approval_form: null,
  authorization: {organization_admin: true, admin_required: null},
  grant_ledger: {
    id: "fleet-policy-grant-ledger",
    list_id: "fleet-policy-grant-list",
    empty: {id: "fleet-policy-grant-empty", copy: "No automation grants."},
    active_count: 0,
    active_label: "0 active",
  },
  grant_form: null,
  revocation_form: null,
  automation_grants: [],
}

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const currentPolicyForm = ref(policyForm())
const validations = []
const saves = []
const FleetPolicyOracle = defineComponent({
  name: "FleetPolicyFormDisclosureOracle",
  setup() {
    return () =>
      h(policySfc.component, {
        ...staticProps,
        policy_form: currentPolicyForm.value,
        onValidatePolicy: (payload) => validations.push(payload),
        onSavePolicy: (payload) => saves.push(payload),
      })
  },
})

const app = createApp(FleetPolicyOracle)
app.mount(dom.window.document.querySelector("#fleet-policy-disclosure-contract"))
await flushVue(nextTick)

const document = dom.window.document
const section = document.querySelector("#fleet-policy-editor")
const disclosureRoot = section?.firstElementChild
const trigger = disclosureRoot?.children[0]
const form = disclosureRoot?.children[1]
const maxContacts = document.querySelector("#policy-max-contacts")
const submit = document.querySelector("#save-fleet-policy")

assert.ok(section instanceof dom.window.HTMLElement)
assert.equal(section.className, "border border-base-300 bg-base-200/15")
assert.ok(disclosureRoot instanceof dom.window.HTMLDivElement)
assert.equal(disclosureRoot.id, "")
assert.equal(disclosureRoot.getAttribute("class"), null)
assert.ok(trigger instanceof dom.window.HTMLButtonElement)
assert.equal(trigger.id, "")
assert.equal(trigger.type, "button")
assert.equal(trigger.className, "cursor-pointer px-4 py-3 text-sm font-semibold")
assert.ok(form instanceof dom.window.HTMLFormElement)
assert.equal(form.id, "fleet-policy-form")
assert.equal(form.getAttribute("class"), "space-y-5 border-t border-base-300 p-4")
assert.equal(form.getAttribute("action"), null)
assert.equal(form.getAttribute("method"), null)
assert.ok(maxContacts instanceof dom.window.HTMLInputElement)
assert.ok(submit instanceof dom.window.HTMLButtonElement)

const expectedIds = [
  "fleet-policy-form",
  "policy-max-horizon-hours",
  "policy-requirement-concurrency",
  "policy-provider-concurrency",
  "policy-reuse-seconds",
  "policy-max-contacts",
  "policy-max-cost",
  "policy-currency",
  "policy-critical-reserve",
  "policy-automation-mode",
  "policy-execution-concurrency",
  "policy-repair-attempts",
  "policy-repair-horizon-hours",
  "policy-automatic-submission",
  "fleet-policy-redundancy-details",
  "policy-distinct-provider",
  "policy-distinct-station",
  "policy-distinct-pool",
  "save-fleet-policy",
]
assert.deepEqual(
  [...section.querySelectorAll("[id]")].map((element) => element.id),
  expectedIds,
  "the form subtree keeps exactly the existing caller-owned ID sequence",
)
assert.equal(section.querySelectorAll("details").length, 1, "the nested redundancy details stays exact")
assert.equal(
  section.querySelector("details")?.id,
  "fleet-policy-redundancy-details",
  "the nested already-migrated CadenceDetailsFrame is untouched",
)

const expectedFieldIds = expectedIds.filter(
  (id) => id.startsWith("policy-") && id !== "policy-automatic-submission",
)
for (const id of expectedFieldIds) {
  const control = document.getElementById(id)
  const keyById = {
    "policy-max-horizon-hours": "max_horizon_hours",
    "policy-requirement-concurrency": "requirement_concurrency",
    "policy-provider-concurrency": "provider_search_concurrency",
    "policy-reuse-seconds": "reuse_freshness_seconds",
    "policy-max-contacts": "max_contacts",
    "policy-max-cost": "max_estimated_cost_micros",
    "policy-currency": "currency",
    "policy-critical-reserve": "critical_contact_reserve",
    "policy-automation-mode": "automation_mode",
    "policy-execution-concurrency": "execution_concurrency",
    "policy-repair-attempts": "max_repair_attempts",
    "policy-repair-horizon-hours": "repair_horizon_hours",
    "policy-distinct-provider": "distinct_provider_required",
    "policy-distinct-station": "distinct_station_required",
    "policy-distinct-pool": "distinct_service_pool_required",
  }

  assert.equal(control?.getAttribute("name"), `policy[${keyById[id]}]`, `${id}: name is exact`)
}
assert.equal(
  document.querySelector("#policy-automatic-submission")?.getAttribute("name"),
  "policy[automatic_submission]",
)

const hiddenInputs = [...form.querySelectorAll('input[type="hidden"]')]
assert.deepEqual(
  hiddenInputs.map((input) => input.getAttribute("name")),
  [
    "policy[automatic_submission]",
    "policy[distinct_provider_required]",
    "policy[distinct_station_required]",
    "policy[distinct_service_pool_required]",
  ],
  "the four existing hidden-false fields retain exact names and order",
)
assert.deepEqual(
  hiddenInputs.map((input) => input.value),
  ["false", "false", "false", "false"],
  "every existing hidden-false value stays exact",
)

const expectedPayload = (maxContactsValue) => ({
  policy: {
    max_horizon_hours: "24",
    requirement_concurrency: "3",
    provider_search_concurrency: "4",
    reuse_freshness_seconds: "300",
    max_contacts: maxContactsValue,
    max_estimated_cost_micros: "500000",
    currency: "USD",
    critical_contact_reserve: "2",
    automation_mode: "bounded_automatic",
    execution_concurrency: "2",
    max_repair_attempts: "1",
    repair_horizon_hours: "6",
    distinct_provider_required: "true",
    distinct_station_required: "false",
    distinct_service_pool_required: "true",
    automatic_submission: "true",
  },
})

const assertDisclosure = (state, hidden) => {
  assert.equal(disclosureRoot.getAttribute("data-state"), state)
  assert.equal(trigger.getAttribute("data-state"), state)
  assert.equal(form.getAttribute("data-state"), state)
  assert.equal(trigger.getAttribute("aria-controls"), "fleet-policy-form")
  assert.equal(trigger.getAttribute("aria-controls"), form.id)
  assert.equal(trigger.getAttribute("aria-expanded"), String(state === "open"))
  assert.equal(form.hasAttribute("hidden"), hidden)
}

const assertNativeIdentity = () => {
  assert.equal(document.querySelector("#fleet-policy-editor")?.firstElementChild, disclosureRoot)
  assert.equal(document.querySelector("#fleet-policy-form"), form)
  assert.equal(document.querySelector("#policy-max-contacts"), maxContacts)
  assert.equal(document.querySelector("#save-fleet-policy"), submit)
}

assertDisclosure("open", false)
assert.equal(trigger.textContent.trim(), "Create the initial policy")
assert.equal(maxContacts.value, "12")

maxContacts.value = "27"
maxContacts.dispatchEvent(new dom.window.Event("input", {bubbles: true}))
await flushVue(nextTick)
assert.deepEqual(validations, [expectedPayload("27")])

const submitEvent = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(form.dispatchEvent(submitEvent), false, "the existing submit handler prevents native navigation")
await flushVue(nextTick)
assert.equal(submitEvent.defaultPrevented, true)
assert.deepEqual(saves, [expectedPayload("27")])

trigger.click()
await flushVue(nextTick)
assertDisclosure("closed", true)
assertNativeIdentity()
assert.equal(maxContacts.value, "27")

trigger.click()
await flushVue(nextTick)
assertDisclosure("open", false)
assertNativeIdentity()
assert.equal(maxContacts.value, "27")

trigger.click()
await flushVue(nextTick)
assertDisclosure("closed", true)

currentPolicyForm.value = policyForm({
  open: true,
  summary: "Same epoch whole-prop replacement",
  maxContacts: "27",
})
await flushVue(nextTick)
assert.equal(trigger.textContent.trim(), "Same epoch whole-prop replacement")
assertDisclosure("closed", true)
assertNativeIdentity()
assert.equal(maxContacts.value, "27")

trigger.click()
await flushVue(nextTick)
assertDisclosure("open", false)

currentPolicyForm.value = policyForm({
  open: false,
  summary: "Changed server-open epoch",
  maxContacts: "27",
})
await flushVue(nextTick)
assert.equal(trigger.textContent.trim(), "Changed server-open epoch")
assertDisclosure("closed", true)
assertNativeIdentity()
assert.equal(maxContacts.value, "27")

currentPolicyForm.value = policyForm({
  open: true,
  summary: "Changed server-open epoch again",
  maxContacts: "27",
})
await flushVue(nextTick)
assertDisclosure("open", false)
assertNativeIdentity()
assert.equal(maxContacts.value, "27")

app.unmount()
dom.window.close()

console.log(
  `fleet_policy_form_disclosure_reconciliation_test passed (${scenarios.length} scenarios; no colocated hook; browser/LiveVue transport/CSRF remain separate gates)`,
)

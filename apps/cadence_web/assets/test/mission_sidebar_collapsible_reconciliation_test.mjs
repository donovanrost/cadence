import assert from "node:assert/strict"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the actual Mission SFC loads the real CadenceCollapsible adapter graph",
  "the initial effective disclosure state comes from the server expanded seed",
  "native button interaction updates client-owned state immediately",
  "same-epoch replacement of the complete presentation prop preserves local state",
  "changed active and expanded seeds change the epoch and intentionally reseed",
  "hidden content stays mounted with exact ul and anchor identity",
  "stable content id, aria, data-state, button type, and link attrs remain exact",
])

const separateGates = Object.freeze([
  "BROWSER GATE: Enter, Space, and focus behavior require real-browser verification",
  "LIVE TRANSPORT GATE: LiveVue transport reconciliation requires integration verification",
])

assert.equal(scenarios.length, 7)
assert.equal(separateGates.length, 2)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const componentPath = resolve(testDirectory, "../vue/MissionSidebarNavigation.vue")

await assertPinnedAdapterRuntime(packageLockPath)

const dom = installDom('<div id="app"></div>')
const missionSfc = await loadSfc(componentPath)
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const MissionSidebarNavigation = missionSfc.component

const navigationAttrs = (href) => ({
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href,
})

const missionPresentation = ({
  active = true,
  expanded = true,
  missionDisplayName = "Canary Mission",
  reconciliation = "initial-server-seed",
  sectionLabel = "Comms",
} = {}) => ({
  overlay: {
    class: "drawer-overlay",
    attrs: {"aria-label": "close sidebar", for: "sidebar-drawer"},
  },
  root: {
    attrs: {
      "data-reconciliation": reconciliation,
      "data-sidebar-collapsible": "",
    },
    expanded_class: "sidebar-collapsible sidebar-expanded",
    collapsed_class: "sidebar-collapsible sidebar-collapsed",
  },
  organization: {
    class: "organization-shell",
    link: {
      attrs: navigationAttrs("/"),
      class: "organization-link",
      icon_class: "organization-icon",
      label_class: "organization-label",
      label: "Canary Organization",
    },
  },
  mission: {
    class: "mission-shell",
    name_class: "mission-name",
    display_name: missionDisplayName,
    slug_visible: true,
    slug_class: "mission-slug",
    slug: "canary",
  },
  navigation: {
    class: "mission-navigation",
    list_class: "mission-navigation-list",
    items: [
      {
        kind: "link",
        key: "overview",
        attrs: navigationAttrs("/missions/mission-canary"),
        class: "overview-link",
        icon_class: "overview-icon",
        label_class: "overview-label",
        label: "Overview",
        active: false,
      },
      {
        kind: "section",
        key: "comms",
        details_class: "group",
        expanded,
        summary_class: "comms-trigger",
        icon_class: "comms-icon",
        label_class: "comms-label",
        label: sectionLabel,
        chevron_class:
          "comms-chevron group-data-[state=open]:rotate-90 sidebar-label",
        list_class: "comms-links",
        children: [
          {
            key: "comms-routing",
            attrs: navigationAttrs("/missions/mission-canary/comms/routing"),
            class: "routing-link",
            icon_container_class: "routing-icon-container",
            icon_class: "routing-icon",
            label_class: "routing-label",
            label: "Routing",
            active,
          },
        ],
        active,
      },
    ],
  },
  sign_out: {
    class: "sign-out-shell",
    form: {
      attrs: {action: "/session", class: "sign-out-form", method: "post"},
      hidden_fields: [
        {
          key: "method",
          attrs: {name: "_method", type: "hidden", value: "delete"},
        },
        {
          key: "csrf",
          attrs: {name: "_csrf_token", type: "hidden", value: "canary-csrf"},
        },
      ],
      button: {
        attrs: {type: "submit"},
        class: "sign-out-button",
        icon_class: "sign-out-icon",
        label_class: "sign-out-label",
        label: "Sign out",
      },
    },
  },
  collapse: {
    attrs: {title: "Toggle sidebar", type: "button"},
    class: "sidebar-toggle",
    icon_class: "sidebar-toggle-icon",
  },
})

const presentation = ref(missionPresentation())

const MissionCanaryOracle = defineComponent({
  name: "MissionSidebarCollapsibleReconciliationOracle",
  setup() {
    return () => h(MissionSidebarNavigation, {presentation: presentation.value})
  },
})

const app = createApp(MissionCanaryOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const document = dom.window.document
const sidebar = document.querySelector("[data-sidebar-collapsible]")
const trigger = document.querySelector(
  'button[aria-controls="mission-sidebar-comms-content"]',
)
const sectionRoot = trigger?.parentElement
const content = document.querySelector("#mission-sidebar-comms-content")
const childAnchor = content?.querySelector(
  'a[href="/missions/mission-canary/comms/routing"]',
)

assert.ok(sidebar instanceof dom.window.HTMLDivElement)
assert.ok(sectionRoot instanceof dom.window.HTMLDivElement)
assert.ok(trigger instanceof dom.window.HTMLButtonElement)
assert.ok(content instanceof dom.window.HTMLUListElement)
assert.ok(childAnchor instanceof dom.window.HTMLAnchorElement)
assert.deepEqual(
  [...sectionRoot.children].map((child) => child.tagName),
  ["BUTTON", "UL"],
  "the caller-owned root keeps trigger then content as native siblings",
)
assert.equal(trigger.parentElement, sectionRoot)
assert.equal(content.parentElement, sectionRoot)
assert.equal(trigger.type, "button")
assert.equal(trigger.disabled, false)
assert.equal(sectionRoot.getAttribute("data-disabled"), null)
assert.equal(trigger.getAttribute("data-disabled"), null)
assert.equal(content.getAttribute("data-disabled"), null)

const assertRelationship = (state, hidden) => {
  assert.equal(sectionRoot.getAttribute("data-state"), state)
  assert.equal(trigger.getAttribute("data-state"), state)
  assert.equal(content.getAttribute("data-state"), state)
  assert.equal(trigger.getAttribute("aria-controls"), "mission-sidebar-comms-content")
  assert.equal(trigger.getAttribute("aria-controls"), content.id)
  assert.equal(trigger.getAttribute("aria-expanded"), String(state === "open"))
  assert.equal(content.hasAttribute("hidden"), hidden)
}

const assertNativeIdentity = () => {
  assert.equal(
    document.querySelector('button[aria-controls="mission-sidebar-comms-content"]'),
    trigger,
  )
  assert.equal(document.querySelector("#mission-sidebar-comms-content"), content)
  assert.equal(
    document.querySelector('a[href="/missions/mission-canary/comms/routing"]'),
    childAnchor,
  )
}

const assertChildLinkAttrs = () => {
  assert.equal(childAnchor.getAttribute("data-phx-link"), "redirect")
  assert.equal(childAnchor.getAttribute("data-phx-link-state"), "push")
  assert.equal(childAnchor.getAttribute("href"), "/missions/mission-canary/comms/routing")
}

assert.equal(sidebar.getAttribute("data-reconciliation"), "initial-server-seed")
assert.equal(trigger.textContent.trim(), "Comms")
assertRelationship("open", false)
assertChildLinkAttrs()

trigger.click()
await flushVue(nextTick)

assertRelationship("closed", true)
assertNativeIdentity()
assertChildLinkAttrs()

presentation.value = missionPresentation({
  missionDisplayName: "Unrelated LiveVue Replacement",
  reconciliation: "same-epoch-prop-replacement",
  sectionLabel: "Communications",
})
await flushVue(nextTick)

assert.equal(sidebar.getAttribute("data-reconciliation"), "same-epoch-prop-replacement")
assert.equal(document.querySelector(".mission-name").textContent.trim(), "Unrelated LiveVue Replacement")
assert.equal(trigger.textContent.trim(), "Communications")
assertRelationship("closed", true)
assertNativeIdentity()
assertChildLinkAttrs()

trigger.click()
await flushVue(nextTick)

assertRelationship("open", false)
assertNativeIdentity()

presentation.value = missionPresentation({
  active: false,
  expanded: false,
  missionDisplayName: "Changed Server Seed",
  reconciliation: "changed-seed-epoch",
  sectionLabel: "Comms",
})
await flushVue(nextTick)

assert.equal(sidebar.getAttribute("data-reconciliation"), "changed-seed-epoch")
assertRelationship("closed", true)
assertNativeIdentity()
assertChildLinkAttrs()

app.unmount()

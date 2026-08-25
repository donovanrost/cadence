import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"
import {
  announceCadencePopoverOpened,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "../vue/ui/reka/popover_compatibility.js"

const scenarioLedger = Object.freeze([
  "CadenceMenu owns a controlled non-modal Reka menu with collision-safe bottom-end positioning",
  "the dashboard menu retains every server-owned root trigger panel item and navigation attribute",
  "opening focuses the first native menu item while Reka owns wrapped Arrow Home and End movement",
  "Escape restores the current trigger and suppressed close reasons never restore it",
  "Tab and native item selection close without focus restoration",
  "peer popovers and menus share one-open overlay coordination",
  "unchanged identity preserves open state while changed or missing identity closes",
])

assert.equal(process.versions.node, "24.16.0", "CadenceMenu contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 7)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const adapterPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenu.vue")
const menuPath = resolve(testDirectory, "../vue/DashboardToolbarMenu.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const presenterPath = resolve(
  testDirectory,
  "../../lib/cadence_web/live/ops_dashboard_show_live/dashboard_toolbar_components.ex",
)

const [adapterSource, menuSource, packageLockSource, presenterSource] = await Promise.all([
  readFile(adapterPath, "utf8"),
  readFile(menuPath, "utf8"),
  readFile(packageLockPath, "utf8"),
  readFile(presenterPath, "utf8"),
])
const adapterTemplate = adapterSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const menuTemplate = menuSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
const packageLock = JSON.parse(packageLockSource)

assert.ok(adapterTemplate, "CadenceMenu.vue must have a template block")
assert.ok(menuTemplate, "DashboardToolbarMenu.vue must have a template block")
assert.equal(packageLock.packages["node_modules/reka-ui"].version, "2.10.3")

assert.match(
  adapterSource,
  /import \{[\s\S]*DropdownMenuContent,[\s\S]*DropdownMenuRoot,[\s\S]*DropdownMenuTrigger,[\s\S]*\} from "reka-ui"/,
)
assert.match(adapterTemplate, /<DropdownMenuRoot[\s\S]*:open="open"[\s\S]*:modal="false"/)
assert.match(adapterTemplate, /@update:open="updateOpen"/)
assert.match(adapterTemplate, /<DropdownMenuTrigger as-child>/)
assert.match(adapterTemplate, /<DropdownMenuContent[\s\S]*v-if="open"[\s\S]*as-child/)
assert.match(adapterTemplate, /:side="props\.side"/)
assert.match(adapterTemplate, /:align="props\.align"/)
assert.match(adapterTemplate, /:collision-padding="props\.collisionPadding"/)
assert.match(adapterTemplate, /:prioritize-position="props\.prioritizePosition"/)
assert.match(adapterTemplate, /:loop="true"/)
assert.match(adapterTemplate, /position-strategy="fixed"/)
assert.match(adapterTemplate, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(adapterTemplate, /@interact-outside="handleInteractOutside"/)
assert.match(adapterTemplate, /@keydown\.tab="handleTabKeyDown"/)
assert.match(adapterTemplate, /<slot[\s\S]*v-else[\s\S]*name="content"/)
assert.doesNotMatch(adapterSource, /DropdownMenuPortal|setTimeout|setInterval/)

assert.match(menuSource, /import \{DropdownMenuItem\} from "reka-ui"/)
assert.match(menuSource, /import CadenceMenu from "\.\/ui\/reka\/CadenceMenu\.vue"/)
assert.match(menuSource, /const attrs = \{\.\.\.props\.presentation\.panel\.attrs\}/)
assert.match(menuSource, /delete attrs\.hidden/)
assert.match(menuTemplate, /<CadenceMenu/)
assert.match(menuTemplate, /:identity="menuIdentity"/)
assert.match(menuTemplate, /side="bottom"/)
assert.match(menuTemplate, /align="end"/)
assert.match(menuTemplate, /:collision-padding="16"/)
assert.match(menuTemplate, /v-bind="props\.presentation\.root\.attrs"/)
assert.match(menuTemplate, /v-bind="props\.presentation\.trigger\.attrs"/)
assert.match(menuTemplate, /:aria-expanded="String\(open\)"/)
assert.match(menuTemplate, /v-bind="panelAttrs"[\s\S]*:hidden="!open"/)
assert.match(menuTemplate, /v-bind="item\.wrapper\.attrs"/)
assert.match(menuTemplate, /<DropdownMenuItem[\s\S]*v-if="open"[\s\S]*as-child[\s\S]*@select="onItemSelect"/)
assert.equal(menuTemplate.match(/<a v-(?:bind|else)/g)?.length, 2)
assert.equal(menuTemplate.match(/v-bind="item\.link\.attrs"/g)?.length, 2)
assert.doesNotMatch(menuSource, /ArrowDown|ArrowUp|\bHome\b|\bEnd\b|createDashboardToolbarMenuController/)
assert.doesNotMatch(menuSource, /addEventListener|removeEventListener|onBeforeUpdate|onUpdated/)

const serverContracts = [
  'id: "dashboard-menu"',
  '"data-overlay-kind": "menu"',
  '"data-overlay-placement": "bottom-end"',
  'id: "dashboard-menu-trigger"',
  '"data-overlay-trigger": ""',
  '"aria-haspopup": "menu"',
  '"aria-controls": "dashboard-menu-menu"',
  '"aria-label": "Actions"',
  'id: "dashboard-menu-menu"',
  'role: "menu"',
  '"data-overlay-panel": ""',
  'wrapper: %{attrs: %{role: "none", class: "cadence-menu-item"}}',
  'href: path',
  '"data-phx-link": "redirect"',
  '"data-phx-link-state": "push"',
  '"data-dashboard-comparison-review-open-count": open_summary.count_text',
  '"data-dashboard-comparison-review-open-requests": open_summary.request_ids_attr',
  '"data-dashboard-comparison-review-open-placements": open_summary.placements_attr',
]

for (const contract of serverContracts) {
  assert.ok(presenterSource.includes(contract), `missing server-owned dashboard menu contract: ${contract}`)
}

const policyStart = "// CADENCE_MENU_FOCUS_POLICY_START"
const policyEnd = "// CADENCE_MENU_FOCUS_POLICY_END"
const policyStartIndex = adapterSource.indexOf(policyStart)
const policyEndIndex = adapterSource.indexOf(policyEnd)
assert.ok(policyStartIndex >= 0 && policyEndIndex > policyStartIndex)

const policySource = adapterSource
  .slice(policyStartIndex + policyStart.length, policyEndIndex)
  .replace("rootElement: HTMLElement | null", "rootElement")
  .replace("rootElement?.querySelector<HTMLElement>", "rootElement?.querySelector")
const context = {}
vm.createContext(context)
vm.runInContext(
  `${policySource}\nglobalThis.createPolicy = createCadenceMenuFocusPolicy;` +
    "globalThis.focusFirstItem = focusFirstCadenceMenuItem;",
  context,
  {filename: adapterPath},
)

const policy = context.createPolicy()
assert.equal(policy.restoreFocusOnClose(), true, "Escape is the unsuppressed close path")

for (const reason of ["Tab", "item selection", "outside interaction", "peer overlay"]) {
  policy.closeWithoutFocus()
  assert.equal(policy.restoreFocusOnClose(), false, `${reason} must suppress trigger restoration`)
  assert.equal(policy.restoreFocusOnClose(), true, `${reason} suppression must reset after close`)
}

let firstFocusCount = 0
let secondFocusCount = 0
const firstItem = {focus: () => (firstFocusCount += 1)}
const secondItem = {focus: () => (secondFocusCount += 1)}
const menuRoot = {
  querySelector(selector) {
    assert.equal(selector, "[data-overlay-panel] [role='menuitem']")
    return firstItem
  },
}

assert.equal(context.focusFirstItem(menuRoot), true)
assert.equal(firstFocusCount, 1)
assert.equal(secondFocusCount, 0)
assert.equal(context.focusFirstItem({querySelector: () => null}), false)
assert.equal(context.focusFirstItem(null), false)

assert.match(
  adapterSource,
  /announceCadencePopoverOpened\(window, root\.value\)\n  focusFirstCadenceMenuItem\(root\.value\)/,
)
assert.match(adapterSource, /const handleTabKeyDown = \(\) => focusPolicy\.closeWithoutFocus\(\)/)
assert.match(adapterSource, /const handleItemSelect = \(\) => focusPolicy\.closeWithoutFocus\(\)/)
assert.match(
  adapterSource,
  /const handleCloseAutoFocus = \(event: Event\) => \{[\s\S]*event\.preventDefault\(\)[\s\S]*restoreCurrentTriggerFocus/,
)

class FakeWindow extends EventTarget {
  CustomEvent = class extends Event {
    constructor(type, options) {
      super(type)
      this.detail = options.detail
    }
  }
}

const windowObject = new FakeWindow()
const scopeRoot = {id: "dashboard-data-controls"}
const healthRoot = {id: "dashboard-data-issues"}
const actionMenuRoot = {id: "dashboard-menu"}
const open = {scope: true, health: true, menu: true}
const removeScope = subscribeToLegacyOverlayOpen(
  windowObject,
  scopeRoot,
  () => (open.scope = false),
)
const removeHealth = subscribeToLegacyOverlayOpen(
  windowObject,
  healthRoot,
  () => (open.health = false),
)
const removeMenu = subscribeToLegacyOverlayOpen(
  windowObject,
  actionMenuRoot,
  () => (open.menu = false),
)

announceCadencePopoverOpened(windowObject, actionMenuRoot)
assert.deepEqual(open, {scope: false, health: false, menu: true})
open.scope = true
announceCadencePopoverOpened(windowObject, scopeRoot)
assert.deepEqual(open, {scope: true, health: false, menu: false})
removeScope()
removeHealth()
removeMenu()

assert.equal(preservesPopoverOpenState(true, "dashboard-menu", "dashboard-menu"), true)
assert.equal(preservesPopoverOpenState(false, "dashboard-menu", "dashboard-menu"), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-menu", "replacement"), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-menu", ""), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-menu", null), false)
assert.equal(preservesPopoverOpenState(true, "dashboard-menu", undefined), false)

console.log(`cadence_menu_test passed (${scenarioLedger.length} scenarios)`)

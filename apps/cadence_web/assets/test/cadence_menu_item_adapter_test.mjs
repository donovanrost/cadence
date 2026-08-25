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
  "the adapter delegates to DropdownMenuItem with mandatory as-child composition",
  "the slotted menu link remains the only public node with every server-authored attribute",
  "Reka role roving-tabindex and Enter selection semantics survive the adapter",
  "select forwards the cancelable Reka event and honors prevented then closing selections",
  "disabled items retain Reka disabled semantics and do not select",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenuItem.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarios.length, 5)

const dom = installDom()
const {component: CadenceMenuItem, descriptor, source} = await loadSfc(componentPath)
const script = descriptor.scriptSetup.content
const template = descriptor.template.content

assert.match(script, /^import \{DropdownMenuItem\} from "reka-ui"$/m)
assert.match(script, /import \{CadencePrimitiveChild\} from "\.\/cadence_primitive_child\.js"/)
assert.match(script, /active: boolean/)
assert.match(script, /disabled\?: boolean/)
assert.match(script, /select: \[event: Event\]/)
assert.match(template, /<DropdownMenuItem/)
assert.match(template, /v-if="props\.active"/)
assert.match(template, /:disabled="props\.disabled"/)
assert.match(template, /\bas-child\b/)
assert.match(template, /@select="emit\('select', \$event\)"/)
assert.match(template, /<slot v-else><\/slot>/)
assert.doesNotMatch(source, /@click|@keydown|preventDefault|stopPropagation|<a\b|<button\b/)

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const {
  DropdownMenuContent,
  DropdownMenuRoot,
  DropdownMenuTrigger,
} = integrationRequire("reka-ui")
const open = ref(true)
const openRequests = []
const selectedEvents = []
let preventNextSelection = true
let nativeClickCount = 0

const RuntimeOracle = defineComponent({
  name: "CadenceMenuItemRuntimeOracle",
  setup() {
    return () =>
      h("div", {id: "menu-item-oracle"}, [
        h("div", {id: "inactive-menu-panel"}, [
          h(
            CadenceMenuItem,
            {active: false, disabled: true},
            {
              default: () =>
                h(
                  "a",
                  {
                    id: "inactive-menu-item",
                    href: "/dashboards/inactive",
                    role: "link",
                    tabindex: "7",
                    "aria-disabled": "false",
                    "data-server-item": "inactive-preserved",
                  },
                  "Inactive item",
                ),
            },
          ),
        ]),
        h(
          DropdownMenuRoot,
          {
            open: open.value,
            modal: false,
            "onUpdate:open": (nextOpen) => {
              openRequests.push(nextOpen)
              open.value = nextOpen
            },
          },
          {
            default: () => [
              h(
                DropdownMenuTrigger,
                {asChild: true},
                {default: () => h("button", {id: "menu-trigger", type: "button"}, "Menu")},
              ),
              h(
                DropdownMenuContent,
                {
                  asChild: true,
                  onOpenAutoFocus: (event) => event.preventDefault(),
                },
                {
                  default: () =>
                    h("div", {id: "menu-panel", "data-overlay-panel": ""}, [
                      h(
                        CadenceMenuItem,
                        {
                          active: true,
                          onSelect: (event) => {
                            selectedEvents.push(event)
                            if (preventNextSelection) {
                              preventNextSelection = false
                              event.preventDefault()
                            }
                          },
                        },
                        {
                          default: () =>
                            h(
                              "a",
                              {
                                id: "menu-item-inspect",
                                href: "/dashboards/alpha",
                                class: "server-menu-link",
                                role: "link",
                                tabindex: "7",
                                "aria-disabled": "true",
                                "data-disabled": "child-stale",
                                "data-phx-link": "redirect",
                                "data-phx-link-state": "push",
                                "data-server-item": "preserved",
                                onClick: (event) => {
                                  event.preventDefault()
                                  nativeClickCount++
                                },
                              },
                              "Inspect dashboard",
                            ),
                        },
                      ),
                      h(
                        CadenceMenuItem,
                        {
                          active: true,
                          disabled: true,
                          onSelect: (event) => selectedEvents.push(event),
                        },
                        {
                          default: () =>
                            h(
                              "a",
                              {
                                id: "menu-item-disabled",
                                href: "/dashboards/disabled",
                                "aria-disabled": "false",
                                onClick: (event) => event.preventDefault(),
                              },
                              "Disabled action",
                            ),
                        },
                      ),
                    ]),
                },
              ),
            ],
          },
        ),
      ])
  },
})

const app = createApp(RuntimeOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const panel = dom.window.document.querySelector("#menu-panel")
const item = dom.window.document.querySelector("#menu-item-inspect")
const disabledItem = dom.window.document.querySelector("#menu-item-disabled")
const inactivePanel = dom.window.document.querySelector("#inactive-menu-panel")
const inactiveItem = dom.window.document.querySelector("#inactive-menu-item")

assert.ok(panel)
assert.equal(inactivePanel.children.length, 1, "inactive mode renders the raw slotted child")
assert.equal(inactiveItem.parentElement, inactivePanel)
assert.equal(inactiveItem.getAttribute("role"), "link")
assert.equal(inactiveItem.getAttribute("tabindex"), "7")
assert.equal(inactiveItem.getAttribute("aria-disabled"), "false")
assert.equal(inactiveItem.getAttribute("data-disabled"), null)
assert.equal(inactiveItem.getAttribute("data-server-item"), "inactive-preserved")
assert.equal(panel.children.length, 2, "as-child adds no item wrapper")
assert.equal(item.parentElement, panel)
assert.equal(item.tagName, "A")
assert.equal(item.getAttribute("href"), "/dashboards/alpha")
assert.equal(item.getAttribute("class"), "server-menu-link")
assert.equal(item.getAttribute("data-phx-link"), "redirect")
assert.equal(item.getAttribute("data-phx-link-state"), "push")
assert.equal(item.getAttribute("data-server-item"), "preserved")
assert.equal(item.getAttribute("role"), "menuitem")
assert.equal(item.getAttribute("tabindex"), "-1")
assert.equal(item.getAttribute("aria-disabled"), null)
assert.equal(item.getAttribute("data-disabled"), null)
assert.equal(disabledItem.getAttribute("role"), "menuitem")
assert.equal(disabledItem.getAttribute("aria-disabled"), "true")
assert.equal(disabledItem.getAttribute("data-disabled"), "")

disabledItem.click()
await flushVue(nextTick)
assert.deepEqual(selectedEvents, [])
assert.equal(open.value, true)

item.focus()
const enterEvent = new dom.window.KeyboardEvent("keydown", {
  bubbles: true,
  cancelable: true,
  key: "Enter",
})
item.dispatchEvent(enterEvent)
await flushVue(nextTick)

assert.equal(enterEvent.defaultPrevented, true, "Reka consumes Enter as a selection key")
assert.equal(nativeClickCount, 1, "Reka keyboard selection dispatches the native child click")
assert.equal(selectedEvents.length, 1)
assert.equal(selectedEvents[0].type, "menu.itemSelect")
assert.equal(selectedEvents[0].bubbles, true)
assert.equal(selectedEvents[0].cancelable, true)
assert.equal(selectedEvents[0].defaultPrevented, true)
assert.equal(open.value, true, "preventing the forwarded select event keeps the menu open")

const spaceEvent = new dom.window.KeyboardEvent("keydown", {
  bubbles: true,
  cancelable: true,
  key: " ",
})
item.dispatchEvent(spaceEvent)
await flushVue(nextTick)

assert.equal(spaceEvent.defaultPrevented, true, "Reka consumes Space as a selection key")
assert.equal(nativeClickCount, 2)
assert.equal(selectedEvents.length, 2)
assert.equal(selectedEvents[1].type, "menu.itemSelect")
assert.equal(selectedEvents[1].defaultPrevented, false)
assert.equal(open.value, false)
assert.equal(dom.window.document.querySelector("#menu-panel"), null)
assert.ok(openRequests.includes(false), "selection closes through the surrounding Reka menu")

app.unmount()
dom.window.close()

console.log(`cadence_menu_item_adapter_test passed (${scenarios.length} scenarios)`)

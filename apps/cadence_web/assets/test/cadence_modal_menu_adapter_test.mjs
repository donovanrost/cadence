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

const scenarioLedger = Object.freeze([
  "the actual adapter compiles and mounts two caller-ID and two generated-ID menus",
  "closed menus expose one native trigger and neither content nor unresolved aria-controls",
  "caller-owned trigger and content IDs resolve both open IDREF directions",
  "generated content IDs and trigger aria-controls stay unique while content labels caller triggers",
  "content is portaled outside the LiveVue host with one menu root and native menuitem anchors",
  "caller wrappers, buttons, anchors, classes, hrefs, and LiveView navigation attributes remain exact",
  "ArrowDown opens and moves focus into every menu through Reka",
  "Escape closes every first instance and restores its public trigger focus",
  "item selection closes every second instance and restores its public trigger focus",
  "default modal Tab suppression and background aria-hidden behavior remain Reka-owned",
  "only raw update:open events cross the adapter and native anchor activation fires exactly once",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/reka/CadenceModalMenu.vue")
const itemPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenuItem.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarioLedger.length, 11)

const dom = installDom('<div id="app"></div>')
Object.defineProperty(globalThis, "HTMLInputElement", {
  configurable: true,
  value: dom.window.HTMLInputElement,
})

const [{component: CadenceModalMenu, descriptor, source}, {component: CadenceMenuItem}] =
  await Promise.all([loadSfc(componentPath), loadSfc(itemPath)])
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")

assert.match(
  descriptor.scriptSetup.content,
  /DropdownMenuContent,[\s\S]*DropdownMenuPortal,[\s\S]*DropdownMenuRoot,[\s\S]*DropdownMenuTrigger/
)
assert.match(descriptor.scriptSetup.content, /"update:open": \[open: boolean\]/)
assert.match(descriptor.template.content, /<DropdownMenuPortal>/)
assert.equal(descriptor.template.content.match(/<CadencePrimitiveChild/g)?.length, 2)
assert.equal(descriptor.template.content.match(/<slot name="trigger"/g)?.length, 1)
assert.equal(descriptor.template.content.match(/<slot name="content"/g)?.length, 1)
assert.doesNotMatch(source, /:modal="false"|\bmodal\?:|\bopen = ref|\bref\(|\bwatch\(/)
assert.doesNotMatch(source, /request-change|compatibility|announceCadence|subscribeToLegacy/)
assert.doesNotMatch(source, /@close-auto-focus|@open-auto-focus|@escape-key-down|@select/)

const menuCases = [
  ...["alpha", "beta"].map((name, index) => ({
    shape: "caller",
    name,
    index,
    wrapperId: `caller-${name}-actions`,
    triggerId: `caller-${name}-actions-trigger`,
    contentId: `caller-${name}-actions-menu`,
  })),
  ...["alpha", "beta"].map((name, index) => ({
    shape: "generated",
    name,
    index,
    wrapperId: null,
    triggerId: `generated-${name}-actions`,
    contentId: null,
  })),
]

const openEvents = new Map(menuCases.map((menuCase) => [menuCase.triggerId, []]))
const activationCounts = new Map(menuCases.map((menuCase) => [menuCase.triggerId, 0]))

const menuSlots = (menuCase) => ({
  trigger: ({open}) =>
    h(
      "button",
      {
        id: menuCase.triggerId,
        type: "button",
        class: `btn btn-ghost ${menuCase.shape}-trigger`,
        "aria-label": `${menuCase.shape} ${menuCase.name} actions`,
        ...(menuCase.shape === "caller"
          ? {"aria-controls": open ? menuCase.contentId : undefined}
          : {}),
        "data-server-trigger": "preserved",
      },
      [h("span", {class: "hero-ellipsis-vertical h-4 w-4"})]
    ),
  content: ({open}) =>
    h(
      "div",
      {
        ...(menuCase.contentId ? {id: menuCase.contentId} : {}),
        "aria-labelledby": menuCase.triggerId,
        class: `z-50 min-w-40 rounded-box ${menuCase.shape}-content`,
        "data-server-content": "preserved",
      },
      [
        h(
          CadenceMenuItem,
          {active: open},
          {
            default: () =>
              h(
                "a",
                {
                  id: `${menuCase.triggerId}-item`,
                  href: `/menus/${menuCase.shape}/${menuCase.name}`,
                  class: "block cursor-pointer rounded px-3 py-2 text-sm",
                  "data-phx-link": "redirect",
                  "data-phx-link-state": "push",
                  "data-server-item": "preserved",
                  onClick: (event) => {
                    event.preventDefault()
                    activationCounts.set(
                      menuCase.triggerId,
                      activationCounts.get(menuCase.triggerId) + 1
                    )
                  },
                },
                `Open ${menuCase.name}`
              ),
          }
        ),
      ]
    ),
})

const RuntimeOracle = defineComponent({
  name: "CadenceModalMenuRuntimeOracle",
  setup() {
    return () =>
      h(
        "main",
        {id: "modal-menu-probe", "data-server-root": "preserved"},
        menuCases.map((menuCase) => {
          const menu = h(
            CadenceModalMenu,
            {
              side: "bottom",
              align: "end",
              sideOffset: 4,
              "onUpdate:open": (open) => openEvents.get(menuCase.triggerId).push(open),
            },
            menuSlots(menuCase)
          )

          if (!menuCase.wrapperId) return menu

          return h(
            "div",
            {
              id: menuCase.wrapperId,
              class: "cadence-overlay",
              "data-server-wrapper": "preserved",
            },
            [menu]
          )
        })
      )
  },
})

document.addEventListener("click", (event) => {
  if (event.target.closest("a")) event.preventDefault()
})

const appElement = document.querySelector("#app")
const app = createApp(RuntimeOracle)
app.mount(appElement)
await flushVue(nextTick)

const probe = document.querySelector("#modal-menu-probe")
assert.ok(probe)
assert.equal(probe.getAttribute("data-server-root"), "preserved")

const assertClosed = (menuCase) => {
  const trigger = document.getElementById(menuCase.triggerId)

  assert.ok(trigger, `${menuCase.shape} ${menuCase.name} keeps its public trigger`)
  assert.equal(trigger.tagName, "BUTTON")
  assert.equal(trigger.getAttribute("type"), "button")
  assert.equal(trigger.getAttribute("aria-haspopup"), "menu")
  assert.equal(trigger.getAttribute("aria-expanded"), "false")
  assert.equal(trigger.hasAttribute("aria-controls"), false)
  assert.equal(trigger.getAttribute("data-state"), "closed")
  assert.equal(trigger.getAttribute("data-server-trigger"), "preserved")
  assert.equal(document.querySelectorAll(`[id="${menuCase.triggerId}"]`).length, 1)
  assert.equal(document.getElementById(`${menuCase.triggerId}-item`), null)

  if (menuCase.contentId) assert.equal(document.getElementById(menuCase.contentId), null)
  if (menuCase.wrapperId) {
    const wrapper = document.getElementById(menuCase.wrapperId)
    assert.ok(wrapper)
    assert.equal(wrapper.className, "cadence-overlay")
    assert.equal(wrapper.getAttribute("data-server-wrapper"), "preserved")
    assert.equal(wrapper.children.length, 1, "the adapter adds no trigger wrapper")
    assert.equal(trigger.parentElement, wrapper)
  } else {
    assert.equal(trigger.parentElement, probe, "the adapter adds no trigger wrapper")
  }
}

for (const menuCase of menuCases) assertClosed(menuCase)

assert.equal(
  new Set(menuCases.map((menuCase) => menuCase.triggerId)).size,
  menuCases.length,
  "all four public trigger IDs are unique"
)

const dispatchKey = (element, key) => {
  const event = new dom.window.KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key,
  })
  element.dispatchEvent(event)
  return event
}

const settleClose = async () => {
  await flushVue(nextTick)
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 10))
  await flushVue(nextTick)
}

const generatedContentIds = []

for (const menuCase of menuCases) {
  const label = `${menuCase.shape} ${menuCase.name}`
  const trigger = document.getElementById(menuCase.triggerId)
  trigger.focus()
  const arrowDown = dispatchKey(trigger, "ArrowDown")

  assert.equal(arrowDown.defaultPrevented, true, `${label} ArrowDown stays Reka-owned`)
  await flushVue(nextTick)

  const contentId = trigger.getAttribute("aria-controls")
  const content = document.getElementById(contentId)
  const item = document.getElementById(`${menuCase.triggerId}-item`)

  assert.ok(content, `${label} mounts content while open`)
  assert.equal(trigger.getAttribute("aria-expanded"), "true")
  assert.equal(trigger.getAttribute("data-state"), "open")
  assert.equal(document.getElementById(trigger.getAttribute("aria-controls")), content)
  assert.equal(content.getAttribute("aria-labelledby"), menuCase.triggerId)
  assert.equal(document.getElementById(content.getAttribute("aria-labelledby")), trigger)
  assert.equal(content.getAttribute("role"), "menu")
  assert.equal(content.getAttribute("data-state"), "open")
  assert.equal(content.getAttribute("data-side"), "bottom")
  assert.equal(content.getAttribute("data-align"), "end")
  assert.equal(content.getAttribute("data-server-content"), "preserved")
  assert.equal(appElement.contains(content), false, `${label} content stays portaled`)
  assert.equal(document.body.contains(content), true)
  assert.equal(content.parentElement.children.length, 1, "the portal has one content root")
  assert.ok(item)
  assert.equal(content.children.length, 1, "CadenceMenuItem adds no interactive wrapper")
  assert.equal(item.parentElement, content)
  assert.equal(item.tagName, "A")
  assert.equal(item.getAttribute("role"), "menuitem")
  assert.equal(item.getAttribute("href"), `/menus/${menuCase.shape}/${menuCase.name}`)
  assert.equal(item.getAttribute("class"), "block cursor-pointer rounded px-3 py-2 text-sm")
  assert.equal(item.getAttribute("data-phx-link"), "redirect")
  assert.equal(item.getAttribute("data-phx-link-state"), "push")
  assert.equal(item.getAttribute("data-server-item"), "preserved")
  assert.equal(content.contains(document.activeElement), true)
  assert.equal(document.activeElement, item)
  assert.equal(appElement.getAttribute("aria-hidden"), "true", `${label} remains modal`)

  if (menuCase.shape === "caller") {
    assert.equal(contentId, menuCase.contentId)
    assert.equal(content.id, menuCase.contentId)
  } else {
    assert.match(contentId, /^reka-dropdown-menu-content-v-\d+$/)
    generatedContentIds.push(contentId)
  }

  const tab = dispatchKey(content, "Tab")
  assert.equal(tab.defaultPrevented, true, `${label} suppresses Tab in the modal menu`)
  assert.equal(trigger.getAttribute("aria-expanded"), "true")

  if (menuCase.index === 0) {
    dispatchKey(content, "Escape")
  } else {
    item.dispatchEvent(
      new dom.window.MouseEvent("click", {
        bubbles: true,
        cancelable: true,
        button: 0,
      })
    )
  }

  await settleClose()
  assertClosed(menuCase)
  assert.equal(document.activeElement, trigger, `${label} restores trigger focus`)
  assert.equal(appElement.hasAttribute("aria-hidden"), false, `${label} releases modal hiding`)
  assert.deepEqual(openEvents.get(menuCase.triggerId), [true, false])
  assert.equal(
    activationCounts.get(menuCase.triggerId),
    menuCase.index === 0 ? 0 : 1,
    `${label} dispatches native anchor activation exactly once`
  )
}

assert.equal(new Set(generatedContentIds).size, 2, "generated content IDs are unique")
assert.equal(
  document.querySelectorAll("[role='menu']").length,
  0,
  "all portaled content unmounts after close"
)

app.unmount()
dom.window.close()

console.log(`cadence_modal_menu_adapter_test passed (${scenarioLedger.length} scenarios)`)

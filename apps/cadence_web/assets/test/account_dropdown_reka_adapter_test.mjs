import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import test from "node:test"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarioLedger = Object.freeze([
  "click toggles aria-expanded, initial focus, focus return, and document listeners",
  "ArrowDown opens and ArrowUp/Down/Home/End move focus with wrapping",
  "Escape and outside pointer close with focus return",
  "Tab and menu activation close without returning focus",
  "destroy removes local and document listeners and resets transient state",
])

const testDirectory = dirname(fileURLToPath(import.meta.url))
const adapterPath = resolve(testDirectory, "../vue/ui/reka/AccountDropdownMenu.vue")
const itemPath = resolve(testDirectory, "../vue/ui/reka/CadenceMenuItem.vue")
const notificationsPath = resolve(testDirectory, "../vue/NotificationsBell.vue")
const userMenuPath = resolve(testDirectory, "../vue/UserMenu.vue")
const packageLockPath = resolve(testDirectory, "../../package-lock.json")

await assertPinnedAdapterRuntime(packageLockPath)
assert.equal(scenarioLedger.length, 5, "all five dropdown-controller scenarios transfer one-for-one")

const dom = installDom()
const [
  {component: AccountDropdownMenu, source},
  {component: CadenceMenuItem},
  {component: NotificationsBell},
  {component: UserMenu},
] = await Promise.all([
  loadSfc(adapterPath),
  loadSfc(itemPath),
  loadSfc(notificationsPath),
  loadSfc(userMenuPath),
])
const {createApp, defineComponent, h, nextTick} = integrationRequire("vue")

assert.match(
  source,
  /import \{[\s\S]*DropdownMenuContent,[\s\S]*DropdownMenuRoot,[\s\S]*DropdownMenuTrigger,[\s\S]*\} from "reka-ui"/,
)
assert.match(source, /:modal="false"/)
assert.match(source, /:loop="true"/)
assert.match(source, /open\.value && "dropdown-open"/)
assert.match(source, /@open-auto-focus="handleOpenAutoFocus"/)
assert.match(source, /@close-auto-focus="handleCloseAutoFocus"/)
assert.match(source, /@escape-key-down="handleEscapeKeyDown"/)
assert.match(source, /@keydown\.tab="handleTabKeyDown"/)
assert.match(source, /<slot[\s\S]*v-else[\s\S]*name="content"/)
assert.doesNotMatch(source, /addEventListener|removeEventListener|setTimeout|setInterval/)

const dispatchKey = (element, key) => {
  const event = new dom.window.KeyboardEvent("keydown", {
    bubbles: true,
    cancelable: true,
    key,
  })
  element.dispatchEvent(event)
  return event
}

const trackedDocumentListeners = (documentObject) => {
  const active = new Map()
  const originalAdd = documentObject.addEventListener.bind(documentObject)
  const originalRemove = documentObject.removeEventListener.bind(documentObject)

  documentObject.addEventListener = (type, listener, options) => {
    const listeners = active.get(type) ?? new Set()
    listeners.add(listener)
    active.set(type, listeners)
    originalAdd(type, listener, options)
  }
  documentObject.removeEventListener = (type, listener, options) => {
    active.get(type)?.delete(listener)
    originalRemove(type, listener, options)
  }

  return {
    activeCount: () => [...active.values()].reduce((count, listeners) => count + listeners.size, 0),
    restore() {
      documentObject.addEventListener = originalAdd
      documentObject.removeEventListener = originalRemove
    },
  }
}

const setup = async ({auditListeners = false} = {}) => {
  const container = dom.window.document.createElement("div")
  const outside = dom.window.document.createElement("button")
  outside.id = "outside-account-menu"
  outside.type = "button"
  dom.window.document.body.append(container, outside)

  const listenerAudit = auditListeners ? trackedDocumentListeners(dom.window.document) : null
  const activations = []
  let triggerClicks = 0

  const RuntimeOracle = defineComponent({
    name: "AccountDropdownMenuRuntimeOracle",
    setup() {
      return () =>
        h(
          AccountDropdownMenu,
          {
            class: "dropdown dropdown-end",
            "data-server-root": "preserved",
          },
          {
            trigger: ({open}) =>
              h(
                "button",
                {
                  type: "button",
                  class: "server-trigger",
                  "data-dropdown-trigger": "",
                  "data-server-trigger": "preserved",
                  "aria-haspopup": "menu",
                  "aria-expanded": String(open),
                  "aria-controls": "account-menu-panel",
                  onClick: () => (triggerClicks += 1),
                },
                "Account",
              ),
            content: ({open, onItemSelect}) => {
              const menuItem = (id, label, element = "a") =>
                h("li", {role: "presentation", "data-server-item-wrapper": id}, [
                  h(
                    CadenceMenuItem,
                    {active: open, onSelect: onItemSelect},
                    {
                      default: () =>
                        h(
                          element,
                          {
                            id,
                            ...(element === "a"
                              ? {href: `/account/${id}`, "data-phx-link": "redirect"}
                              : {type: "button"}),
                            class: "server-menu-item",
                            role: "menuitem",
                            "data-server-item": "preserved",
                            onClick: (event) => {
                              if (element === "a") event.preventDefault()
                              activations.push(id)
                            },
                          },
                          label,
                        ),
                    },
                  ),
                ])

              return h(
                "div",
                {
                  id: "account-menu-panel",
                  class: "dropdown-content menu server-panel",
                  role: "menu",
                  "data-server-panel": "preserved",
                },
                [
                  h("li", {class: "menu-title"}, "Account actions"),
                  menuItem("first-account-item", "First"),
                  menuItem("second-account-item", "Second"),
                  menuItem("third-account-item", "Third", "button"),
                ],
              )
            },
          },
        )
    },
  })

  const app = createApp(RuntimeOracle)
  app.mount(container)
  await flushVue(nextTick)

  const query = (selector) => container.querySelector(selector)
  const root = query("[data-server-root]")
  const trigger = query("[data-dropdown-trigger]")
  const panel = query("#account-menu-panel")
  const items = () => [
    query("#first-account-item"),
    query("#second-account-item"),
    query("#third-account-item"),
  ]

  return {
    activations,
    app,
    container,
    items,
    listenerAudit,
    outside,
    panel,
    root,
    trigger,
    triggerClicks: () => triggerClicks,
    async cleanup() {
      app.unmount()
      await flushVue(nextTick)
      listenerAudit?.restore()
      container.remove()
      outside.remove()
    },
  }
}

test(scenarioLedger[0], async () => {
  const oracle = await setup({auditListeners: true})

  assert.equal(oracle.root.className, "dropdown dropdown-end")
  assert.equal(oracle.root.getAttribute("data-server-root"), "preserved")
  assert.equal(oracle.root.children.length, 2, "closed DOM keeps the trigger and menu siblings")
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "false")
  assert.equal(oracle.trigger.getAttribute("aria-controls"), oracle.panel.id)
  assert.equal(oracle.panel.getAttribute("role"), "menu")
  assert.equal(oracle.panel.getAttribute("data-server-panel"), "preserved")
  assert.equal(oracle.items()[0].parentElement.getAttribute("role"), "presentation")
  assert.equal(oracle.items()[0].getAttribute("role"), "menuitem")
  assert.equal(oracle.items()[0].getAttribute("href"), "/account/first-account-item")

  oracle.trigger.click()
  await flushVue(nextTick)

  assert.equal(oracle.triggerClicks(), 1)
  assert.equal(oracle.root.classList.contains("dropdown-open"), true)
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "true")
  assert.equal(dom.window.document.activeElement, oracle.items()[0])
  assert.ok(oracle.listenerAudit.activeCount() > 0, "open Reka content owns document listeners")

  oracle.trigger.click()
  await flushVue(nextTick)

  assert.equal(oracle.triggerClicks(), 2)
  assert.equal(oracle.root.className, "dropdown dropdown-end")
  assert.equal(oracle.trigger.getAttribute("aria-expanded"), "false")
  assert.equal(dom.window.document.activeElement, oracle.trigger)
  assert.equal(oracle.root.children.length, 2, "close restores the exact raw content branch")
  assert.equal(oracle.items()[0].getAttribute("data-server-item"), "preserved")

  await oracle.cleanup()
})

test(scenarioLedger[1], async () => {
  const oracle = await setup()
  const openEvent = dispatchKey(oracle.trigger, "ArrowDown")
  await flushVue(nextTick)

  assert.equal(openEvent.defaultPrevented, true)
  assert.equal(oracle.root.classList.contains("dropdown-open"), true)
  assert.equal(dom.window.document.activeElement, oracle.items()[0])

  dispatchKey(oracle.items()[0], "ArrowDown")
  assert.equal(dom.window.document.activeElement, oracle.items()[1])
  dispatchKey(oracle.items()[1], "ArrowUp")
  assert.equal(dom.window.document.activeElement, oracle.items()[0])
  dispatchKey(oracle.items()[0], "ArrowUp")
  assert.equal(dom.window.document.activeElement, oracle.items()[2])
  dispatchKey(oracle.items()[2], "ArrowDown")
  assert.equal(dom.window.document.activeElement, oracle.items()[0])
  dispatchKey(oracle.items()[0], "End")
  assert.equal(dom.window.document.activeElement, oracle.items()[2])
  dispatchKey(oracle.items()[2], "Home")
  assert.equal(dom.window.document.activeElement, oracle.items()[0])

  await oracle.cleanup()
})

test(scenarioLedger[2], async () => {
  const oracle = await setup()

  oracle.trigger.click()
  await flushVue(nextTick)
  const escapeEvent = dispatchKey(oracle.items()[0], "Escape")
  await flushVue(nextTick)

  assert.equal(escapeEvent.defaultPrevented, true)
  assert.equal(oracle.root.classList.contains("dropdown-open"), false)
  assert.equal(dom.window.document.activeElement, oracle.trigger)

  oracle.trigger.click()
  await flushVue(nextTick)
  const outsideEvent = new globalThis.PointerEvent("pointerdown", {
    bubbles: true,
    cancelable: true,
    button: 0,
  })
  oracle.outside.dispatchEvent(outsideEvent)
  await flushVue(nextTick)

  assert.equal(oracle.root.classList.contains("dropdown-open"), false)
  assert.equal(dom.window.document.activeElement, oracle.trigger)

  await oracle.cleanup()
})

test(scenarioLedger[3], async () => {
  const oracle = await setup()

  oracle.trigger.click()
  await flushVue(nextTick)
  const firstOpenItem = oracle.items()[0]
  const tabEvent = dispatchKey(firstOpenItem, "Tab")
  await flushVue(nextTick)

  assert.equal(tabEvent.defaultPrevented, false)
  assert.equal(oracle.root.classList.contains("dropdown-open"), false)
  assert.notEqual(dom.window.document.activeElement, oracle.trigger)

  oracle.trigger.click()
  await flushVue(nextTick)
  const secondOpenItem = oracle.items()[1]
  secondOpenItem.click()
  await flushVue(nextTick)

  assert.deepEqual(oracle.activations, ["second-account-item"])
  assert.equal(oracle.root.classList.contains("dropdown-open"), false)
  assert.notEqual(dom.window.document.activeElement, oracle.trigger)

  await oracle.cleanup()
})

test(scenarioLedger[4], async () => {
  const oracle = await setup({auditListeners: true})
  oracle.trigger.click()
  await flushVue(nextTick)

  const retainedRoot = oracle.root
  const retainedTrigger = oracle.trigger
  let unmountFocusCount = 0
  retainedTrigger.focus = () => (unmountFocusCount += 1)
  assert.equal(retainedRoot.classList.contains("dropdown-open"), true)
  assert.ok(oracle.listenerAudit.activeCount() > 0)

  await oracle.cleanup()

  assert.equal(retainedRoot.classList.contains("dropdown-open"), false)
  assert.equal(retainedTrigger.getAttribute("aria-expanded"), "false")
  assert.equal(unmountFocusCount, 0, "unmount never returns focus to a detached trigger")
  assert.equal(oracle.listenerAudit.activeCount(), 0, "Reka removes every tracked document listener")
})

test("closed account components retain native links, forms, parameters, and CSRF fields", async () => {
  const mountAccountComponent = async (component, presentation) => {
    const container = dom.window.document.createElement("div")
    dom.window.document.body.append(container)
    const app = createApp(component, {presentation})
    app.mount(container)
    await flushVue(nextTick)
    return {app, container}
  }

  const notificationsPresentation = {
    root: {class: "dropdown dropdown-end"},
    trigger: {
      class: "notification-trigger",
      attrs: {
        type: "button",
        "data-dropdown-trigger": "",
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": "notifications-runtime-menu",
        "aria-label": "Notifications",
      },
      icon_class: "hero-bell",
      badge: {class: "badge", text: "9+"},
    },
    menu: {
      id: "notifications-runtime-menu",
      class: "dropdown-content menu notifications-panel",
      attrs: {role: "menu", "data-server-menu": "notifications"},
      title: {
        item_class: "menu-title",
        label_class: "hud-label",
        label: "Notifications",
        unread_class: "text-primary",
        unread_label: "(12 unread)",
      },
      empty_state: null,
      notifications: [
        {
          key: "notification-1",
          link: {
            class: "notification-link",
            attrs: {
              href: "/notifications",
              "data-phx-link": "redirect",
              "data-phx-link-state": "push",
            },
          },
          dot_class: "unread-dot",
          content_class: "notification-copy",
          title: {class: "notification-title", text: "Contact window"},
          body: {class: "notification-body", text: "Starts in five minutes"},
        },
      ],
      footer: {
        item_class: "notification-footer",
        class: "notification-footer-link",
        attrs: {
          href: "/notifications",
          "data-phx-link": "redirect",
          "data-phx-link-state": "push",
        },
        label: "See all notifications",
      },
    },
  }

  const notifications = await mountAccountComponent(
    NotificationsBell,
    notificationsPresentation,
  )
  const notificationsRoot = notifications.container.querySelector(".dropdown")
  const notificationsTrigger = notifications.container.querySelector("[data-dropdown-trigger]")
  const notificationsPanel = notifications.container.querySelector("#notifications-runtime-menu")
  const notificationLinks = [...notificationsPanel.querySelectorAll("a")]

  assert.equal(notificationsRoot.className, notificationsPresentation.root.class)
  assert.equal(notificationsRoot.children.length, 2)
  assert.equal(notificationsRoot.children[0], notificationsTrigger)
  assert.equal(notificationsRoot.children[1], notificationsPanel)
  assert.equal(notificationsTrigger.getAttribute("aria-controls"), notificationsPanel.id)
  assert.equal(notificationsTrigger.getAttribute("aria-label"), "Notifications")
  assert.equal(notificationsPanel.getAttribute("data-server-menu"), "notifications")
  assert.equal(notificationsPanel.querySelectorAll("[data-reka-collection-item]").length, 0)
  assert.equal(notificationLinks.length, 2)
  for (const link of notificationLinks) {
    assert.equal(link.getAttribute("href"), "/notifications")
    assert.equal(link.getAttribute("data-phx-link"), "redirect")
    assert.equal(link.getAttribute("data-phx-link-state"), "push")
  }
  assert.match(notificationsPanel.textContent, /Contact window/)
  assert.match(notificationsPanel.textContent, /See all notifications/)

  notifications.app.unmount()
  notifications.container.remove()

  const hiddenField = (name, value) => ({attrs: {type: "hidden", name, value}})
  const userMenuPresentation = {
    root: {class: "dropdown dropdown-end"},
    trigger: {
      class: "user-menu-trigger",
      attrs: {
        type: "button",
        "data-dropdown-trigger": "",
        "aria-haspopup": "menu",
        "aria-expanded": "false",
        "aria-controls": "user-runtime-menu",
      },
      label: {class: "user-label", text: "Mission Operator"},
      icon_class: "hero-chevron-down",
    },
    menu: {
      id: "user-runtime-menu",
      class: "dropdown-content menu user-panel",
      attrs: {role: "menu", "data-server-menu": "user"},
      identity: {
        element: "div",
        class: "identity",
        attrs: {role: "presentation"},
        label: {class: "identity-label", text: "Mission Operator"},
        email: {class: "identity-email", text: "operator@example.test"},
      },
      organization: {
        element: "div",
        class: "organization",
        attrs: {role: "presentation"},
        label: {class: "organization-label", text: "ORGANIZATION"},
        current: {class: "organization-current", text: "Cadence"},
        switcher: {
          class: "organization-switcher",
          summary: {
            class: "organization-summary",
            label_class: "organization-summary-label",
            label: "Cadence",
            icon_class: "hero-chevron-down",
          },
          list_class: "organization-list",
          organizations: [
            {
              key: "organization-2",
              item_attrs: {role: "presentation"},
              label: "Flight Dynamics",
              form: {
                attrs: {action: "/session/organization", method: "post"},
                hidden_fields: [
                  hiddenField("_method", "put"),
                  hiddenField("_csrf_token", "organization-csrf"),
                  hiddenField("organization_id", "organization-2"),
                ],
                button: {
                  class: "organization-button",
                  attrs: {type: "submit", role: "menuitem"},
                  label_class: "organization-button-label",
                  label: "Flight Dynamics",
                },
              },
            },
          ],
        },
      },
      admin_action: {
        item_class: "admin-item",
        item_attrs: {role: "presentation"},
        class: "admin-link",
        attrs: {
          href: "/admin-mode",
          role: "menuitem",
          "data-phx-link": "redirect",
          "data-phx-link-state": "push",
        },
        icon_class: "hero-cog-6-tooth",
        label: "Enter admin mode",
      },
      leave_admin_mode: {
        item_class: "leave-admin-item",
        item_attrs: {role: "presentation"},
        attrs: {action: "/admin-mode", method: "post"},
        hidden_fields: [
          hiddenField("_method", "delete"),
          hiddenField("_csrf_token", "admin-csrf"),
        ],
        button: {
          class: "leave-admin-button",
          attrs: {type: "submit", role: "menuitem"},
          icon_class: "hero-lock-closed",
          label: "Leave admin mode",
        },
      },
      sign_out: {
        item_class: "sign-out-item",
        item_attrs: {role: "presentation"},
        attrs: {action: "/session", method: "post"},
        hidden_fields: [
          hiddenField("_method", "delete"),
          hiddenField("_csrf_token", "session-csrf"),
        ],
        button: {
          class: "sign-out-button",
          attrs: {type: "submit", role: "menuitem"},
          icon_class: "hero-arrow-right-start-on-rectangle",
          label: "Sign out",
        },
      },
    },
  }

  const userMenu = await mountAccountComponent(UserMenu, userMenuPresentation)
  const userRoot = userMenu.container.querySelector(".dropdown")
  const userTrigger = userMenu.container.querySelector("[data-dropdown-trigger]")
  const userPanel = userMenu.container.querySelector("#user-runtime-menu")
  const forms = [...userPanel.querySelectorAll("form")]
  const formContract = (form) => ({
    action: form.getAttribute("action"),
    method: form.getAttribute("method"),
    fields: [...form.querySelectorAll("input")].map((input) => ({
      type: input.getAttribute("type"),
      name: input.getAttribute("name"),
      value: input.getAttribute("value"),
    })),
  })
  const closedFormContracts = forms.map(formContract)

  assert.equal(userRoot.className, userMenuPresentation.root.class)
  assert.equal(userRoot.children.length, 2)
  assert.equal(userRoot.children[0], userTrigger)
  assert.equal(userRoot.children[1], userPanel)
  assert.equal(userTrigger.getAttribute("aria-controls"), userPanel.id)
  assert.equal(userPanel.querySelectorAll("[data-reka-collection-item]").length, 0)
  assert.equal(forms.length, 3)
  assert.deepEqual(closedFormContracts, [
    {
      action: "/session/organization",
      method: "post",
      fields: [
        {type: "hidden", name: "_method", value: "put"},
        {type: "hidden", name: "_csrf_token", value: "organization-csrf"},
        {type: "hidden", name: "organization_id", value: "organization-2"},
      ],
    },
    {
      action: "/admin-mode",
      method: "post",
      fields: [
        {type: "hidden", name: "_method", value: "delete"},
        {type: "hidden", name: "_csrf_token", value: "admin-csrf"},
      ],
    },
    {
      action: "/session",
      method: "post",
      fields: [
        {type: "hidden", name: "_method", value: "delete"},
        {type: "hidden", name: "_csrf_token", value: "session-csrf"},
      ],
    },
  ])
  assert.equal(userPanel.querySelector("a.admin-link").getAttribute("href"), "/admin-mode")
  assert.equal(userPanel.querySelector("a.admin-link").getAttribute("data-phx-link"), "redirect")
  assert.match(userPanel.textContent, /Mission Operator/)
  assert.match(userPanel.textContent, /ORGANIZATION/)
  assert.match(userPanel.textContent, /Sign out/)

  userTrigger.click()
  await flushVue(nextTick)
  assert.equal(userRoot.classList.contains("dropdown-open"), true)
  assert.deepEqual([...userPanel.querySelectorAll("form")].map(formContract), closedFormContracts)

  userMenu.app.unmount()
  userMenu.container.remove()
})

test.after(() => dom.window.close())

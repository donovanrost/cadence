import assert from "node:assert/strict"
import {existsSync, readFileSync} from "node:fs"
import {readFile} from "node:fs/promises"
import {dirname, extname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  assertPinnedAdapterRuntime,
  flushVue,
  installDom,
  integrationNodeModules,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the actual DashboardCanvas and DashboardGrid SFCs load the real CadenceCollapsible graph",
  "caller-owned DIV BUTTON and DIV.contents nodes retain exact identity order attrs and children",
  "unseen keys use their open and closed server seeds with exact adapter state and IDREFs",
  "button interaction updates keyed disclosure state on the next Vue patch",
  "same-key complete presentation replacement preserves local state and mounted grid identity",
  "a genuinely new key uses its own server seed",
  "close-to-open schedules one post-patch resize and clears prevWidth before onResize",
  "group removal destroys its one GridStack instance exactly once with destroy(false)",
  "layout_changed forwards the exact GridStack payload through DashboardGrid and DashboardCanvas",
])
const browserGates = Object.freeze([
  "BROWSER GATE: Enter, Space, and focus behavior require real-browser verification",
  "BROWSER GATE: hidden/open layout, sticky trigger, and chevron animation require real-browser verification",
  "BROWSER GATE: GridStack geometry, drag, and resize after reopen require real-browser verification",
])

assert.equal(scenarios.length, 9)
assert.equal(browserGates.length, 3)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const packageLockPath = resolve(testDirectory, "../../package-lock.json")
const vueRoot = resolve(testDirectory, "../vue")
const componentPaths = Object.freeze({
  canvas: resolve(vueRoot, "DashboardCanvas.vue"),
  grid: resolve(vueRoot, "DashboardGrid.vue"),
  root: resolve(vueRoot, "ui/reka/CadenceCollapsible.vue"),
  trigger: resolve(vueRoot, "ui/reka/CadenceCollapsibleTrigger.vue"),
  content: resolve(vueRoot, "ui/reka/CadenceCollapsibleContent.vue"),
})

await assertPinnedAdapterRuntime(packageLockPath)
const dom = installDom('<div id="app"></div>')
Object.defineProperty(globalThis, "devicePixelRatio", {
  configurable: true,
  value: dom.window.devicePixelRatio,
})
Object.defineProperty(globalThis, "matchMedia", {
  configurable: true,
  value: (media) => ({
    media,
    matches: false,
    addEventListener() {},
    removeEventListener() {},
  }),
})

const gridRecords = []
const FakeGridStack = {
  init(options, element) {
    const widgetId = element.getAttribute("data-fixture-widget-id")
    const widgetElement = element.querySelector(`:scope > [gs-id="${widgetId}"]`)
    assert.ok(widgetElement, `${widgetId} is a direct native grid child`)
    widgetElement.gridstackNode = {el: widgetElement}
    const record = {
      element,
      widgetElement,
      options,
      destroyCalls: [],
      resizePrevWidths: [],
      eventHandlers: new Map(),
    }
    const grid = {
      engine: {
        nodes: [{el: widgetElement, x: 2, y: 3, w: 4, h: 5}],
      },
      opts: {staticGrid: options.staticGrid},
      prevWidth: 960,
      on(events, callback) {
        record.eventHandlers.set(events, callback)
      },
      setStatic(value) {
        this.opts.staticGrid = value
      },
      float() {},
      makeWidget(nextWidgetElement) {
        nextWidgetElement.gridstackNode = {el: nextWidgetElement}
      },
      movable() {},
      resizable() {},
      removeWidget() {},
      onResize() {
        record.resizePrevWidths.push(this.prevWidth)
      },
      destroy(removeDom) {
        record.destroyCalls.push(removeDom)
      },
    }
    record.grid = grid
    gridRecords.push(record)
    return grid
  },
}

const localModuleCache = new Map()
const loadedLocalModules = new Set()
const loadLocalModule = (modulePath) => {
  if (localModuleCache.has(modulePath)) return localModuleCache.get(modulePath).exports

  const loadedModule = {exports: {}}
  localModuleCache.set(modulePath, loadedModule)
  loadedLocalModules.add(modulePath)
  const {transformSync} = integrationRequire("esbuild")
  let moduleSource = readFileSync(modulePath, "utf8")
  let loader = extname(modulePath) === ".ts" ? "ts" : "js"

  if (extname(modulePath) === ".vue") {
    const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
    const parsed = parse(moduleSource, {filename: modulePath})
    assert.deepEqual(parsed.errors, [], `${modulePath} parses with the pinned Vue compiler`)
    moduleSource = compileScript(parsed.descriptor, {
      id: `dashboard-canvas-disclosure-${modulePath.split("/").at(-1)}`,
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
  const evaluate = new Function("require", "module", "exports", transformed.code)
  evaluate(moduleRequire(modulePath), loadedModule, loadedModule.exports)
  return loadedModule.exports
}
const moduleRequire = (fromPath) => (specifier) => {
  if (specifier.startsWith(".")) {
    let resolvedPath = resolve(dirname(fromPath), specifier)
    if (resolvedPath.endsWith("/vendor/gridstack/gridstack-all")) return FakeGridStack
    if (!existsSync(resolvedPath) && extname(resolvedPath) === ".js") {
      resolvedPath = `${resolvedPath.slice(0, -3)}.ts`
    }
    if (!existsSync(resolvedPath) && existsSync(`${resolvedPath}.js`)) {
      resolvedPath = `${resolvedPath}.js`
    }
    if (!existsSync(resolvedPath) && existsSync(`${resolvedPath}.ts`)) {
      resolvedPath = `${resolvedPath}.ts`
    }
    return loadLocalModule(resolvedPath)
  }

  if (specifier === "live_vue") {
    return loadLocalModule(resolve(integrationNodeModules, "live_vue/assets/index.ts"))
  }

  return integrationRequire(specifier)
}

const [canvasSource, gridSource] = await Promise.all([
  readFile(componentPaths.canvas, "utf8"),
  readFile(componentPaths.grid, "utf8"),
])
const DashboardCanvas = loadLocalModule(componentPaths.canvas).default

for (const componentPath of Object.values(componentPaths)) {
  assert.equal(loadedLocalModules.has(componentPath), true, `${componentPath} loads as actual source`)
}
assert.match(canvasSource, /const sectionOpenByKey = reactive\(new Map\(\)\)/)
assert.doesNotMatch(canvasSource, /<details(?:\s|>)|<summary(?:\s|>)/)
assert.doesNotMatch(gridSource, /closest\(|addEventListener\("toggle"|sectionDetails/)

const widgetPresentation = (key) => ({
  component_id: `dashboard-widget-${key}-component`,
  header: {
    component_id: `dashboard-widget-${key}-header-component`,
    root: {class: "widget-header-exact", attrs: {}},
    title: {class: "widget-title-exact", text: `${key} widget`},
    status_indicators: {
      class: "widget-indicators-exact",
      attrs: {},
      limit: null,
      comparison: null,
      quality: null,
      lifecycle: null,
    },
    actions: {
      class: "widget-actions-exact",
      details: {
        overlay: {
          id: `dashboard-widget-${key}-details-overlay`,
          class: "widget-details-overlay-exact",
          attrs: {},
        },
        trigger: {
          id: `dashboard-widget-${key}-details-trigger`,
          type: "button",
          class: "widget-details-trigger-exact",
          attrs: {"aria-label": "Widget details"},
          content: {
            class: "widget-details-trigger-content-exact",
            attrs: {},
            icon: {name: "hero-ellipsis-horizontal", class: "widget-details-icon-exact"},
          },
        },
        panel: {
          id: `dashboard-widget-${key}-details-panel`,
          class: "widget-details-panel-exact",
          hidden: true,
          attrs: {},
        },
        body: {
          class: "widget-details-body-exact",
          heading: {
            class: "widget-details-heading-exact",
            title: {class: "widget-details-title-exact", text: "Details"},
            binding: {class: "widget-details-binding-exact", text: key},
          },
          indicators: {
            class: "widget-details-indicators-exact",
            attrs: {},
            lifecycle: null,
            source: null,
            data_management: [],
            warnings: [],
          },
          actions: {
            class: "widget-details-actions-exact",
            attrs: {},
            query: null,
            frame_evidence: null,
            data_links: null,
            inspector: null,
          },
        },
      },
      edit: [],
    },
  },
  body: {
    root: {class: "widget-body-exact", attrs: {}},
    notice: null,
    content: null,
  },
})
const sectionGroup = ({
  key,
  open,
  title,
  description,
  summaryVersion = "initial",
}) => {
  const sectionId = `dashboard-section-group-${key}`
  const gridId = `dashboard-grid-${key}`
  return {
    key,
    root: {
      attrs: {
        id: `dashboard-widget-group-${key}`,
        class: "widget-group-exact",
        "data-dashboard-widget-group": key,
      },
    },
    section: {
      root: {
        attrs: {
          id: sectionId,
          ...(open ? {open: ""} : {}),
          class: "group/dashboard-section",
          "data-dashboard-section": key,
        },
      },
      summary: {
        attrs: {
          id: `${sectionId}-trigger`,
          class: "summary-exact sticky top-0",
          "data-summary-version": summaryVersion,
          "aria-label": `${title} disclosure`,
        },
        icon: {
          attrs: {
            id: `${sectionId}-icon`,
            class:
              "hero-chevron-right transition-transform group-data-[state=open]/dashboard-section:rotate-90",
            "aria-hidden": "true",
          },
        },
        copy: {
          attrs: {id: `${sectionId}-copy`, class: "copy-exact"},
          title: {
            attrs: {id: `${sectionId}-title`, class: "title-exact"},
            text: title,
          },
          description: {
            attrs: {id: `${sectionId}-description`, class: "description-exact"},
            text: description,
          },
        },
        count: {
          attrs: {id: `${sectionId}-count`, class: "count-exact"},
          text: "1 widget",
        },
      },
    },
    header: null,
    grid: {
      root: {
        attrs: {
          id: gridId,
          class: "grid-stack gs-12",
          "data-dashboard-grid": "true",
          "data-fixture-widget-id": `placement-${key}`,
        },
      },
      widgets: [
        {
          key: `placement-${key}`,
          shell: {
            attrs: {
              class: "grid-stack-item",
              "gs-id": `placement-${key}`,
              "gs-x": "2",
              "gs-y": "3",
              "gs-w": "4",
              "gs-h": "5",
            },
          },
          content: {attrs: {class: "grid-stack-item-content widget-content-exact"}},
          host: {
            attrs: {id: `dashboard-widget-${key}-component`, class: "contents"},
          },
          presentation: widgetPresentation(key),
        },
      ],
      controller: {
        host: {attrs: {id: `${gridId}-controller`, class: "hidden"}},
        props: {
          target_id: gridId,
          edit_mode: true,
          item_ids: [`placement-${key}`],
        },
      },
    },
  }
}
const canvasPresentation = (groups, label) => ({
  root: {attrs: {id: "dashboard-canvas", class: "canvas-exact", "data-version": label}},
  content: {attrs: {id: "dashboard-canvas-content", class: "content-exact"}},
  groups,
  empty_state: null,
  comparison_inspector: null,
})

const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")
const presentations = ref(
  canvasPresentation(
    [
      sectionGroup({
        key: "power",
        open: true,
        title: "Power",
        description: "Bus health",
      }),
      sectionGroup({
        key: "comms",
        open: false,
        title: "Comms",
        description: "Link health",
      }),
    ],
    "initial",
  ),
)
const layoutPayloads = []
const DashboardCanvasOracle = defineComponent({
  name: "DashboardCanvasSectionDisclosuresReconciliationOracle",
  setup() {
    return () =>
      h(DashboardCanvas, {
        presentation: presentations.value,
        onLayout_changed: (payload) => layoutPayloads.push(payload),
      })
  },
})

const app = createApp(DashboardCanvasOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const document = dom.window.document
const sectionElements = (key) => ({
  root: document.querySelector(`#dashboard-section-group-${key}`),
  trigger: document.querySelector(`#dashboard-section-group-${key}-trigger`),
  content: document.querySelector(`#dashboard-section-group-${key}-content`),
  grid: document.querySelector(`#dashboard-grid-${key}`),
})
const assertSectionState = (elements, open) => {
  const state = open ? "open" : "closed"
  assert.equal(elements.root.getAttribute("data-state"), state)
  assert.equal(elements.trigger.getAttribute("data-state"), state)
  assert.equal(elements.content.getAttribute("data-state"), state)
  assert.equal(elements.trigger.getAttribute("aria-expanded"), String(open))
  assert.equal(elements.trigger.getAttribute("aria-controls"), elements.content.id)
  assert.equal(elements.content.hasAttribute("hidden"), !open)
}
const assertExactSectionShell = (key, elements, title, description) => {
  assert.ok(elements.root instanceof dom.window.HTMLDivElement)
  assert.ok(elements.trigger instanceof dom.window.HTMLButtonElement)
  assert.ok(elements.content instanceof dom.window.HTMLDivElement)
  assert.equal(elements.root.id, `dashboard-section-group-${key}`)
  assert.equal(elements.root.className, "group/dashboard-section")
  assert.equal(elements.root.getAttribute("data-dashboard-section"), key)
  assert.equal(elements.root.hasAttribute("open"), false)
  assert.equal(elements.trigger.type, "button")
  assert.equal(elements.trigger.className, "summary-exact sticky top-0")
  assert.equal(elements.trigger.getAttribute("data-summary-version"), "initial")
  assert.equal(elements.trigger.getAttribute("aria-label"), `${title} disclosure`)
  assert.equal(elements.content.className, "contents")
  assert.deepEqual([...elements.root.children].map((child) => child.tagName), ["BUTTON", "DIV"])
  assert.deepEqual([...elements.trigger.children].map((child) => child.tagName), [
    "SPAN",
    "DIV",
    "SPAN",
  ])
  assert.equal(elements.trigger.children[0].id, `dashboard-section-group-${key}-icon`)
  assert.equal(
    elements.trigger.children[0].className,
    "hero-chevron-right transition-transform group-data-[state=open]/dashboard-section:rotate-90",
  )
  assert.equal(elements.trigger.children[0].getAttribute("aria-hidden"), "true")
  assert.equal(elements.trigger.children[1].id, `dashboard-section-group-${key}-copy`)
  assert.equal(elements.trigger.children[1].className, "copy-exact")
  assert.equal(elements.trigger.children[2].id, `dashboard-section-group-${key}-count`)
  assert.equal(elements.trigger.children[2].className, "count-exact")
  assert.equal(elements.trigger.querySelector("h2").textContent, title)
  assert.equal(elements.trigger.querySelector("h2").className, "title-exact")
  assert.equal(elements.trigger.querySelector("p").textContent, description)
  assert.equal(elements.trigger.querySelector("p").className, "description-exact")
  assert.equal(elements.trigger.children[2].textContent, "1 widget")
  assert.equal(elements.content.firstElementChild, elements.grid)
  assert.deepEqual([...elements.content.children].map((child) => child.id), [
    `dashboard-grid-${key}`,
    `dashboard-grid-${key}-controller`,
  ])
}

const power = sectionElements("power")
const comms = sectionElements("comms")
assertExactSectionShell("power", power, "Power", "Bus health")
assertExactSectionShell("comms", comms, "Comms", "Link health")
assertSectionState(power, true)
assertSectionState(comms, false)
assert.equal(gridRecords.length, 2)
const powerGridRecord = gridRecords.find(({element}) => element.id === "dashboard-grid-power")
assert.ok(powerGridRecord)
assert.equal(powerGridRecord.destroyCalls.length, 0)
const powerWidget = powerGridRecord.widgetElement
const powerWidgetHost = document.querySelector("#dashboard-widget-power-component")
assert.equal(powerWidget.parentElement, power.grid)
assert.equal(powerWidgetHost.parentElement.parentElement, powerWidget)

power.trigger.click()
await nextTick()
assert.equal(power.root.getAttribute("data-state"), "closed")
assert.equal(power.trigger.getAttribute("aria-expanded"), "false")
await flushVue(nextTick)
assertSectionState(power, false)
assert.deepEqual(powerGridRecord.resizePrevWidths, [], "close does not resize")

presentations.value = canvasPresentation(
  [
    sectionGroup({
      key: "power",
      open: true,
      title: "Power replacement",
      description: "Replacement bus health",
      summaryVersion: "replacement",
    }),
    sectionGroup({
      key: "comms",
      open: true,
      title: "Comms replacement",
      description: "Replacement link health",
      summaryVersion: "replacement",
    }),
  ],
  "same-key-replacement",
)
await flushVue(nextTick)

assert.equal(document.querySelector("#dashboard-canvas").getAttribute("data-version"), "same-key-replacement")
assert.equal(sectionElements("power").root, power.root)
assert.equal(sectionElements("power").trigger, power.trigger)
assert.equal(sectionElements("power").content, power.content)
assert.equal(sectionElements("power").grid, power.grid)
assert.equal(document.querySelector('#dashboard-grid-power > [gs-id="placement-power"]'), powerWidget)
assert.equal(document.querySelector("#dashboard-widget-power-component"), powerWidgetHost)
assert.equal(power.trigger.getAttribute("data-summary-version"), "replacement")
assert.equal(power.trigger.querySelector("h2").textContent, "Power replacement")
assert.equal(power.trigger.querySelector("p").textContent, "Replacement bus health")
assertSectionState(power, false)
assertSectionState(comms, false)
assert.equal(gridRecords.length, 2, "same-key replacement does not initialize GridStack again")
assert.equal(powerGridRecord.destroyCalls.length, 0)

powerGridRecord.grid.prevWidth = 720
power.trigger.click()
await flushVue(nextTick)
assertSectionState(power, true)
assert.deepEqual(powerGridRecord.resizePrevWidths, [undefined])
assert.equal(sectionElements("power").grid, power.grid)
assert.equal(document.querySelector('#dashboard-grid-power > [gs-id="placement-power"]'), powerWidget)
assert.equal(document.querySelector("#dashboard-widget-power-component"), powerWidgetHost)
assert.equal(gridRecords.length, 2)
assert.equal(powerGridRecord.destroyCalls.length, 0)

powerGridRecord.eventHandlers.get("change")()
await new Promise((resolvePromise) => setTimeout(resolvePromise, 425))
assert.deepEqual(layoutPayloads, [
  {
    layouts: [
      {
        widget_id: "placement-power",
        x: 2,
        y: 3,
        w: 4,
        h: 5,
      },
    ],
  },
])

presentations.value = canvasPresentation(
  [
    ...presentations.value.groups,
    sectionGroup({
      key: "thermal",
      open: true,
      title: "Thermal",
      description: "Temperature health",
    }),
  ],
  "new-key",
)
await flushVue(nextTick)
const thermal = sectionElements("thermal")
assertExactSectionShell("thermal", thermal, "Thermal", "Temperature health")
assertSectionState(thermal, true)
assert.equal(gridRecords.length, 3)

presentations.value = canvasPresentation(
  presentations.value.groups.filter((group) => group.key !== "power"),
  "power-removed",
)
await flushVue(nextTick)
assert.equal(document.querySelector("#dashboard-section-group-power"), null)
assert.deepEqual(powerGridRecord.destroyCalls, [false])
assert.equal(gridRecords.length, 3)

app.unmount()
assert.deepEqual(powerGridRecord.destroyCalls, [false], "removed group stays destroyed exactly once")
dom.window.close()

console.log(
  `dashboard_canvas_section_disclosures_reconciliation_test passed (${scenarios.length} scenarios; ` +
    `${browserGates.length} explicit browser gates; JSDOM only)`,
)

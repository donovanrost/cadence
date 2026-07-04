import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))

async function loadHook(path, replacements = [], context = {}) {
  const source = await readFile(path, "utf8")
  const testableSource = replacements.reduce(
    (nextSource, [from, to]) => nextSource.replace(from, to),
    source
  )

  const vmContext = {
    console,
    URL,
    setTimeout: () => 1,
    clearTimeout: () => {},
    ...context,
  }

  vm.createContext(vmContext)
  vm.runInContext(testableSource, vmContext, { filename: path })
  return vmContext
}

function classList(...initialClasses) {
  const classes = new Set(initialClasses)

  return {
    add: (...names) => names.forEach((name) => classes.add(name)),
    remove: (...names) => names.forEach((name) => classes.delete(name)),
    contains: (name) => classes.has(name),
    toggle: (name, force) => {
      const want = force === undefined ? !classes.has(name) : Boolean(force)
      if (want) classes.add(name)
      else classes.delete(name)
      return want
    },
    values: () => Array.from(classes),
  }
}

{
  const clipboardPath = resolve(__dirname, "../js/hooks/clipboard_button.js")
  const context = await loadHook(
    clipboardPath,
    [["export default ClipboardButton", "globalThis.ClipboardButton = ClipboardButton"]],
    {
      navigator: {
        clipboard: {
          writeText: async (text) => {
            context.copiedText = text
          },
        },
      },
      window: {
        location: {
          origin: "https://cadence.test",
          pathname: "/ops/dashboards/alpha",
          search: "?scope=mission-1",
        },
      },
    }
  )

  const el = {
    dataset: { clipboardText: "/ops/dashboards/alpha?selected=data-link-1" },
    addEventListener(type, listener) {
      this.listenerType = type
      this.listener = listener
    },
    removeEventListener(type, listener) {
      this.removedType = type
      this.removedListener = listener
    },
  }

  const hook = Object.assign(Object.create(context.ClipboardButton), { el })
  hook.mounted()
  assert.equal(el.listenerType, "click")

  await el.listener()

  assert.equal(
    context.copiedText,
    "https://cadence.test/ops/dashboards/alpha?selected=data-link-1"
  )
  assert.equal(el.dataset.clipboardCopied, "true")

  hook.destroyed()
  assert.equal(el.removedType, "click")
  assert.equal(el.removedListener, el.listener)
}

{
  const clipboardPath = resolve(__dirname, "../js/hooks/clipboard_button.js")
  const appended = []
  const context = await loadHook(
    clipboardPath,
    [["export default ClipboardButton", "globalThis.ClipboardButton = ClipboardButton"]],
    {
      navigator: {
        clipboard: {
          writeText: async () => {
            throw new Error("clipboard unavailable")
          },
        },
      },
      window: {
        location: {
          origin: "https://cadence.test",
          pathname: "/ops/dashboards/beta",
          search: "?selected=data-link-2",
        },
      },
      document: {
        body: {
          appendChild: (node) => appended.push(node),
        },
        createElement: () => ({
          style: {},
          setAttribute(name, value) {
            this[name] = value
          },
          select() {
            this.selected = true
          },
          remove() {
            this.removed = true
          },
        }),
        execCommand: (command) => {
          context.execCommand = command
          return true
        },
      },
    }
  )

  const el = {
    dataset: {},
    addEventListener() {},
    removeEventListener() {},
  }

  const hook = Object.assign(Object.create(context.ClipboardButton), { el })
  await hook.copy()

  assert.equal(appended.length, 1)
  assert.equal(appended[0].value, "https://cadence.test/ops/dashboards/beta?selected=data-link-2")
  assert.equal(appended[0].readonly, "readonly")
  assert.equal(appended[0].selected, true)
  assert.equal(appended[0].removed, true)
  assert.equal(context.execCommand, "copy")
  assert.equal(el.dataset.clipboardCopied, "true")
}

{
  const gridPath = resolve(__dirname, "../js/hooks/dashboard_grid.js")
  const gridCalls = []
  const connectedNode = {
    x: 2,
    y: 3,
    w: 4,
    h: 5,
    el: {
      isConnected: true,
      getAttribute: (name) => (name === "gs-id" ? "widget-alpha" : null),
    },
  }
  const disconnectedNode = { el: { isConnected: false, classList: classList() } }

  const fakeGrid = {
    engine: { nodes: [connectedNode, disconnectedNode] },
    opts: { staticGrid: true },
    float(value) {
      gridCalls.push(["float", value])
    },
    on(event, handler) {
      gridCalls.push(["on", event])
      this.changeHandler = handler
    },
    setStatic(value) {
      gridCalls.push(["setStatic", value])
      this.opts.staticGrid = value
      if (value) {
        gridElement.classList.add("grid-stack-static")
      } else {
        gridElement.classList.remove("grid-stack-static")
      }
    },
    makeWidget(el) {
      gridCalls.push(["makeWidget", el.id])
      el.gridstackNode = { el }
    },
    movable(el, value) {
      gridCalls.push(["movable", el.id, value])
    },
    resizable(el, value) {
      gridCalls.push(["resizable", el.id, value])
    },
    removeWidget(_el, removeDom, triggerEvent) {
      gridCalls.push(["removeWidget", removeDom, triggerEvent])
    },
    destroy(removeDom) {
      gridCalls.push(["destroy", removeDom])
    },
  }

  const gridElement = {
    dataset: { editMode: "false" },
    classList: classList("grid-stack-static"),
    querySelector(selector) {
      assert.equal(selector, ".ui-draggable-dragging, .ui-resizable-resizing")
      return null
    },
    querySelectorAll(selector) {
      assert.equal(selector, ":scope > .grid-stack-item")
      return [
        {
          id: "widget-new",
          classList: classList("grid-stack-item"),
        },
        {
          id: "widget-existing",
          gridstackNode: { el: null },
          classList: classList("grid-stack-item"),
        },
      ]
    },
  }

  const context = await loadHook(
    gridPath,
    [[
      'import GridStack from "../../vendor/gridstack/gridstack-all"\n',
      "const GridStack = globalThis.GridStack\n",
    ], ["export default DashboardGrid", "globalThis.DashboardGrid = DashboardGrid"]],
    {
      GridStack: {
        init(options, el) {
          gridCalls.push(["init", options.staticGrid, options.resizable.handles, el === gridElement])
          return fakeGrid
        },
      },
    }
  )

  const pushedEvents = []
  const hook = Object.assign(Object.create(context.DashboardGrid), {
    el: gridElement,
    pushEvent: (event, payload) => pushedEvents.push([event, payload]),
  })

  hook.mounted()

  assert.deepEqual(gridCalls.slice(0, 2), [
    ["init", true, "e, se, s", true],
    ["on", "change"],
  ])

  gridElement.dataset.editMode = "true"
  hook.updated()

  assert.deepEqual(gridCalls.slice(2, 6), [
    ["makeWidget", "widget-new"],
    ["movable", "widget-existing", true],
    ["resizable", "widget-existing", true],
    ["removeWidget", false, false],
  ])
  // Entering edit lifts static mode and switches to float(false) so
  // neighbors reflow classically while the operator rearranges.
  assert.deepEqual(gridCalls.slice(6, 8), [
    ["setStatic", false],
    ["float", false],
  ])

  hook.flushLayout()

  assert.deepEqual(JSON.parse(JSON.stringify(pushedEvents)), [
    [
      "layout_changed",
      {
        layouts: [
          {
            widget_id: "widget-alpha",
            x: 2,
            y: 3,
            w: 4,
            h: 5,
          },
        ],
      },
    ],
  ])

  gridElement.dataset.editMode = "false"
  hook.updated()

  // Exiting edit restores float(true) before re-freezing the grid so view
  // mode keeps the server's exact gs-* positions.
  assert.deepEqual(gridCalls.slice(-2), [
    ["float", true],
    ["setStatic", true],
  ])

  hook.destroyed()
  assert.deepEqual(gridCalls.at(-1), ["destroy", false])
}

console.log("dashboard_hooks_smoke_test passed")

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

{
  const editorGuardPath = resolve(__dirname, "../js/hooks/dashboard_editor_guard.js")
  const windowListeners = new Map()
  const documentListeners = new Map()
  let confirmResult = false

  const context = await loadHook(
    editorGuardPath,
    [["export default DashboardEditorGuard", "globalThis.DashboardEditorGuard = DashboardEditorGuard"]],
    {
      window: {
        addEventListener: (type, listener) => windowListeners.set(type, listener),
        removeEventListener: (type, listener) => {
          assert.equal(windowListeners.get(type), listener)
          windowListeners.delete(type)
        },
        confirm: () => confirmResult,
      },
      document: {
        addEventListener: (type, listener, capture) => {
          assert.equal(capture, true)
          documentListeners.set(type, listener)
        },
        removeEventListener: (type, listener, capture) => {
          assert.equal(capture, true)
          assert.equal(documentListeners.get(type), listener)
          documentListeners.delete(type)
        },
      },
    }
  )

  const el = {dataset: {editorDirty: "false"}}
  const hook = Object.assign(Object.create(context.DashboardEditorGuard), {el})
  hook.mounted()

  const cleanUnload = {preventDefault() { this.prevented = true }}
  windowListeners.get("beforeunload")(cleanUnload)
  assert.equal(cleanUnload.prevented, undefined)

  el.dataset.editorDirty = "true"
  const dirtyUnload = {preventDefault() { this.prevented = true }}
  windowListeners.get("beforeunload")(dirtyUnload)
  assert.equal(dirtyUnload.prevented, true)
  assert.equal(dirtyUnload.returnValue, "")

  const anchor = {
    target: "",
    hasAttribute: () => false,
  }
  const click = {
    target: {closest: (selector) => (selector === "a[href]" ? anchor : null)},
    preventDefault() { this.prevented = true },
    stopImmediatePropagation() { this.stopped = true },
  }

  documentListeners.get("click")(click)
  assert.equal(click.prevented, true)
  assert.equal(click.stopped, true)

  confirmResult = true
  const confirmedClick = {
    target: {closest: () => anchor},
    preventDefault() { this.prevented = true },
    stopImmediatePropagation() { this.stopped = true },
  }
  documentListeners.get("click")(confirmedClick)
  assert.equal(confirmedClick.prevented, undefined)

  hook.destroyed()
  assert.equal(windowListeners.size, 0)
  assert.equal(documentListeners.size, 0)
}

{
  const recentsPath = resolve(__dirname, "../js/hooks/time_range_recents.js")
  const storage = new Map()
  const context = await loadHook(
    recentsPath,
    [["export default {", "globalThis.TimeRangeRecents = {"]],
    {
      localStorage: {
        getItem: (key) => (storage.has(key) ? storage.get(key) : null),
        setItem: (key, value) => storage.set(key, value),
      },
    }
  )

  const makeHook = () => {
    const events = []
    const handlers = new Map()
    const hook = Object.assign(Object.create(context.TimeRangeRecents), {
      pushEvent: (name, payload) => events.push({name, payload}),
      handleEvent: (name, handler) => handlers.set(name, handler),
    })
    return {hook, events, handlers}
  }

  // First mount: nothing stored yet -> pushes an empty list.
  const first = makeHook()
  first.hook.mounted()

  assert.equal(
    JSON.stringify(first.events),
    JSON.stringify([{name: "time_recents_loaded", payload: {ranges: []}}])
  )

  // Applying an absolute range stores it, dedupes, and caps at four entries.
  const store = first.handlers.get("cadence:store-time-recent")
  store({from: "2026-08-01T10:00:00Z", to: "2026-08-01T12:00:00Z"})
  store({from: "2026-08-01T13:00:00Z", to: "2026-08-01T14:00:00Z"})
  store({from: "2026-08-01T10:00:00Z", to: "2026-08-01T12:00:00Z"})
  store({from: "2026-08-01T15:00:00Z", to: "2026-08-01T16:00:00Z"})
  store({from: "2026-08-01T17:00:00Z", to: "2026-08-01T18:00:00Z"})
  store({from: "2026-08-01T19:00:00Z", to: "2026-08-01T20:00:00Z"})

  const lastPush = first.events.at(-1)
  assert.equal(lastPush.name, "time_recents_loaded")
  assert.equal(
    lastPush.payload.ranges.map((range) => range.from).join(","),
    [
      "2026-08-01T19:00:00Z",
      "2026-08-01T17:00:00Z",
      "2026-08-01T15:00:00Z",
      "2026-08-01T10:00:00Z",
    ].join(",")
  )

  // Remount (fresh session): stored ranges hydrate the pushed list.
  const second = makeHook()
  second.hook.mounted()
  assert.equal(second.events[0].payload.ranges.length, 4)
  assert.equal(second.events[0].payload.ranges[0].from, "2026-08-01T19:00:00Z")

  // Corrupt storage degrades to an empty list instead of throwing.
  storage.set("cadence:dashboard-time-recents", "{not json")
  const third = makeHook()
  third.hook.mounted()
  assert.equal(third.events[0].payload.ranges.length, 0)

  // Malformed pushes are ignored.
  const before = first.events.length
  store({from: 42, to: "2026-08-01T20:00:00Z"})
  assert.equal(first.events.length, before)
}

console.log("dashboard_hooks_smoke_test passed")

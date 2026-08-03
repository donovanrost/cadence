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

{
  const csvPath = resolve(__dirname, "../js/hooks/csv_download.js")
  const created = []
  let revokedUrl = null
  const context = await loadHook(
    csvPath,
    [["export default {", "globalThis.CsvDownload = {"]],
    {
      Blob: class {
        constructor(parts, options) {
          this.content = parts.join("")
          this.type = options?.type
        }
      },
      URL: {
        createObjectURL: (blob) => `blob:${blob.content.length}`,
        revokeObjectURL: (url) => {
          revokedUrl = url
        },
      },
      document: {
        createElement: (tag) => {
          const anchor = {tag, clicked: false, click() { this.clicked = true }}
          created.push(anchor)
          return anchor
        },
      },
    }
  )

  const listeners = new Map()
  const el = {
    dataset: {csv: "time_utc,volts\r\n2026-08-01T10:00:00Z,1.5", filename: "trend-inspect.csv"},
    addEventListener: (type, listener) => listeners.set(type, listener),
    removeEventListener: (type, listener) => {
      assert.equal(listeners.get(type), listener)
      listeners.delete(type)
    },
  }

  const hook = Object.assign(Object.create(context.CsvDownload), {el})
  hook.mounted()

  listeners.get("click")()

  assert.equal(created.length, 1)
  assert.equal(created[0].tag, "a")
  assert.equal(created[0].download, "trend-inspect.csv")
  assert.equal(created[0].clicked, true)
  assert.equal(created[0].href, `blob:${el.dataset.csv.length}`)
  assert.equal(revokedUrl, created[0].href)

  // Missing payload degrades to an empty file with the default name.
  el.dataset.csv = undefined
  el.dataset.filename = undefined
  listeners.get("click")()
  assert.equal(created[1].download, "widget-data.csv")
  assert.equal(created[1].href, "blob:0")

  hook.destroyed()
  assert.equal(listeners.size, 0)
}

console.log("dashboard_hooks_smoke_test passed")

import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))

async function loadControllerSfc(path, replacements = [], context = {}, exposure = "") {
  const source = await readFile(path, "utf8")
  const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
  const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

  assert.ok(script, `${path} must have a script setup block`)
  assert.ok(template, `${path} must have a template block`)

  const testableSource = replacements.reduce(
    (nextSource, [from, to]) => nextSource.replace(from, to),
    script
  ) + exposure

  const vmContext = {
    console,
    URL,
    setTimeout: () => 1,
    clearTimeout: () => {},
    ...context,
  }

  vm.createContext(vmContext)
  vm.runInContext(testableSource, vmContext, { filename: path })
  return {...vmContext, template}
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
  const gridPath = resolve(__dirname, "../vue/DashboardGrid.vue")
  const gridCalls = []
  const timerCallbacks = new Map()
  const timerDelays = new Map()
  const animationFrameCallbacks = new Map()
  const canceledAnimationFrames = []
  let nextTimerId = 0
  let nextAnimationFrameId = 0
  let mountedCallback
  let updatedCallback
  let unmountedCallback
  let observerCallback
  let observerTarget
  let observerOptions
  let observerObserveCount = 0
  let observerDisconnectCount = 0
  let observerConnected = false
  const notifyObservedMutation = (record) => {
    if (observerConnected) observerCallback([record])
  }
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
      notifyObservedMutation({type: "attributes", attributeName: "class", target: gridElement})
    },
    makeWidget(el) {
      gridCalls.push(["makeWidget", el.id])
      el.gridstackNode = { el }
      notifyObservedMutation({type: "attributes", attributeName: "class", target: el})
    },
    movable(el, value) {
      gridCalls.push(["movable", el.id, value])
      if (value) el.classList.add("ui-draggable")
      notifyObservedMutation({type: "attributes", attributeName: "class", target: el})
    },
    resizable(el, value) {
      gridCalls.push(["resizable", el.id, value])
      notifyObservedMutation({type: "attributes", attributeName: "class", target: el})
    },
    removeWidget(_el, removeDom, triggerEvent) {
      gridCalls.push(["removeWidget", removeDom, triggerEvent])
    },
    destroy(removeDom) {
      gridCalls.push(["destroy", removeDom])
    },
    onResize() {
      gridCalls.push(["onResize"])
    },
  }

  const sectionListeners = new Map()
  const sectionDetails = {
    open: false,
    addEventListener(type, listener) {
      sectionListeners.set(type, listener)
    },
    removeEventListener(type, listener) {
      assert.equal(sectionListeners.get(type), listener)
      sectionListeners.delete(type)
    },
  }

  const gridItems = [
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

  const gridElement = {
    dataset: { editMode: "false" },
    classList: classList("grid-stack-static"),
    gestureActive: false,
    closest(selector) {
      assert.equal(selector, "details[data-dashboard-section]")
      return sectionDetails
    },
    querySelector(selector) {
      assert.equal(selector, ".ui-draggable-dragging, .ui-resizable-resizing")
      return this.gestureActive ? {} : null
    },
    querySelectorAll(selector) {
      assert.equal(selector, ":scope > .grid-stack-item")
      return gridItems
    },
  }

  gridItems.forEach((item) => {
    item.parentElement = gridElement
  })

  class FakeMutationObserver {
    constructor(callback) {
      observerCallback = callback
    }

    observe(target, options) {
      if (observerOptions) assert.equal(options, observerOptions)
      observerTarget = target
      observerOptions = options
      observerObserveCount += 1
      observerConnected = true
    }

    disconnect() {
      observerDisconnectCount += 1
      observerConnected = false
    }
  }

  const runAnimationFrame = (id) => {
    const callback = animationFrameCallbacks.get(id)
    assert.equal(typeof callback, "function")
    animationFrameCallbacks.delete(id)
    callback()
  }

  const props = {target_id: "dashboard-grid-alpha", edit_mode: false, item_ids: ["widget-alpha"]}
  const emittedEvents = []
  const context = await loadControllerSfc(
    gridPath,
    [
      [
        'import {onBeforeUnmount, onMounted, onUpdated} from "vue"\n',
        "const {onBeforeUnmount, onMounted, onUpdated} = globalThis.Vue\n",
      ],
      [
        'import GridStack from "../vendor/gridstack/gridstack-all"\n',
        "const GridStack = globalThis.GridStack\n",
      ],
    ],
    {
      defineProps(definition) {
        assert.equal(definition.target_id.required, true)
        assert.equal(definition.edit_mode.default, false)
        assert.equal(definition.item_ids.type.name, "Array")
        return props
      },
      defineEmits(names) {
        assert.equal(Array.from(names).join(","), "layout_changed")
        return (event, payload) => emittedEvents.push([event, payload])
      },
      document: {
        getElementById(id) {
          assert.equal(id, props.target_id)
          return gridElement
        },
      },
      GridStack: {
        init(options, el) {
          gridCalls.push(["init", options.staticGrid, options.resizable.handles, el === gridElement])
          return fakeGrid
        },
      },
      MutationObserver: FakeMutationObserver,
      requestAnimationFrame(callback) {
        const id = ++nextAnimationFrameId
        animationFrameCallbacks.set(id, callback)
        return id
      },
      cancelAnimationFrame(id) {
        canceledAnimationFrames.push(id)
        animationFrameCallbacks.delete(id)
      },
      setTimeout(callback, delay) {
        const id = ++nextTimerId
        timerCallbacks.set(id, callback)
        timerDelays.set(id, delay)
        return id
      },
      clearTimeout(id) {
        timerCallbacks.delete(id)
        timerDelays.delete(id)
      },
      Vue: {
        onMounted: (callback) => { mountedCallback = callback },
        onUpdated: (callback) => { updatedCallback = callback },
        onBeforeUnmount: (callback) => { unmountedCallback = callback },
      },
    },
    "\nglobalThis.DashboardGridTest = {DashboardGridController, getController: () => controller}"
  )

  assert.match(context.template, /data-dashboard-grid-controller/)
  assert.equal(typeof mountedCallback, "function")
  assert.equal(typeof updatedCallback, "function")
  assert.equal(typeof unmountedCallback, "function")

  mountedCallback()
  const controller = context.DashboardGridTest.getController()

  assert.deepEqual(gridCalls.slice(0, 2), [
    ["init", true, "e, se, s", true],
    ["on", "change"],
  ])
  assert.equal(typeof sectionListeners.get("toggle"), "function")
  assert.equal(typeof observerCallback, "function")
  assert.equal(observerTarget, gridElement)
  assert.equal(observerObserveCount, 1)
  assert.equal(observerConnected, true)
  assert.deepEqual(JSON.parse(JSON.stringify(observerOptions)), {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: [
      "class",
      "data-edit-mode",
      "gs-id",
      "gs-x",
      "gs-y",
      "gs-w",
      "gs-h",
      "gs-auto-position",
    ],
  })

  gridElement.gestureActive = true
  const callsBeforeGestureUpdate = gridCalls.length
  updatedCallback()
  assert.equal(gridCalls.length, callsBeforeGestureUpdate)
  gridElement.gestureActive = false

  props.edit_mode = true
  gridElement.dataset.editMode = "true"
  updatedCallback()

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
  assert.equal(animationFrameCallbacks.size, 0)

  const externalGridItem = {
    id: "widget-external",
    parentElement: gridElement,
    classList: classList("grid-stack-item"),
  }
  gridItems.push(externalGridItem)
  const callsBeforeExternalMutation = gridCalls.length
  observerCallback([{type: "childList", target: gridElement}])
  observerCallback([{type: "attributes", attributeName: "gs-x", target: externalGridItem}])
  assert.equal(animationFrameCallbacks.size, 1)
  assert.equal(gridCalls.length, callsBeforeExternalMutation)
  const observesBeforeExternalReconciliation = observerObserveCount
  const disconnectsBeforeExternalReconciliation = observerDisconnectCount
  runAnimationFrame(nextAnimationFrameId)
  assert.equal(
    gridCalls.some(([name, id]) => name === "makeWidget" && id === "widget-external"),
    true
  )
  assert.equal(observerDisconnectCount, disconnectsBeforeExternalReconciliation + 1)
  assert.equal(observerObserveCount, observesBeforeExternalReconciliation + 1)
  assert.equal(observerConnected, true)
  // The fake GridStack methods attempt to report their own class mutations.
  // Observation is suspended during reconciliation, so no recursive frame is
  // scheduled when the observer is reattached.
  assert.equal(animationFrameCallbacks.size, 0)

  const nestedWidgetContent = {parentElement: {parentElement: externalGridItem}}
  observerCallback([{type: "childList", target: nestedWidgetContent}])
  assert.equal(animationFrameCallbacks.size, 0)

  controller.flushLayout()

  assert.deepEqual(JSON.parse(JSON.stringify(emittedEvents)), [
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

  fakeGrid.changeHandler()
  const scheduledTimerId = nextTimerId
  assert.equal(timerDelays.get(scheduledTimerId), 400)
  timerCallbacks.get(scheduledTimerId)()
  assert.equal(emittedEvents.length, 2)

  sectionListeners.get("toggle")()
  assert.equal(gridCalls.some(([name]) => name === "onResize"), false)
  sectionDetails.open = true
  fakeGrid.prevWidth = 720
  sectionListeners.get("toggle")()
  runAnimationFrame(nextAnimationFrameId)
  assert.equal(fakeGrid.prevWidth, undefined)
  assert.deepEqual(gridCalls.at(-1), ["onResize"])

  props.edit_mode = false
  gridElement.dataset.editMode = "false"
  updatedCallback()

  // Exiting edit restores float(true) before re-freezing the grid so view
  // mode keeps the server's exact gs-* positions.
  assert.deepEqual(gridCalls.slice(-2), [
    ["float", true],
    ["setStatic", true],
  ])

  observerCallback([{type: "childList", target: gridElement}])
  const pendingReconciliationFrame = nextAnimationFrameId
  assert.equal(animationFrameCallbacks.has(pendingReconciliationFrame), true)
  const disconnectsBeforeUnmount = observerDisconnectCount
  unmountedCallback()
  assert.deepEqual(gridCalls.at(-1), ["destroy", false])
  assert.equal(observerDisconnectCount, disconnectsBeforeUnmount + 1)
  assert.equal(observerConnected, false)
  assert.equal(canceledAnimationFrames.includes(pendingReconciliationFrame), true)
  assert.equal(animationFrameCallbacks.size, 0)
  assert.equal(sectionListeners.size, 0)
  assert.equal(context.DashboardGridTest.getController(), null)
}

{
  const editorGuardPath = resolve(__dirname, "../vue/DashboardEditorGuard.vue")
  const windowListeners = new Map()
  const documentListeners = new Map()
  let confirmResult = false
  let confirmationText = null
  let mountedCallback
  let unmountedCallback
  const props = {editor_dirty: false}

  const context = await loadControllerSfc(
    editorGuardPath,
    [[
      'import {onBeforeUnmount, onMounted} from "vue"\n',
      "const {onBeforeUnmount, onMounted} = globalThis.Vue\n",
    ]],
    {
      defineProps(definition) {
        assert.equal(definition.editor_dirty.default, false)
        return props
      },
      window: {
        addEventListener: (type, listener) => windowListeners.set(type, listener),
        removeEventListener: (type, listener) => {
          assert.equal(windowListeners.get(type), listener)
          windowListeners.delete(type)
        },
        confirm: (text) => {
          confirmationText = text
          return confirmResult
        },
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
      Vue: {
        onMounted: (callback) => { mountedCallback = callback },
        onBeforeUnmount: (callback) => { unmountedCallback = callback },
      },
    },
    "\nglobalThis.DashboardEditorGuardTest = {DashboardEditorGuardController, getController: () => controller}"
  )

  assert.match(context.template, /data-dashboard-editor-guard/)
  assert.equal(typeof mountedCallback, "function")
  assert.equal(typeof unmountedCallback, "function")
  mountedCallback()

  const cleanUnload = {preventDefault() { this.prevented = true }}
  windowListeners.get("beforeunload")(cleanUnload)
  assert.equal(cleanUnload.prevented, undefined)

  props.editor_dirty = true
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
  assert.equal(confirmationText, "Discard unsaved dashboard changes and leave the Editor?")

  for (const exemptAnchor of [
    null,
    {target: "", hasAttribute: (name) => name === "data-editor-discard"},
    {target: "_blank", hasAttribute: () => false},
    {target: "", hasAttribute: (name) => name === "download"},
  ]) {
    const exemptClick = {
      target: {closest: () => exemptAnchor},
      preventDefault() { this.prevented = true },
      stopImmediatePropagation() { this.stopped = true },
    }
    confirmationText = null
    documentListeners.get("click")(exemptClick)
    assert.equal(exemptClick.prevented, undefined)
    assert.equal(exemptClick.stopped, undefined)
    assert.equal(confirmationText, null)
  }

  confirmResult = true
  const confirmedClick = {
    target: {closest: () => anchor},
    preventDefault() { this.prevented = true },
    stopImmediatePropagation() { this.stopped = true },
  }
  documentListeners.get("click")(confirmedClick)
  assert.equal(confirmedClick.prevented, undefined)

  unmountedCallback()
  assert.equal(windowListeners.size, 0)
  assert.equal(documentListeners.size, 0)
  assert.equal(context.DashboardEditorGuardTest.getController(), null)
}

{
  const recentsPath = resolve(__dirname, "../vue/TimeRangeRecents.vue")
  const source = await readFile(recentsPath, "utf8")
  const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
  const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

  assert.ok(script, "TimeRangeRecents.vue must have a script setup block")
  assert.ok(template, "TimeRangeRecents.vue must have a template block")
  assert.match(
    template,
    /<p class="text-xs font-semibold text-base-content\/85">Recently used absolute ranges<\/p>/
  )
  assert.match(
    template,
    /<p v-if="props\.ranges\.length === 0" class="mt-1 text-\[0\.68rem\] text-base-content\/60">\s*Apply an absolute range and it will appear here for quick reuse\.\s*<\/p>/
  )
  assert.match(template, /<ul v-else class="mt-1" role="presentation">/)
  assert.match(template, /v-for="range in props\.ranges"/)
  assert.match(
    template,
    /<button\s+type="button"\s+data-dashboard-time-recent-range\s+class="w-full truncate px-1 py-0\.5 text-left font-mono text-\[0\.68rem\] text-base-content\/70 hover:bg-base-300\/40 hover:text-base-content"\s+:title="`Apply \$\{range\.from\} to \$\{range\.to\}`"\s+@click="selectRange\(range\)"\s*>\s*\{\{ range\.label \}\}\s*<\/button>/
  )

  const storage = new Map()
  const storageKey = "cadence:dashboard-time-recents"
  const serverRanges = [{
    from: "2026-08-01T10:00:00Z",
    to: "2026-08-01T12:00:00Z",
    label: "2026-08-01 10:00:00 to 2026-08-01 12:00:00 UTC",
  }]

  const makeComponent = ({getItem, setItem} = {}) => {
    const events = []
    const handlers = new Map()
    let mountedCallback

    const context = {
      localStorage: {
        getItem: getItem || ((key) => (storage.has(key) ? storage.get(key) : null)),
        setItem: setItem || ((key, value) => storage.set(key, value)),
      },
      defineProps: () => ({ranges: serverRanges}),
      defineEmits: (names) => {
        assert.equal(Array.from(names).join(","), "recents-loaded,select-range")
        return (name, payload) => events.push({name, payload})
      },
      Vue: {
        onMounted: (callback) => {
          mountedCallback = callback
        },
      },
      LiveVue: {
        useLiveEvent: (name, callback) => handlers.set(name, callback),
      },
    }

    const testableScript = script
      .replace(
        'import {onMounted} from "vue"',
        "const {onMounted} = globalThis.Vue"
      )
      .replace(
        'import {useLiveEvent} from "live_vue"',
        "const {useLiveEvent} = globalThis.LiveVue"
      ) + "\nglobalThis.TimeRangeRecents = {readRecents, storeRecent, selectRange}"

    vm.createContext(context)
    vm.runInContext(testableScript, context, {filename: recentsPath})

    return {
      events,
      handlers,
      mount: mountedCallback,
      state: context.TimeRangeRecents,
    }
  }

  // First mount: nothing stored yet -> pushes an empty list.
  const first = makeComponent()
  assert.equal(typeof first.mount, "function")
  assert.equal(typeof first.handlers.get("cadence:store-time-recent"), "function")
  first.mount()

  assert.equal(
    JSON.stringify(first.events),
    JSON.stringify([{name: "recents-loaded", payload: {ranges: []}}])
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
  assert.equal(lastPush.name, "recents-loaded")
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
  const second = makeComponent()
  second.mount()
  assert.equal(second.events[0].payload.ranges.length, 4)
  assert.equal(second.events[0].payload.ranges[0].from, "2026-08-01T19:00:00Z")

  // Stored entries without string bounds are filtered out.
  storage.set(storageKey, JSON.stringify([
    {from: "2026-08-01T21:00:00Z", to: "2026-08-01T22:00:00Z"},
    {from: 42, to: "2026-08-01T23:00:00Z"},
    {from: "2026-08-02T00:00:00Z", to: null},
  ]))
  const filtered = makeComponent()
  filtered.mount()
  assert.equal(filtered.events[0].payload.ranges.length, 1)
  assert.equal(filtered.events[0].payload.ranges[0].from, "2026-08-01T21:00:00Z")

  // Corrupt storage degrades to an empty list instead of throwing.
  storage.set(storageKey, "{not json")
  const third = makeComponent()
  third.mount()
  assert.equal(third.events[0].payload.ranges.length, 0)

  // Unavailable reads degrade to an empty list instead of throwing.
  const readFailure = makeComponent({
    getItem: () => {
      throw new Error("storage unavailable")
    },
  })
  readFailure.mount()
  assert.equal(readFailure.events[0].payload.ranges.length, 0)

  // Unavailable writes still update the current LiveView session.
  const writeFailure = makeComponent({
    setItem: () => {
      throw new Error("storage unavailable")
    },
  })
  writeFailure.handlers.get("cadence:store-time-recent")({
    from: "2026-08-02T01:00:00Z",
    to: "2026-08-02T02:00:00Z",
  })
  assert.equal(writeFailure.events[0].name, "recents-loaded")
  assert.equal(writeFailure.events[0].payload.ranges[0].from, "2026-08-02T01:00:00Z")

  // Malformed pushes are ignored.
  const before = first.events.length
  store({from: 42, to: "2026-08-01T20:00:00Z"})
  assert.equal(first.events.length, before)

  // Selecting a mounted recent range preserves the existing server event payload.
  first.state.selectRange(serverRanges[0])
  assert.equal(first.events.at(-1).name, "select-range")
  assert.equal(first.events.at(-1).payload.from, "2026-08-01T10:00:00Z")
  assert.equal(first.events.at(-1).payload.to, "2026-08-01T12:00:00Z")
}

console.log("dashboard_hooks_smoke_test passed")

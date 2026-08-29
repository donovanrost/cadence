import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  emptyStateActionClass,
  emptyStateActionContainerClass,
  emptyStateDescriptionClass,
  emptyStateRootClass,
  emptyStateTitleClass,
} from "./empty_state_frame_test_support.mjs"
import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarios = Object.freeze([
  "the production-compiled frame owns exactly the canonical div, title, description, and action-container presentation",
  "nested Fragment and array slots flatten without wrapper, comment, or whitespace nodes",
  "caller-owned native actions retain IDs, hrefs, Phoenix attrs, listeners, directives, and semantic text",
  "keyed native actions retain identity across reactive updates and reorder",
  "caller root attrs and listeners forward to the one native frame root",
  "the DTO CadenceEmptyState delegates to the frame without changing exact mounted output",
  "neither shared component owns routing, action semantics, state, or native action elements beyond the legacy DTO adapter",
])

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `empty-state frame contracts use pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 7)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const framePath = resolve(testDirectory, "../vue/ui/components/CadenceEmptyStateFrame.vue")
const dtoComponentPath = resolve(testDirectory, "../vue/ui/components/CadenceEmptyState.vue")
const dom = installDom('<div id="frame-host"></div><div id="dto-host"></div>')
const frameSource = await readFile(framePath, "utf8")
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsedFrame = parse(frameSource, {filename: framePath})

assert.deepEqual(parsedFrame.errors, [], "CadenceEmptyStateFrame parses with the pinned compiler")
assert.ok(parsedFrame.descriptor.script)
assert.equal(parsedFrame.descriptor.scriptSetup, null)

const compiledFrame = compileScript(parsedFrame.descriptor, {
  id: "cadence-empty-state-frame-contract",
}).content
const transformedFrame = transformSync(compiledFrame, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedFrameModule = {exports: {}}

new Function("require", "module", "exports", transformedFrame.code)(
  integrationRequire,
  loadedFrameModule,
  loadedFrameModule.exports,
)

const frameSfc = {
  component: loadedFrameModule.exports.default,
  descriptor: parsedFrame.descriptor,
  source: frameSource,
}
const dtoSfc = await loadSfc(dtoComponentPath)
const CadenceEmptyStateFrame = frameSfc.component
const CadenceEmptyState = dtoSfc.component
const {
  Fragment,
  createApp,
  defineComponent,
  h,
  nextTick,
  ref,
  withDirectives,
} = integrationRequire("vue")

assert.equal(frameSfc.descriptor.template, null, "the frame uses a strict render function")
assert.ok(frameSfc.descriptor.script, "the frame keeps a typed ordinary Vue script")
assert.equal(frameSfc.descriptor.script.lang, "ts")
assert.equal(CadenceEmptyStateFrame.inheritAttrs, false)
assert.deepEqual(Object.keys(CadenceEmptyStateFrame.props), [
  "rootAttrs",
  "titleAttrs",
  "descriptionAttrs",
  "actionContainerAttrs",
])
assert.equal(frameSfc.source.match(/h\(\s*"div"/g)?.length, 2)
assert.equal(frameSfc.source.match(/h\(\s*"p"/g)?.length, 2)
assert.match(frameSfc.source, /child\.type === Fragment/)
assert.match(frameSfc.source, /mergeProps\(props\.rootAttrs \?\? rootAttrs, attrs\)/)
assert.doesNotMatch(
  frameSfc.source,
  /<template>|<style|<a\b|<button\b|href|data-phx-link|defineEmits|emit\(|ref\(|reactive\(|watch\(/,
)

const phase = ref("ready")
const rootId = ref("caller-empty-state")
const actionOrder = ref(["alpha", "bravo"])
const actionElements = new Map()
const actionClicks = []
let rootClicks = 0
let directiveMounts = 0
let directiveUpdates = 0
let directiveUnmounts = 0

const ownershipDirective = {
  mounted(element, binding) {
    directiveMounts += 1
    element.dataset.directiveValue = binding.value
  },
  updated(element, binding) {
    directiveUpdates += 1
    element.dataset.directiveValue = binding.value
  },
  unmounted() {
    directiveUnmounts += 1
  },
}

const actionNode = (key) =>
  withDirectives(
    h(
      "a",
      {
        key,
        ref: (element) => {
          if (element) actionElements.set(key, element)
        },
        id: `caller-action-${key}`,
        href: `/actions/${key}?phase=${phase.value}&source=empty-state`,
        "data-phx-link": "redirect",
        "data-phx-link-state": "push",
        "data-phase": phase.value,
        class: emptyStateActionClass,
        onClick: (event) => {
          event.preventDefault()
          actionClicks.push(key)
        },
      },
      [h("span", {class: "hero-plus -ml-0.5 mr-1 h-4 w-4"}), ` ${key} ${phase.value}`],
    ),
    [[ownershipDirective, phase.value]],
  )

const FrameOracle = defineComponent({
  name: "CadenceEmptyStateFrameOracle",
  setup() {
    return () =>
      h(
        CadenceEmptyStateFrame,
        {
          id: rootId.value,
          "aria-label": "Caller empty state",
          "data-phase": phase.value,
          onClick: () => {
            rootClicks += 1
          },
        },
        {
          title: () => [h(Fragment, null, ["No ", h(Fragment, null, ["resources"]), " yet"])],
          description: () => [
            h(Fragment, null, ["Create one for phase ", h(Fragment, null, [phase.value]), "."]),
          ],
          action: () => [
            h(
              Fragment,
              null,
              actionOrder.value.map((key) => h(Fragment, {key}, [actionNode(key)])),
            ),
          ],
        },
      )
  },
})

const frameApp = createApp(FrameOracle)
frameApp.mount(dom.window.document.querySelector("#frame-host"))
await flushVue(nextTick)

const root = dom.window.document.querySelector("#caller-empty-state")
const title = root.children[0]
const description = root.children[1]
const actionContainer = root.children[2]
const alpha = dom.window.document.querySelector("#caller-action-alpha")
const bravo = dom.window.document.querySelector("#caller-action-bravo")

assert.equal(root.tagName, "DIV")
assert.deepEqual(elementAttributes(root), {
  "aria-label": "Caller empty state",
  class: emptyStateRootClass,
  "data-phase": "ready",
  id: "caller-empty-state",
})
assert.deepEqual(
  [...root.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "P"],
    [dom.window.Node.ELEMENT_NODE, "P"],
    [dom.window.Node.ELEMENT_NODE, "DIV"],
  ],
)
assert.deepEqual(elementAttributes(title), {class: emptyStateTitleClass})
assert.deepEqual(elementAttributes(description), {class: emptyStateDescriptionClass})
assert.deepEqual(elementAttributes(actionContainer), {class: emptyStateActionContainerClass})
assert.equal(title.textContent, "No resources yet")
assert.equal(description.textContent, "Create one for phase ready.")
assert.deepEqual([...actionContainer.childNodes].map((node) => node.nodeName), ["A", "A"])
assert.strictEqual(actionContainer.children[0], alpha)
assert.strictEqual(actionContainer.children[1], bravo)
assert.strictEqual(actionElements.get("alpha"), alpha)
assert.strictEqual(actionElements.get("bravo"), bravo)
assert.deepEqual(elementAttributes(alpha), {
  class: emptyStateActionClass,
  "data-directive-value": "ready",
  "data-phase": "ready",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/actions/alpha?phase=ready&source=empty-state",
  id: "caller-action-alpha",
})
assert.equal(alpha.textContent, " alpha ready")
assert.equal(directiveMounts, 2)

alpha.click()
assert.deepEqual(actionClicks, ["alpha"])
assert.equal(rootClicks, 1, "the caller root listener receives the unchanged bubbling click")

phase.value = "updated"
rootId.value = "caller-empty-state-updated"
actionOrder.value = ["bravo", "alpha"]
await flushVue(nextTick)

const updatedRoot = dom.window.document.querySelector("#caller-empty-state-updated")
assert.strictEqual(updatedRoot, root)
assert.strictEqual(updatedRoot.children[0], title)
assert.strictEqual(updatedRoot.children[1], description)
assert.strictEqual(updatedRoot.children[2], actionContainer)
assert.strictEqual(actionContainer.children[0], bravo)
assert.strictEqual(actionContainer.children[1], alpha)
assert.strictEqual(actionElements.get("alpha"), alpha)
assert.strictEqual(actionElements.get("bravo"), bravo)
assert.equal(description.textContent, "Create one for phase updated.")
assert.equal(alpha.getAttribute("href"), "/actions/alpha?phase=updated&source=empty-state")
assert.equal(alpha.dataset.directiveValue, "updated")
assert.equal(bravo.dataset.directiveValue, "updated")
assert.ok(directiveUpdates >= 2)

const dtoPresentation = {
  attrs: {
    id: "legacy-dto-empty-state",
    class: "legacy-root first-order",
    "data-legacy-root": "preserved",
  },
  title: {
    attrs: {id: "legacy-title", class: "legacy-title first-order"},
    text: "No legacy resources <yet>",
  },
  description: {
    attrs: {id: "legacy-description", class: "legacy-description first-order"},
    text: "The DTO & its exact attributes remain authoritative.",
  },
  action_container: {
    attrs: {id: "legacy-actions", class: "legacy-actions first-order"},
  },
  action: {
    attrs: {
      id: "legacy-action",
      href: "/legacy/new?from=empty&mode=dto",
      "data-phx-link": "redirect",
      "data-phx-link-state": "push",
      class: "legacy-action first-order",
    },
    icon: {
      attrs: {id: "legacy-icon", class: "hero-plus legacy-icon"},
    },
    text: "Create legacy resource",
  },
}

const dtoApp = createApp({
  render: () => h(CadenceEmptyState, {emptyState: dtoPresentation}),
})
dtoApp.mount(dom.window.document.querySelector("#dto-host"))
await flushVue(nextTick)

const dtoRoot = dom.window.document.querySelector("#legacy-dto-empty-state")
assert.equal(
  dtoRoot.outerHTML,
  '<div id="legacy-dto-empty-state" class="legacy-root first-order" data-legacy-root="preserved"><p id="legacy-title" class="legacy-title first-order">No legacy resources &lt;yet&gt;</p><p id="legacy-description" class="legacy-description first-order">The DTO &amp; its exact attributes remain authoritative.</p><div id="legacy-actions" class="legacy-actions first-order"><a id="legacy-action" href="/legacy/new?from=empty&amp;mode=dto" data-phx-link="redirect" data-phx-link-state="push" class="legacy-action first-order"><span id="legacy-icon" class="hero-plus legacy-icon"></span> Create legacy resource</a></div></div>',
)
assert.deepEqual([...dtoRoot.childNodes].map((node) => node.nodeName), ["P", "P", "DIV"])
assert.equal(dtoRoot.querySelectorAll("a").length, 1)
assert.equal(dtoRoot.querySelectorAll("span").length, 1)

assert.match(dtoSfc.source, /import CadenceEmptyStateFrame from "\.\/CadenceEmptyStateFrame\.vue"/)
assert.equal(dtoSfc.source.match(/<a\b/g)?.length, 1, "only the legacy DTO adapter owns its anchor")
assert.doesNotMatch(dtoSfc.source, /defineEmits|emit\(|ref\(|reactive\(|watch\(/)

assert.doesNotThrow(() => dtoApp.unmount())
assert.doesNotThrow(() => frameApp.unmount())
assert.equal(directiveUnmounts, 2)
dom.window.close()

console.log(`cadence_empty_state_frame_test passed (${scenarios.length} semantic scenarios)`)

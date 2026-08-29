import assert from "node:assert/strict"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceBreadcrumbs contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(testDirectory, "../vue/ui/components/CadenceBreadcrumbs.vue")
const dom = installDom('<div id="dto-contract"></div><div id="slot-contract"></div>')
const {component: CadenceBreadcrumbs, descriptor, source} = await loadSfc(componentPath)
const {Fragment, createApp, defineComponent, h} = integrationRequire("vue")

assert.equal(descriptor.scriptSetup.lang, "ts")
assert.equal(CadenceBreadcrumbs.props.breadcrumbs.required, false)
assert.match(source, /breadcrumbs\?: BreadcrumbsPresentation/)
assert.match(source, /child\.type === Fragment/)
assert.equal(source.match(/<a\b/g)?.length, 1, "slot mode adds no anchor implementation")
assert.equal(source.match(/data-phx-link/g), null, "Phoenix redirect attributes remain caller-owned")
assert.doesNotMatch(source, /cloneVNode|defineEmits|\b(?:computed|reactive|ref|watch)\s*\(/)

const navClass =
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
const breadcrumbs = {
  attrs: {"aria-label": "Breadcrumb", class: navClass},
  items: [
    {
      key: "mission",
      separator: null,
      link: {
        attrs: {
          id: "dto-mission-link",
          href: "/missions/alpha?from=breadcrumb&mode=inspect",
          "data-phx-link": "redirect",
          "data-phx-link-state": "push",
        },
        text: "Mission <Alpha>",
      },
      current: null,
    },
    {
      key: "current",
      separator: {
        attrs: {id: "dto-separator", "aria-hidden": "true"},
        text: "/",
      },
      link: null,
      current: {
        attrs: {id: "dto-current", "aria-current": "page"},
        text: "Current & active",
      },
    },
  ],
}

const dtoHost = dom.window.document.querySelector("#dto-contract")
const dtoApp = createApp({render: () => h(CadenceBreadcrumbs, {breadcrumbs})})
dtoApp.mount(dtoHost)

const dtoNav = dtoHost.firstElementChild
assert.equal(dtoHost.children.length, 1)
assert.equal(dtoNav.tagName, "NAV")
assert.equal(
  dtoNav.outerHTML,
  `<nav aria-label="Breadcrumb" class="${navClass}"><!--v-if--><a id="dto-mission-link" href="/missions/alpha?from=breadcrumb&amp;mode=inspect" data-phx-link="redirect" data-phx-link-state="push">Mission &lt;Alpha&gt;</a><!--v-if--><span id="dto-separator" aria-hidden="true">/</span><!--v-if--><span id="dto-current" aria-current="page">Current &amp; active</span></nav>`,
  "DTO mode retains the existing mounted DOM exactly",
)
assert.deepEqual(
  [...dtoNav.children].map((child) => child.tagName),
  ["A", "SPAN", "SPAN"],
)
assert.deepEqual(
  [...dtoNav.childNodes].map((node) => [node.nodeType, node.nodeName, node.nodeValue]),
  [
    [dom.window.Node.TEXT_NODE, "#text", ""],
    [dom.window.Node.TEXT_NODE, "#text", ""],
    [dom.window.Node.COMMENT_NODE, "#comment", "v-if"],
    [dom.window.Node.ELEMENT_NODE, "A", null],
    [dom.window.Node.COMMENT_NODE, "#comment", "v-if"],
    [dom.window.Node.TEXT_NODE, "#text", ""],
    [dom.window.Node.TEXT_NODE, "#text", ""],
    [dom.window.Node.ELEMENT_NODE, "SPAN", null],
    [dom.window.Node.COMMENT_NODE, "#comment", "v-if"],
    [dom.window.Node.ELEMENT_NODE, "SPAN", null],
    [dom.window.Node.TEXT_NODE, "#text", ""],
    [dom.window.Node.TEXT_NODE, "#text", ""],
  ],
  "DTO mode retains the existing text and conditional comment nodes exactly",
)
assert.deepEqual(elementAttributes(dtoNav.children[0]), {
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/alpha?from=breadcrumb&mode=inspect",
  id: "dto-mission-link",
})

let callerAnchor = null
let callerSeparator = null
let callerCurrent = null
let anchorClicks = 0
const SlotContract = defineComponent({
  name: "CadenceBreadcrumbsSlotContract",
  setup() {
    return () =>
      h(
        CadenceBreadcrumbs,
        null,
        {
          default: () => [
            h(Fragment, null, [
              h(
                "a",
                {
                  key: "mission",
                  ref: (element) => {
                    callerAnchor = element
                  },
                  id: "caller-mission-link",
                  href: "/missions/beta?from=breadcrumb&mode=slot",
                  "data-phx-link": "redirect",
                  "data-phx-link-state": "push",
                  "data-owner": "caller",
                  onClick: () => {
                    anchorClicks += 1
                  },
                },
                "Mission <Beta>",
              ),
              [
                h(Fragment, null, [
                  h(
                    "span",
                    {
                      key: "separator",
                      ref: (element) => {
                        callerSeparator = element
                      },
                      id: "caller-separator",
                      "aria-hidden": "true",
                      "data-owner": "caller",
                    },
                    "/",
                  ),
                ]),
              ],
            ]),
            h(
              "span",
              {
                key: "current",
                ref: (element) => {
                  callerCurrent = element
                },
                id: "caller-current",
                "aria-current": "page",
                "data-owner": "caller",
              },
              "Current & caller-owned",
            ),
          ],
        },
      )
  },
})

const slotHost = dom.window.document.querySelector("#slot-contract")
const slotApp = createApp(SlotContract)
slotApp.mount(slotHost)

const slotNav = slotHost.firstElementChild
assert.equal(slotHost.children.length, 1)
assert.equal(slotHost.querySelectorAll("nav").length, 1)
assert.equal(slotNav.tagName, "NAV")
assert.deepEqual(elementAttributes(slotNav), {
  "aria-label": "Breadcrumb",
  class: navClass,
})
assert.deepEqual(
  [...slotNav.childNodes].map((node) => [node.nodeType, node.nodeName]),
  [
    [dom.window.Node.ELEMENT_NODE, "A"],
    [dom.window.Node.ELEMENT_NODE, "SPAN"],
    [dom.window.Node.ELEMENT_NODE, "SPAN"],
  ],
  "slot mode adds no wrappers, fragment anchors, separators, or other child DOM",
)
assert.strictEqual(slotNav.children[0], callerAnchor)
assert.strictEqual(slotNav.children[1], callerSeparator)
assert.strictEqual(slotNav.children[2], callerCurrent)
assert.deepEqual(elementAttributes(callerAnchor), {
  "data-owner": "caller",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/missions/beta?from=breadcrumb&mode=slot",
  id: "caller-mission-link",
})
assert.deepEqual(elementAttributes(callerSeparator), {
  "aria-hidden": "true",
  "data-owner": "caller",
  id: "caller-separator",
})
assert.deepEqual(elementAttributes(callerCurrent), {
  "aria-current": "page",
  "data-owner": "caller",
  id: "caller-current",
})
assert.equal(callerAnchor.textContent, "Mission <Beta>")
assert.equal(callerSeparator.textContent, "/")
assert.equal(callerCurrent.textContent, "Current & caller-owned")
assert.equal(callerAnchor.hasAttribute("key"), false)
callerAnchor.click()
assert.equal(anchorClicks, 1, "caller-owned native listeners remain attached")

dtoApp.unmount()
slotApp.unmount()
assert.equal(dtoHost.children.length, 0)
assert.equal(slotHost.children.length, 0)
dom.window.close()

console.log("cadence_breadcrumbs_test passed (DTO exact DOM + transparent slot contract)")

#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  elementAttributes,
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"
import {
  noticeFrameCallerLedger,
  peelCadenceNoticeFrames,
} from "./notice_frame_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `CadenceNoticeFrame contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const vueDirectory = resolve(testDirectory, "../vue")
const componentPath = resolve(vueDirectory, "ui/components/CadenceNoticeFrame.vue")
const callerPaths = Object.keys(noticeFrameCallerLedger).map((filename) => ({
  filename,
  path: resolve(vueDirectory, filename),
}))

const componentSource = await readFile(componentPath, "utf8")
assert.match(componentSource, /name: "CadenceNoticeFrame"/)
assert.match(componentSource, /inheritAttrs: false/)
assert.match(componentSource, /type Tone = "info" \| "warning"/)
assert.match(componentSource, /required: true/)
assert.doesNotMatch(componentSource, /default:/)
assert.equal(componentSource.match(/h\(\s*"div"/g)?.length, 1)
assert.equal(componentSource.match(/\binfo:/g)?.length, 1)
assert.equal(componentSource.match(/\bwarning:/g)?.length, 1)
assert.doesNotMatch(componentSource, /\b(?:error|success):/)

for (const caller of callerPaths) {
  const source = await readFile(caller.path, "utf8")
  peelCadenceNoticeFrames(source, caller.filename)
}

const dom = installDom('<div id="notice-contract"></div>')
for (const globalName of ["Document", "ShadowRoot"]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const parsed = parse(componentSource, {filename: componentPath})
assert.deepEqual(parsed.errors, [])
assert.ok(parsed.descriptor.script)
assert.equal(parsed.descriptor.scriptSetup, null)
assert.equal(parsed.descriptor.template, null)

const compiled = compileScript(parsed.descriptor, {id: "cadence-notice-frame-contract"})
const transformed = transformSync(compiled.content, {
  format: "cjs",
  loader: "ts",
  platform: "node",
  target: "node24",
})
const loadedModule = {exports: {}}
const evaluate = new Function("require", "module", "exports", transformed.code)
evaluate(integrationRequire, loadedModule, loadedModule.exports)
const CadenceNoticeFrame = loadedModule.exports.default

assert.equal(CadenceNoticeFrame.inheritAttrs, false)
assert.equal(CadenceNoticeFrame.props.tone.required, true)
assert.equal(Object.hasOwn(CadenceNoticeFrame.props.tone, "default"), false)
assert.equal(CadenceNoticeFrame.props.tone.validator("info"), true)
assert.equal(CadenceNoticeFrame.props.tone.validator("warning"), true)
assert.equal(CadenceNoticeFrame.props.tone.validator("error"), false)

const {Fragment, createApp, defineComponent, h, nextTick, reactive} = integrationRequire("vue")
const state = reactive({tone: "info"})
let clickCount = 0
const Contract = defineComponent({
  setup() {
    return () =>
      h(
        CadenceNoticeFrame,
        {
          tone: state.tone,
          id: "notice-frame-proof",
          class: "caller-class",
          "data-proof": "caller-owned",
          onClick: () => {
            clickCount += 1
          },
        },
        {
          default: () => [
            "alpha",
            [
              h(Fragment, null, [
                h("span", {id: "fragment-span"}, "beta"),
                [h(Fragment, null, ["gamma", h("a", {id: "fragment-link"}, "delta")])],
              ]),
            ],
          ],
        },
      )
  },
})

const host = dom.window.document.querySelector("#notice-contract")
const app = createApp(Contract)
app.mount(host)

const notice = host.firstElementChild
assert.equal(notice.tagName, "DIV")
assert.deepEqual(elementAttributes(notice), {
  class:
    "border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70 caller-class",
  "data-proof": "caller-owned",
  id: "notice-frame-proof",
})
assert.equal(notice.hasAttribute("role"), false)
assert.deepEqual(
  [...notice.childNodes].map((node) => node.nodeName),
  ["#text", "SPAN", "#text", "A"],
)
assert.deepEqual(
  [...notice.childNodes].map((node) => node.textContent),
  ["alpha", "beta", "gamma", "delta"],
)
assert.strictEqual(notice.children[0], host.querySelector("#fragment-span"))
assert.strictEqual(notice.children[1], host.querySelector("#fragment-link"))

notice.dispatchEvent(new dom.window.MouseEvent("click", {bubbles: true}))
assert.equal(clickCount, 1)

state.tone = "warning"
await nextTick()
assert.strictEqual(host.firstElementChild, notice)
assert.equal(
  notice.className,
  "border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70 caller-class",
)

app.unmount()
assert.equal(host.children.length, 0)
dom.window.close()

console.log("notice_frame_migration_test passed (4 exact boundaries, 3 frozen callers)")

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"
import {
  flushVue,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/CsvDownloadButton.vue")
const cadenceButtonPath = resolve(__dirname, "../vue/ui/components/CadenceButton.vue")
const [source, cadenceButtonSource] = await Promise.all([
  readFile(componentPath, "utf8"),
  readFile(cadenceButtonPath, "utf8"),
])

const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CsvDownloadButton.vue must have a script setup block")
assert.ok(template, "CsvDownloadButton.vue must have a template block")
assert.match(
  template,
  /<CadenceButton\s+id="dashboard-widget-inspect-download"\s+type="button"\s+:disabled="props.disabled"\s+class="btn btn-sm btn-outline justify-start"\s+@click="downloadCsv"\s*>\s*<span class="hero-arrow-down-tray h-4 w-4"><\/span> Download CSV\s*<\/CadenceButton>/,
  "the CSV component must delegate its exact attributes, listener, icon, and copy to CadenceButton",
)
assert.match(script, /^import CadenceButton from "\.\/ui\/components\/CadenceButton\.vue"$/m)
assert.doesNotMatch(template, /<button\b|<div\b/)
assert.match(cadenceButtonSource, /h\("button", null, slots\.default\?\.\(\)\)/)

const props = {
  csv: "time_utc,volts\r\n2026-08-01T10:00:00Z,1.5",
  filename: "trend-inspect.csv",
  disabled: false,
}
const blobs = []
const anchors = []
const revokedUrls = []
let clickError

const context = {
  Blob: class {
    constructor(parts, options) {
      this.content = parts.join("")
      this.type = options?.type
      blobs.push(this)
    }
  },
  URL: {
    createObjectURL() {
      return `blob:csv-${blobs.length}`
    },
    revokeObjectURL(url) {
      revokedUrls.push(url)
    },
  },
  defineProps() {
    return props
  },
  document: {
    createElement(tag) {
      const anchor = {
        tag,
        clicked: false,
        click() {
          this.clicked = true
          if (clickError) throw clickError
        },
      }
      anchors.push(anchor)
      return anchor
    },
  },
}

vm.createContext(context)
const testableScript =
  script.replace(/^import CadenceButton from "\.\/ui\/components\/CadenceButton\.vue"\n\n/m, "") +
  "\nglobalThis.downloadCsv = downloadCsv"

vm.runInContext(testableScript, context, {
  filename: componentPath,
})

context.downloadCsv()

assert.equal(blobs[0].content, props.csv)
assert.equal(blobs[0].type, "text/csv;charset=utf-8")
assert.equal(anchors[0].tag, "a")
assert.equal(anchors[0].download, "trend-inspect.csv")
assert.equal(anchors[0].href, "blob:csv-1")
assert.equal(anchors[0].clicked, true)
assert.deepEqual(revokedUrls, ["blob:csv-1"])

// Missing props preserve the hook's empty CSV and default filename behavior.
props.csv = undefined
props.filename = undefined
context.downloadCsv()

assert.equal(blobs[1].content, "")
assert.equal(anchors[1].download, "widget-data.csv")
assert.equal(anchors[1].href, "blob:csv-2")
assert.deepEqual(revokedUrls, ["blob:csv-1", "blob:csv-2"])

// Cleanup remains guaranteed if the synthetic anchor click throws.
clickError = new Error("click failed")
assert.throws(() => context.downloadCsv(), /click failed/)
assert.deepEqual(revokedUrls, ["blob:csv-1", "blob:csv-2", "blob:csv-3"])

const dom = installDom('<div id="enabled"></div><div id="disabled"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const loadSfc = async (path, localModules = {}) => {
  const sfcSource = await readFile(path, "utf8")
  const parsed = parse(sfcSource, {filename: path})

  assert.deepEqual(parsed.errors, [], `${path} parses with the pinned Vue compiler`)
  assert.ok(
    parsed.descriptor.scriptSetup ?? parsed.descriptor.script,
    `${path} keeps an auditable script`,
  )

  const compiled = parsed.descriptor.scriptSetup
    ? compileScript(parsed.descriptor, {
        id: `csv-download-${path.split("/").at(-1)}`,
        inlineTemplate: true,
      }).content
    : parsed.descriptor.script.content
  const transformed = transformSync(compiled, {
    format: "cjs",
    loader: "ts",
    platform: "node",
    target: "node24",
  })
  const loadedModule = {exports: {}}
  const localRequire = (specifier) => localModules[specifier] ?? integrationRequire(specifier)

  new Function("require", "module", "exports", transformed.code)(
    localRequire,
    loadedModule,
    loadedModule.exports,
  )

  return loadedModule.exports
}

const cadenceButtonModule = await loadSfc(cadenceButtonPath)
const csvDownloadButtonModule = await loadSfc(componentPath, {
  "./ui/components/CadenceButton.vue": cadenceButtonModule,
})
const CsvDownloadButton = csvDownloadButtonModule.default

assert.deepEqual(Object.keys(CsvDownloadButton.props).sort(), ["csv", "disabled", "filename"])
assert.equal(CsvDownloadButton.props.csv.default, "")
assert.equal(CsvDownloadButton.props.filename.default, "widget-data.csv")
assert.equal(CsvDownloadButton.props.disabled.default, false)

const runtimeBlobs = []
const runtimeAnchors = []
const runtimeRevokedUrls = []
const RuntimeBlob = class {
  constructor(parts, options) {
    this.content = parts.join("")
    this.type = options?.type
    runtimeBlobs.push(this)
  }
}
const runtimeDocument = dom.window.document
const originalCreateElement = runtimeDocument.createElement.bind(runtimeDocument)
runtimeDocument.createElement = (tag, options) => {
  const element = originalCreateElement(tag, options)

  if (tag === "a") {
    element.click = () => {
      element.clicked = true
    }
    runtimeAnchors.push(element)
  }

  return element
}
Object.defineProperty(globalThis, "Blob", {configurable: true, value: RuntimeBlob})
Object.defineProperty(globalThis.URL, "createObjectURL", {
  configurable: true,
  value: () => `blob:runtime-${runtimeBlobs.length}`,
})
Object.defineProperty(globalThis.URL, "revokeObjectURL", {
  configurable: true,
  value: (url) => runtimeRevokedUrls.push(url),
})

const {createApp, nextTick} = integrationRequire("vue")
const runtimeProps = {
  csv: "time_utc,volts\r\n2026-08-01T10:00:00Z,1.5",
  filename: "trend-inspect.csv",
  disabled: false,
}
const enabledApp = createApp(CsvDownloadButton, runtimeProps)
enabledApp.mount(runtimeDocument.querySelector("#enabled"))
await flushVue(nextTick)

const enabledButton = runtimeDocument.querySelector("#enabled > button")
assert.equal(
  enabledButton.outerHTML,
  '<button id="dashboard-widget-inspect-download" type="button" class="btn btn-sm btn-outline justify-start"><span class="hero-arrow-down-tray h-4 w-4"></span> Download CSV </button>',
)
assert.equal(enabledButton.childNodes.length, 2)
assert.equal(enabledButton.childNodes[0].tagName, "SPAN")
assert.equal(enabledButton.childNodes[1].nodeType, dom.window.Node.TEXT_NODE)
assert.equal(enabledButton.childNodes[1].textContent, " Download CSV ")
enabledButton.click()
assert.equal(runtimeBlobs[0].content, runtimeProps.csv)
assert.equal(runtimeBlobs[0].type, "text/csv;charset=utf-8")
assert.equal(runtimeAnchors[0].download, runtimeProps.filename)
assert.equal(runtimeAnchors[0].href, "blob:runtime-1")
assert.equal(runtimeAnchors[0].clicked, true)
assert.deepEqual(runtimeRevokedUrls, ["blob:runtime-1"])

const disabledApp = createApp(CsvDownloadButton, {
  csv: "must not download",
  filename: "disabled.csv",
  disabled: true,
})
disabledApp.mount(runtimeDocument.querySelector("#disabled"))
await flushVue(nextTick)

const disabledButton = runtimeDocument.querySelector("#disabled > button")
assert.equal(
  disabledButton.outerHTML,
  '<button id="dashboard-widget-inspect-download" type="button" disabled="" class="btn btn-sm btn-outline justify-start"><span class="hero-arrow-down-tray h-4 w-4"></span> Download CSV </button>',
)
assert.equal(disabledButton.childNodes.length, 2)
assert.equal(disabledButton.childNodes[1].textContent, " Download CSV ")
disabledButton.click()
assert.equal(runtimeBlobs.length, 1)
assert.equal(runtimeAnchors.length, 1)
assert.deepEqual(runtimeRevokedUrls, ["blob:runtime-1"])

assert.doesNotThrow(() => enabledApp.unmount())
assert.doesNotThrow(() => disabledApp.unmount())

console.log("csv_download_button_test passed")

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/CsvDownloadButton.vue")
const source = await readFile(componentPath, "utf8")

const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CsvDownloadButton.vue must have a script setup block")
assert.ok(template, "CsvDownloadButton.vue must have a template block")
assert.match(
  template,
  /<button\s+id="dashboard-widget-inspect-download"\s+type="button"\s+:disabled="props.disabled"\s+class="btn btn-sm btn-outline justify-start"\s+@click="downloadCsv"\s*>\s*<span class="hero-arrow-down-tray h-4 w-4"><\/span> Download CSV\s*<\/button>/,
  "the Vue button must preserve the existing DOM, label, icon, styling, and native disabled state"
)

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
vm.runInContext(script + "\nglobalThis.downloadCsv = downloadCsv", context, {
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

console.log("csv_download_button_test passed")

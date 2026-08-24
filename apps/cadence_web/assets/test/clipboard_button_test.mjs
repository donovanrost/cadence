import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/ClipboardButton.vue")
const source = await readFile(componentPath, "utf8")

const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "ClipboardButton.vue must have a script setup block")
assert.ok(template, "ClipboardButton.vue must have a template block")
assert.match(template, /<button[\s\S]*:id="props\.button_id"[\s\S]*type="button"/)
assert.match(template, /:class="props\.button_class"/)
assert.match(template, /:title="props\.title \|\| undefined"/)
assert.match(template, /:aria-label="props\.aria_label \|\| undefined"/)
assert.match(template, /data-clipboard-button/)
assert.match(template, /:data-clipboard-text="props\.clipboard_text \|\| undefined"/)
assert.match(template, /:data-clipboard-copied="feedback === 'copied' \? 'true' : undefined"/)
assert.match(template, /:data-clipboard-failed="feedback === 'failed' \? 'true' : undefined"/)
assert.match(template, /v-bind="props\.data_attrs"/)
assert.match(template, /@click="copy"/)
assert.match(template, /<span :class="\[props\.icon, props\.icon_class\]"><\/span> \{\{ props\.label \}\}/)
assert.match(
  template,
  /<span class="sr-only" role="status" aria-live="polite" aria-atomic="true">/,
  "copy feedback must be announced without changing the button label"
)

const props = {
  button_id: "dashboard-data-link-copy-link",
  clipboard_text: "/ops/dashboards/alpha?selected=data-link-1",
  button_class: "btn btn-sm btn-outline w-full justify-start",
  icon: "hero-link",
  icon_class: "h-4 w-4",
  label: "Copy link",
  title: "",
  aria_label: "",
  data_attrs: {"data-dashboard-example": "example-1"}
}
const appended = []
const clearedTimers = []
const timers = new Map()
const clipboardWrites = []
let nextTimerId = 1
let unmountedCallback
let clipboardError
let execCommandResult = true
let execCommandError
let execCommandName

const context = {
  URL,
  clearTimeout(timerId) {
    clearedTimers.push(timerId)
    timers.delete(timerId)
  },
  setTimeout(callback, delay) {
    const timerId = nextTimerId
    nextTimerId += 1
    timers.set(timerId, {callback, delay})
    return timerId
  },
  defineProps() {
    return props
  },
  document: {
    body: {
      appendChild(node) {
        appended.push(node)
      }
    },
    createElement(tag) {
      assert.equal(tag, "textarea")
      return {
        style: {},
        setAttribute(name, value) {
          this[name] = value
        },
        select() {
          this.selected = true
        },
        remove() {
          this.removed = true
        }
      }
    },
    execCommand(command) {
      execCommandName = command
      if (execCommandError) throw execCommandError
      return execCommandResult
    }
  },
  navigator: {
    clipboard: {
      async writeText(text) {
        if (clipboardError) throw clipboardError
        clipboardWrites.push(text)
      }
    }
  },
  window: {
    location: {
      origin: "https://cadence.test",
      pathname: "/ops/dashboards/beta",
      search: "?selected=data-link-2"
    }
  },
  Vue: {
    computed(callback) {
      return {
        get value() {
          return callback()
        }
      }
    },
    onUnmounted(callback) {
      unmountedCallback = callback
    },
    ref(value) {
      return {value}
    }
  }
}

const testableScript =
  script.replace(
    'import {computed, onUnmounted, ref} from "vue"',
    "const {computed, onUnmounted, ref} = globalThis.Vue"
  ) +
  "\nglobalThis.clipboardButton = {absoluteText, copyWithFallback, markFeedback, copy, feedback, feedbackMessage}"

vm.createContext(context)
vm.runInContext(testableScript, context, {filename: componentPath})

const component = context.clipboardButton

assert.equal(typeof unmountedCallback, "function")
assert.equal(component.feedback.value, "")
assert.equal(component.feedbackMessage.value, "")
assert.equal(
  component.absoluteText(),
  "https://cadence.test/ops/dashboards/alpha?selected=data-link-1"
)

await component.copy()

assert.deepEqual(clipboardWrites, [
  "https://cadence.test/ops/dashboards/alpha?selected=data-link-1"
])
assert.equal(component.feedback.value, "copied")
assert.equal(component.feedbackMessage.value, "Copied to clipboard")
assert.equal(timers.get(1).delay, 1500)

timers.get(1).callback()
assert.equal(component.feedback.value, "")
assert.equal(component.feedbackMessage.value, "")

clipboardError = new Error("clipboard unavailable")
props.clipboard_text = ""
await component.copy()

assert.equal(appended.length, 1)
assert.equal(
  appended[0].value,
  "https://cadence.test/ops/dashboards/beta?selected=data-link-2"
)
assert.equal(appended[0].readonly, "readonly")
assert.equal(appended[0].style.position, "fixed")
assert.equal(appended[0].style.opacity, "0")
assert.equal(appended[0].selected, true)
assert.equal(appended[0].removed, true)
assert.equal(execCommandName, "copy")
assert.equal(component.feedback.value, "copied")

execCommandResult = false
await component.copy()
assert.equal(component.feedback.value, "failed")
assert.equal(component.feedbackMessage.value, "Copy failed")

execCommandResult = true
execCommandError = new Error("fallback unavailable")
await component.copy()
assert.equal(appended.at(-1).removed, true)
assert.equal(component.feedback.value, "failed")

const activeTimerId = nextTimerId - 1
unmountedCallback()
assert.equal(clearedTimers.includes(activeTimerId), true)

console.log("clipboard_button_test passed")

import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const __dirname = dirname(fileURLToPath(import.meta.url))
const componentPath = resolve(__dirname, "../vue/UtcClock.vue")
const source = await readFile(componentPath, "utf8")

const script = source.match(/<script setup>\n([\s\S]*?)\n<\/script>/)?.[1]
const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "UtcClock.vue must have a script setup block")
assert.ok(template, "UtcClock.vue must have a template block")
assert.match(
  template,
  /<span role="timer" aria-live="off">\{\{ utcTime \}\}<\/span>/,
  "the visible clock must remain accessible without announcing every tick"
)

let nowMs = Date.parse("2026-08-23T03:04:05Z")
let mountedCallback
let unmountedCallback
let intervalCallback
let intervalDelay
let clearedTimer

const NativeDate = Date

class TestDate extends NativeDate {
  constructor(...args) {
    super(...(args.length === 0 ? [nowMs] : args))
  }
}

const context = {
  Date: TestDate,
  clearInterval(timerId) {
    clearedTimer = timerId
  },
  setInterval(callback, delay) {
    intervalCallback = callback
    intervalDelay = delay
    return 42
  },
  Vue: {
    onMounted(callback) {
      mountedCallback = callback
    },
    onUnmounted(callback) {
      unmountedCallback = callback
    },
    ref(value) {
      return {value}
    },
  },
}

const testableScript =
  script.replace(
    'import {onMounted, onUnmounted, ref} from "vue"',
    "const {onMounted, onUnmounted, ref} = globalThis.Vue"
  ) + "\nglobalThis.clockState = {utcTime}"

vm.createContext(context)
vm.runInContext(testableScript, context, {filename: componentPath})

assert.equal(context.clockState.utcTime.value, "")
assert.equal(typeof mountedCallback, "function")
assert.equal(typeof unmountedCallback, "function")

mountedCallback()

assert.equal(context.clockState.utcTime.value, "03:04:05 UTC")
assert.equal(intervalDelay, 1000)
assert.equal(typeof intervalCallback, "function")

nowMs = Date.parse("2026-08-23T23:59:00Z")
intervalCallback()

assert.equal(context.clockState.utcTime.value, "23:59:00 UTC")

unmountedCallback()

assert.equal(clearedTimer, 42)

console.log("utc_clock_test passed")

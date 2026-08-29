#!/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node

import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {readFile, readdir} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

import {
  elementAttributes,
  expectedNodeVersion,
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"
import {
  opsListBodyFrameCallerNames,
  opsListBodyFrameClass,
  opsListBodyFrameImport,
  opsListBodyFrameMigrations,
  opsListBodyFramePath,
  opsListBodyFramePredecessorCommit,
  opsListBodyFrameSha256,
  peelCadenceOpsListBodyFrame,
} from "./ops_list_body_frame_test_support.mjs"
import {
  opsListFrameClass,
  opsListFrameMigrations,
  opsListFramePredecessorCommit,
  peelCadenceOpsListFrame,
} from "./ops_list_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves and is an ancestor of current HEAD",
  "exactly two callers import and use the body frame",
  "the frozen base has exactly two native wrappers and no third eligible match",
  "both callers reconstruct their frozen predecessor bytes and SHA-256 values exactly",
  "the newest inverse peel composes before CadenceOpsListFrame and older layers",
  "real callers retain direct children, forms, controls, events, values, links, details, and keyed list identity",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "Ops list body migration uses the pinned Node executable")
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Ops list body migration uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 6)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const nativeOpening = `<div class="${opsListBodyFrameClass}">`
const occurrences = (source, fragment) => source.split(fragment).length - 1
const gitText = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})
const frozenSource = migration =>
  gitText(["show", `${opsListBodyFramePredecessorCommit}:${migration.repositoryPath}`])

assert.equal(
  gitText(["cat-file", "-t", opsListBodyFramePredecessorCommit]).trim(),
  "commit",
  "the frozen body-frame predecessor resolves exactly as a commit",
)
assert.equal(
  gitText(["rev-parse", "--verify", `${opsListBodyFramePredecessorCommit}^{commit}`]).trim(),
  opsListBodyFramePredecessorCommit,
  "the frozen body-frame predecessor resolves to the requested object",
)
assert.doesNotThrow(
  () => gitText(["merge-base", "--is-ancestor", opsListBodyFramePredecessorCommit, "HEAD"]),
  "the frozen body-frame predecessor is an ancestor of current HEAD",
)

assert.equal(opsListBodyFrameMigrations.length, 2, "the body-frame ledger has exactly two callers")
assert.deepEqual(
  [...opsListBodyFrameCallerNames].sort(),
  ["OpsAlarms.vue", "OpsCommands.vue"],
  "the body-frame ledger is exactly OpsAlarms and OpsCommands",
)

const currentVueFiles = (await readdir(vueDirectory, {recursive: true}))
  .filter(file => file.endsWith(".vue"))
  .sort()
const currentSources = await Promise.all(
  currentVueFiles.map(async file => ({
    file,
    source: await readFile(resolve(vueDirectory, file), "utf8"),
  })),
)
const importedCallers = currentSources
  .filter(({source}) => occurrences(source, opsListBodyFrameImport) > 0)
  .map(({file}) => file)
  .sort()

assert.deepEqual(
  importedCallers,
  ["OpsAlarms.vue", "OpsCommands.vue"],
  "exactly two callers import CadenceOpsListBodyFrame",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, opsListBodyFrameImport), 0),
  2,
  "the Vue source tree has exactly two body-frame imports",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceOpsListBodyFrame\b/g)?.length ?? 0),
    0,
  ),
  2,
  "the Vue source tree has exactly two body-frame openings",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceOpsListBodyFrame>/g)?.length ?? 0),
    0,
  ),
  2,
  "the Vue source tree has exactly two body-frame closings",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, nativeOpening), 0),
  0,
  "no eligible native body wrapper remains in current Vue sources",
)

const predecessorVueFiles = gitText([
  "ls-tree",
  "-r",
  "--name-only",
  opsListBodyFramePredecessorCommit,
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter(file => file.endsWith(".vue"))
  .map(file => file.slice("apps/cadence_web/assets/vue/".length))
  .sort()
const historicalEligibleRoots = predecessorVueFiles.flatMap(file => {
  const source = gitText(["show", `${opsListBodyFramePredecessorCommit}:apps/cadence_web/assets/vue/${file}`])
  const count = occurrences(source, nativeOpening)
  return count > 0 ? [{file, count}] : []
})

assert.equal(
  historicalEligibleRoots.reduce((total, {count}) => total + count, 0),
  2,
  "the frozen base has exactly two original eligible native body wrappers",
)
assert.deepEqual(
  historicalEligibleRoots,
  [
    {file: "OpsAlarms.vue", count: 1},
    {file: "OpsCommands.vue", count: 1},
  ],
  "the frozen base wrappers are exactly the two audited callers",
)
assert.deepEqual(
  currentSources.filter(({source}) => occurrences(source, opsListBodyFrameImport) > 0).map(({file}) => file).sort(),
  [...opsListBodyFrameCallerNames].sort(),
  "the current import inventory has no third caller",
)
assert.equal(
  new Set([
    ...historicalEligibleRoots.map(({file}) => file),
    ...currentSources
      .filter(({source}) => occurrences(source, nativeOpening) > 0)
      .map(({file}) => file),
  ]).size,
  2,
  "the current/base eligible-wrapper union has no third match",
)
assert.ok(
  currentVueFiles.includes(opsListBodyFramePath.slice("apps/cadence_web/assets/vue/".length)),
  "the successor includes the new body-frame path",
)

for (const migration of opsListBodyFrameMigrations) {
  const current = await readFile(resolve(vueDirectory, migration.file), "utf8")
  const predecessor = frozenSource(migration)

  assert.equal(
    gitText(["rev-parse", `${opsListBodyFramePredecessorCommit}:${migration.repositoryPath}`]).trim(),
    migration.predecessorBlobId,
    `${migration.file} keeps its frozen predecessor blob object`,
  )
  assert.equal(Buffer.byteLength(predecessor), migration.predecessorByteLength)
  assert.equal(opsListBodyFrameSha256(predecessor), migration.predecessorSha256)
  assert.equal(
    peelCadenceOpsListBodyFrame(current, migration.file),
    predecessor,
    `${migration.file} reconstructs its exact frozen predecessor bytes`,
  )
  assert.equal(
    opsListBodyFrameSha256(peelCadenceOpsListBodyFrame(current, migration.file)),
    migration.predecessorSha256,
    `${migration.file} inverse peel preserves its frozen predecessor SHA-256`,
  )

  const bodyFramePredecessor = peelCadenceOpsListBodyFrame(current, migration.file)
  const listFramePredecessor = peelCadenceOpsListFrame(bodyFramePredecessor, migration.file)
  assert.ok(opsListFrameMigrations.some(entry => entry.file === migration.file))
  assert.equal(
    listFramePredecessor,
    gitText(["show", `${opsListFramePredecessorCommit}:${migration.repositoryPath}`]),
    `${migration.file} composes body peel before the CadenceOpsListFrame predecessor`,
  )
}

const dom = installDom('<main id="ops-list-body-migration"></main>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
  "HTMLButtonElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

const selectField = (id, name, label, options) => ({
  id,
  name,
  type: "select",
  label,
  options,
})
const searchField = (id, name, label) => ({
  id,
  name,
  type: "search",
  label,
  placeholder: `Search ${label.toLowerCase()}`,
  debounce_ms: 1,
})
const alarm = id => ({
  id,
  __dom_id: `alarm-row-${id}`,
  limit_event_id: `limit-${id}`,
  severity: "critical",
  limit_state: "triggered",
  state_label: "Triggered",
  point_name: `${id} point`,
  context: `context-${id}`,
  value: {label: "Value", display: `${id}-value`},
  observed: {label: "Observed", display: `${id}-observed`},
  evidence: {
    id: `alarm-evidence-${id}`,
    href: `/ops/alarms/${id}/evidence`,
    title: `Evidence ${id}`,
    icon: "icon-evidence",
    label: "Evidence",
  },
  definition: {
    id: `alarm-definition-${id}`,
    href: `/ops/alarms/${id}/definition`,
    title: `Definition ${id}`,
    icon: "icon-definition",
    label: "Definition",
  },
})
const alarms = [alarm("alpha"), alarm("bravo")]
const alarmProps = {
  page: {
    id: "ops-alarms-page",
    header: {eyebrow: "Operations", heading: "Alarms", copy: "Live alarms"},
    conditions_id: "alarm-conditions",
  },
  summary: {id: "alarm-summary", active_count: 2, observed: "2 observed", badges: [{severity: "critical", count: 2, label: "Critical"}]},
  filters: {
    id: "alarm-filters",
    values: {severity: "critical", state: "triggered", spacecraft_id: "sc-1", query: "alpha"},
    fields: {
      severity: selectField("alarm-severity", "severity", "Severity", [{label: "Critical", value: "critical"}, {label: "Warning", value: "warning"}]),
      state: selectField("alarm-state", "state", "State", [{label: "Triggered", value: "triggered"}]),
      spacecraft_id: selectField("alarm-spacecraft", "spacecraft_id", "Spacecraft", [{label: "SC-1", value: "sc-1"}]),
      query: searchField("alarm-query", "query", "Search"),
    },
  },
  reset: {id: "alarm-reset", label: "Reset"},
  empty: {id: "alarm-empty", icon: "icon-empty", heading: "No alarms", copy: "All clear"},
  alarms,
}

const command = (id, following = false) => ({
  id,
  __dom_id: `command-row-${id}`,
  command_request_id: `request-${id}`,
  command_name: `Command ${id}`,
  status: {value: "queued", label: "Queued", class: "text-info"},
  target: {label: "Target", display: `Target ${id}`},
  requester: {label: "Requester", display: `Requester ${id}`},
  age: {label: "Age", display: `${id} age`},
  focus: {
    following,
    label: "Following",
    class: "text-success",
    action: {id: `command-follow-${id}`, label: "Follow", icon: "icon-follow", payload: {"command-request-id": `request-${id}`}},
  },
  evidence: {
    summary: `Evidence ${id}`,
    request_state: {label: "Request", display: `request-state-${id}`},
    queue_entry: {label: "Queue", record_id: `queue-${id}`, display: `queue-${id}`},
    release_attempt: {label: "Release", record_id: null, display: "Not released"},
    verification: {label: "Verification", state: "pending", display: "Pending"},
  },
})
const commands = [command("alpha"), command("bravo", true)]
const commandProps = {
  page: {
    id: "ops-commands-page",
    header: {eyebrow: "Operations", heading: "Commands", copy: "Live commands"},
    rows_id: "command-rows",
  },
  summary: {id: "command-summary", active_count: 2, observed: "2 observed", metrics: [{label: "Queued", value: 2, value_class: "text-info"}]},
  filters: {
    id: "command-filters",
    values: {status: "queued", target: "target-1", query: "alpha"},
    fields: {
      status: selectField("command-status", "status", "Status", [{label: "Queued", value: "queued"}]),
      target: selectField("command-target", "target", "Target", [{label: "Target 1", value: "target-1"}]),
      query: searchField("command-query", "query", "Search"),
    },
  },
  reset: {id: "command-reset", label: "Reset", payload: {}},
  focus_banner: {
    id: "command-focus",
    command_request_id: "request-alpha",
    icon: "icon-focus",
    prefix: "Following",
    suffix: "now",
    clear: {id: "command-clear", label: "Clear", payload: {}},
  },
  empty: {id: "command-empty", icon: "icon-empty", heading: "No commands", copy: "No commands"},
  commands,
}

const mountCaller = async (file, props, listeners = {}) => {
  const {component} = await loadSfc(resolve(vueDirectory, file))
  const propsRef = ref(props)
  const wrapper = defineComponent({
    name: `Mounted${file.replace(".vue", "")}`,
    setup() {
      return () => h(component, {...propsRef.value, ...listeners})
    },
  })
  const host = dom.window.document.createElement("div")
  host.id = `host-${file}`
  dom.window.document.querySelector("#ops-list-body-migration").append(host)
  const app = createApp(wrapper)
  app.mount(host)
  await flushVue(nextTick)
  return {app, host, propsRef}
}

const listFrameSelector = `section.${opsListFrameClass.split(" ").join(".")}`
const alarmEvents = {filter: [], reset: 0}
const alarmMount = await mountCaller("OpsAlarms.vue", alarmProps, {
  onFilter: payload => alarmEvents.filter.push(payload),
  onReset_filters: () => {
    alarmEvents.reset += 1
  },
})
const alarmForm = alarmMount.host.querySelector("#alarm-filters")
const alarmBody = alarmForm.parentElement
const alarmFrame = alarmMount.host.querySelector(listFrameSelector)
const alarmConditions = alarmMount.host.querySelector("#alarm-conditions")
assert.equal(alarmBody.tagName, "DIV")
assert.deepEqual(elementAttributes(alarmBody), {class: opsListBodyFrameClass})
assert.strictEqual(alarmForm.parentElement, alarmBody)
assert.strictEqual(alarmFrame.parentElement, alarmBody)
assert.strictEqual(alarmConditions.parentElement, alarmFrame)
assert.equal(alarmBody.firstElementChild, alarmForm)
assert.deepEqual(elementAttributes(alarmFrame), {class: opsListFrameClass})
assert.deepEqual(
  [...alarmConditions.children].map(child => child.id),
  ["alarm-empty", "alarm-row-alpha", "alarm-row-bravo"],
)
assert.equal(alarmMount.host.querySelector("#alarm-severity").value, "critical")
assert.equal(alarmMount.host.querySelector("#alarm-state").value, "triggered")
assert.equal(alarmMount.host.querySelector("#alarm-spacecraft").value, "sc-1")
assert.equal(alarmMount.host.querySelector("#alarm-query").value, "alpha")
assert.equal(alarmMount.host.querySelector("#alarm-query").getAttribute("name"), "query")
assert.equal(alarmMount.host.querySelector("#alarm-evidence-alpha").getAttribute("href"), "/ops/alarms/alpha/evidence")
assert.equal(alarmMount.host.querySelector("#alarm-evidence-alpha").getAttribute("data-phx-link"), "redirect")
assert.equal(alarmMount.host.querySelector("#alarm-definition-alpha").getAttribute("data-phx-link-state"), "push")
const alarmSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(alarmForm.dispatchEvent(alarmSubmit), false)
const alarmSeverity = alarmMount.host.querySelector("#alarm-severity")
alarmSeverity.value = "warning"
alarmSeverity.dispatchEvent(new dom.window.Event("change", {bubbles: true}))
assert.deepEqual(alarmEvents.filter.at(-1), {filters: {severity: "warning", state: "triggered", spacecraft_id: "sc-1", query: "alpha"}})
alarmMount.host.querySelector("#alarm-reset").click()
assert.equal(alarmEvents.reset, 1)
const alarmAlpha = alarmMount.host.querySelector("#alarm-row-alpha")
const alarmBravo = alarmMount.host.querySelector("#alarm-row-bravo")
alarmMount.propsRef.value = {...alarmProps, alarms: [alarms[1], alarms[0]]}
await flushVue(nextTick)
assert.strictEqual(alarmMount.host.querySelector("#alarm-row-alpha"), alarmAlpha)
assert.strictEqual(alarmMount.host.querySelector("#alarm-row-bravo"), alarmBravo)
assert.deepEqual([...alarmConditions.children].map(child => child.id), ["alarm-empty", "alarm-row-bravo", "alarm-row-alpha"])

const commandEvents = {filter: [], reset: 0, follow: [], clear: 0}
const commandMount = await mountCaller("OpsCommands.vue", commandProps, {
  onFilter: payload => commandEvents.filter.push(payload),
  onReset_filters: () => {
    commandEvents.reset += 1
  },
  onFollow_command: payload => {
    commandEvents.follow.push(payload)
  },
  onClear_command_focus: () => {
    commandEvents.clear += 1
  },
})
const commandForm = commandMount.host.querySelector("#command-filters")
const commandBody = commandForm.parentElement
const commandFocus = commandMount.host.querySelector("#command-focus")
const commandFrame = commandMount.host.querySelector(listFrameSelector)
const commandRows = commandMount.host.querySelector("#command-rows")
assert.equal(commandBody.tagName, "DIV")
assert.deepEqual(elementAttributes(commandBody), {class: opsListBodyFrameClass})
assert.strictEqual(commandFocus.parentElement, commandBody)
assert.strictEqual(commandForm.parentElement, commandBody)
assert.strictEqual(commandFrame.parentElement, commandBody)
assert.strictEqual(commandRows.parentElement, commandFrame)
assert.equal(commandBody.firstElementChild, commandFocus)
assert.equal(commandFocus.getAttribute("data-followed-command"), "request-alpha")
assert.equal(commandMount.host.querySelector("#command-status").value, "queued")
assert.equal(commandMount.host.querySelector("#command-target").value, "target-1")
assert.equal(commandMount.host.querySelector("#command-query").value, "alpha")
assert.equal(commandMount.host.querySelector("#command-query").getAttribute("name"), "query")
assert.equal(commandMount.host.querySelector("#command-row-alpha details").tagName, "DETAILS")
assert.equal(commandMount.host.querySelector("#command-row-alpha summary").textContent.trim(), "Evidence alpha")
const commandSubmit = new dom.window.Event("submit", {bubbles: true, cancelable: true})
assert.equal(commandForm.dispatchEvent(commandSubmit), false)
commandMount.host.querySelector("#command-follow-alpha").click()
assert.deepEqual(commandEvents.follow, [{"command-request-id": "request-alpha"}])
commandMount.host.querySelector("#command-clear").click()
assert.equal(commandEvents.clear, 1)
commandMount.host.querySelector("#command-reset").click()
assert.equal(commandEvents.reset, 1)
const commandAlpha = commandMount.host.querySelector("#command-row-alpha")
const commandBravo = commandMount.host.querySelector("#command-row-bravo")
commandMount.propsRef.value = {...commandProps, commands: [commands[1], commands[0]]}
await flushVue(nextTick)
assert.strictEqual(commandMount.host.querySelector("#command-row-alpha"), commandAlpha)
assert.strictEqual(commandMount.host.querySelector("#command-row-bravo"), commandBravo)
assert.deepEqual([...commandRows.children].map(child => child.id), ["command-empty", "command-row-bravo", "command-row-alpha"])

assert.doesNotThrow(() => alarmMount.app.unmount())
assert.doesNotThrow(() => commandMount.app.unmount())
dom.window.close()

console.log(`ops_list_body_frame_migration_test passed (${scenarios.length} exact-DOM scenarios)`)

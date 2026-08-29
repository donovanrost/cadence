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
  opsListFrameCallerNames,
  opsListFrameClass,
  opsListFrameMigrationFor,
  opsListFrameMigrations,
  opsListFramePredecessorCommit,
  opsListFrameSha256,
  peelCadenceOpsListFrame,
} from "./ops_list_frame_test_support.mjs"

const scenarios = Object.freeze([
  "the exact predecessor resolves and is an ancestor of current HEAD",
  "exactly two audited callers import and use the frame",
  "the base has exactly two eligible roots and current sources have no third match",
  "both caller sources reconstruct the frozen predecessor bytes exactly",
  "real callers retain native roots, direct-child IDs, controls, links, and details",
  "keyed caller items retain native identity across reorder and reactive updates",
])

const pinnedNode = "/Users/donovanrost/.local/share/mise/installs/node/24.16.0/bin/node"
assert.equal(process.execPath, pinnedNode, "Ops list migration uses the pinned Node executable")
assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `Ops list migration uses pinned Node ${expectedNodeVersion}`,
)
assert.equal(scenarios.length, 6)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const vueDirectory = resolve(testDirectory, "../vue")
const nativeRoot = `<section class="${opsListFrameClass}">`
const occurrences = (source, fragment) => source.split(fragment).length - 1
const gitText = args => execFileSync("git", ["-C", repositoryRoot, ...args], {encoding: "utf8"})

assert.equal(
  gitText(["cat-file", "-t", opsListFramePredecessorCommit]).trim(),
  "commit",
  "the frozen Ops list predecessor resolves exactly as a commit",
)
assert.equal(
  gitText(["rev-parse", "--verify", `${opsListFramePredecessorCommit}^{commit}`]).trim(),
  opsListFramePredecessorCommit,
  "the frozen Ops list predecessor resolves to the requested object",
)
assert.doesNotThrow(
  () => gitText(["merge-base", "--is-ancestor", opsListFramePredecessorCommit, "HEAD"]),
  "the frozen Ops list predecessor is an ancestor of current HEAD",
)

assert.equal(opsListFrameMigrations.length, 2, "the owned caller ledger has exactly two files")
assert.deepEqual(
  [...opsListFrameCallerNames].sort(),
  ["OpsAlarms.vue", "OpsCommands.vue"],
  "the owned caller ledger is exactly OpsAlarms and OpsCommands",
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
  .filter(({source}) => /^import CadenceOpsListFrame\b/gm.test(source))
  .map(({file}) => file)
  .sort()

assert.deepEqual(
  importedCallers,
  ["OpsAlarms.vue", "OpsCommands.vue"],
  "exactly two callers import CadenceOpsListFrame",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/^import CadenceOpsListFrame\b/gm)?.length ?? 0),
    0,
  ),
  2,
  "the Vue source tree has exactly two frame imports",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<CadenceOpsListFrame\b/g)?.length ?? 0),
    0,
  ),
  2,
  "the Vue source tree has exactly two frame openings",
)
assert.equal(
  currentSources.reduce(
    (total, {source}) => total + (source.match(/<\/CadenceOpsListFrame>/g)?.length ?? 0),
    0,
  ),
  2,
  "the Vue source tree has exactly two frame closings",
)
assert.equal(
  currentSources.reduce((total, {source}) => total + occurrences(source, nativeRoot), 0),
  0,
  "no eligible native list root remains in current Vue sources",
)

const historicalVueFiles = gitText([
  "ls-tree",
  "-r",
  "--name-only",
  opsListFramePredecessorCommit,
  "apps/cadence_web/assets/vue",
])
  .trim()
  .split("\n")
  .filter(file => file.endsWith(".vue"))
  .map(file => file.slice("apps/cadence_web/assets/vue/".length))

const historicalEligibleRoots = historicalVueFiles.flatMap(file => {
  const source = gitText(["show", `${opsListFramePredecessorCommit}:apps/cadence_web/assets/vue/${file}`])
  const count = occurrences(source, nativeRoot)
  return count > 0 ? [{file, count}] : []
})

assert.equal(
  historicalEligibleRoots.reduce((total, {count}) => total + count, 0),
  2,
  "the frozen base has exactly two original eligible native list roots",
)
assert.deepEqual(
  historicalEligibleRoots,
  [
    {file: "OpsAlarms.vue", count: 1},
    {file: "OpsCommands.vue", count: 1},
  ],
  "the frozen base eligible roots are exactly the two audited callers",
)
assert.equal(
  new Set([
    ...historicalEligibleRoots.map(({file}) => file),
    ...currentSources
      .filter(({source}) => occurrences(source, nativeRoot) > 0)
      .map(({file}) => file),
  ]).size,
  2,
  "the current/base eligible-root union has no third match",
)

const dom = installDom('<main id="ops-list-migration"></main>')
for (const globalName of [
  "Document",
  "ShadowRoot",
  "HTMLFormElement",
  "HTMLInputElement",
  "HTMLSelectElement",
]) {
  Object.defineProperty(globalThis, globalName, {
    configurable: true,
    value: dom.window[globalName],
  })
}
const {createApp, defineComponent, h, nextTick, ref} = integrationRequire("vue")

const alarm = (id, pointName) => ({
  id,
  __dom_id: `alarm-row-${id}`,
  limit_event_id: `limit-${id}`,
  severity: "critical",
  limit_state: "triggered",
  state_label: "Triggered",
  point_name: pointName,
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

const alarms = [alarm("alpha", "Alpha point"), alarm("bravo", "Bravo point")]
const alarmProps = {
  page: {
    id: "ops-alarms-page",
    header: {eyebrow: "Operations", heading: "Alarms", copy: "Live alarms"},
    conditions_id: "alarm-conditions",
  },
  summary: {
    id: "alarm-summary",
    active_count: 2,
    observed: "2 observed",
    badges: [{severity: "critical", count: 2, label: "Critical"}],
  },
  filters: {
    id: "alarm-filters",
    values: {severity: "critical", state: "triggered", spacecraft_id: "sc-1", query: "alpha"},
    fields: {
      severity: {
        id: "alarm-severity",
        name: "severity",
        type: "select",
        label: "Severity",
        options: [{label: "Critical", value: "critical"}],
      },
      state: {
        id: "alarm-state",
        name: "state",
        type: "select",
        label: "State",
        options: [{label: "Triggered", value: "triggered"}],
      },
      spacecraft_id: {
        id: "alarm-spacecraft",
        name: "spacecraft_id",
        type: "select",
        label: "Spacecraft",
        options: [{label: "SC-1", value: "sc-1"}],
      },
      query: {
        id: "alarm-query",
        name: "query",
        type: "search",
        label: "Search",
        placeholder: "Search alarms",
        debounce_ms: 1,
      },
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
    action: {
      id: `command-follow-${id}`,
      label: "Follow",
      icon: "icon-follow",
      payload: {"command-request-id": `request-${id}`},
    },
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
  summary: {
    id: "command-summary",
    active_count: 2,
    observed: "2 observed",
    metrics: [{label: "Queued", value: 2, value_class: "text-info"}],
  },
  filters: {
    id: "command-filters",
    values: {status: "queued", target: "target-1", query: "alpha"},
    fields: {
      status: {
        id: "command-status",
        name: "status",
        type: "select",
        label: "Status",
        options: [{label: "Queued", value: "queued"}],
      },
      target: {
        id: "command-target",
        name: "target",
        type: "select",
        label: "Target",
        options: [{label: "Target 1", value: "target-1"}],
      },
      query: {
        id: "command-query",
        name: "query",
        type: "search",
        label: "Search",
        placeholder: "Search commands",
        debounce_ms: 1,
      },
    },
  },
  reset: {id: "command-reset", label: "Reset", payload: {}},
  focus_banner: null,
  empty: {id: "command-empty", icon: "icon-empty", heading: "No commands", copy: "No commands"},
  commands,
}

const mountCaller = async (file, props, listeners = {}) => {
  const componentPath = resolve(vueDirectory, file)
  const {component} = await loadSfc(componentPath)
  const propsRef = ref(props)
  const wrapper = defineComponent({
    name: `Mounted${file.replace(".vue", "")}`,
    setup() {
      return () => h(component, {...propsRef.value, ...listeners})
    },
  })
  const host = dom.window.document.createElement("div")
  host.id = `host-${file}`
  dom.window.document.querySelector("#ops-list-migration").append(host)
  const app = createApp(wrapper)
  app.mount(host)
  await flushVue(nextTick)
  return {app, host, propsRef}
}

const alarmEvents = {reset: 0}
const alarmMount = await mountCaller("OpsAlarms.vue", alarmProps, {
  onReset_filters: () => {
    alarmEvents.reset += 1
  },
})
const alarmFrame = alarmMount.host.querySelector(`section.${opsListFrameClass.split(" ").join(".")}`)
const alarmRoot = alarmMount.host.querySelector("#alarm-conditions").parentElement
assert.equal(alarmFrame.tagName, "SECTION")
assert.deepEqual(elementAttributes(alarmFrame), {class: opsListFrameClass})
assert.strictEqual(alarmFrame, alarmRoot)
assert.equal(alarmFrame.childElementCount, 1)
assert.equal(alarmFrame.firstElementChild.id, "alarm-conditions")
assert.deepEqual(
  [...alarmFrame.firstElementChild.children].map(child => child.id),
  ["alarm-empty", "alarm-row-alpha", "alarm-row-bravo"],
)
const alarmAlpha = alarmMount.host.querySelector("#alarm-row-alpha")
const alarmBravo = alarmMount.host.querySelector("#alarm-row-bravo")
assert.deepEqual(elementAttributes(alarmAlpha), {
  class: "grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 lg:grid-cols-[10rem_minmax(0,1fr)_12rem_12rem_auto] lg:items-center",
  "data-alarm-condition": "limit-alpha",
  "data-alarm-severity": "critical",
  "data-alarm-state": "triggered",
  id: "alarm-row-alpha",
})
assert.deepEqual(elementAttributes(alarmMount.host.querySelector("#alarm-evidence-alpha")), {
  class: "btn btn-ghost btn-xs",
  "data-phx-link": "redirect",
  "data-phx-link-state": "push",
  href: "/ops/alarms/alpha/evidence",
  id: "alarm-evidence-alpha",
  title: "Evidence alpha",
})
assert.equal(alarmMount.host.querySelector("#alarm-query").value, "alpha")
alarmMount.host.querySelector("#alarm-reset").click()
assert.equal(alarmEvents.reset, 1)

alarmMount.propsRef.value = {
  ...alarmProps,
  alarms: [alarms[1], alarms[0]],
}
await flushVue(nextTick)
assert.strictEqual(alarmMount.host.querySelector("#alarm-row-alpha"), alarmAlpha)
assert.strictEqual(alarmMount.host.querySelector("#alarm-row-bravo"), alarmBravo)
assert.deepEqual(
  [...alarmFrame.firstElementChild.children].map(child => child.id),
  ["alarm-empty", "alarm-row-bravo", "alarm-row-alpha"],
)

const commandEvents = {follow: [], clear: 0}
const commandMount = await mountCaller("OpsCommands.vue", commandProps, {
  onFollow_command: payload => {
    commandEvents.follow.push(payload)
  },
  onClear_command_focus: () => {
    commandEvents.clear += 1
  },
})
const commandFrame = commandMount.host.querySelector(`section.${opsListFrameClass.split(" ").join(".")}`)
const commandRoot = commandMount.host.querySelector("#command-rows").parentElement
assert.equal(commandFrame.tagName, "SECTION")
assert.deepEqual(elementAttributes(commandFrame), {class: opsListFrameClass})
assert.strictEqual(commandFrame, commandRoot)
assert.equal(commandFrame.childElementCount, 1)
assert.equal(commandFrame.firstElementChild.id, "command-rows")
assert.deepEqual(
  [...commandFrame.firstElementChild.children].map(child => child.id),
  ["command-empty", "command-row-alpha", "command-row-bravo"],
)
const commandAlpha = commandMount.host.querySelector("#command-row-alpha")
const commandBravo = commandMount.host.querySelector("#command-row-bravo")
assert.deepEqual(elementAttributes(commandAlpha), {
  class: "grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 xl:grid-cols-[9rem_minmax(0,1fr)_13rem_10rem_10rem_auto] xl:items-center",
  "data-command-request": "request-alpha",
  "data-command-state": "queued",
  id: "command-row-alpha",
})
assert.equal(commandMount.host.querySelector("#command-query").value, "alpha")
assert.equal(commandMount.host.querySelector("#command-row-alpha details").tagName, "DETAILS")
assert.equal(commandMount.host.querySelector("#command-row-alpha summary").textContent.trim(), "Evidence alpha")
commandMount.host.querySelector("#command-follow-alpha").click()
assert.deepEqual(commandEvents.follow, [{"command-request-id": "request-alpha"}])

commandMount.propsRef.value = {
  ...commandProps,
  commands: [commands[1], commands[0]],
}
await flushVue(nextTick)
assert.strictEqual(commandMount.host.querySelector("#command-row-alpha"), commandAlpha)
assert.strictEqual(commandMount.host.querySelector("#command-row-bravo"), commandBravo)
assert.deepEqual(
  [...commandFrame.firstElementChild.children].map(child => child.id),
  ["command-empty", "command-row-bravo", "command-row-alpha"],
)

for (const migration of opsListFrameMigrations) {
  const currentSource = await readFile(resolve(vueDirectory, migration.file), "utf8")
  const predecessor = peelCadenceOpsListFrame(currentSource, migration.file)
  const frozenSource = gitText(["show", `${opsListFramePredecessorCommit}:${migration.repositoryPath}`])

  assert.equal(
    Buffer.byteLength(frozenSource),
    migration.predecessorByteLength,
    `${migration.file} keeps its frozen predecessor byte count`,
  )
  assert.equal(
    opsListFrameSha256(frozenSource),
    migration.predecessorSha256,
    `${migration.file} keeps its frozen predecessor SHA-256`,
  )
  assert.equal(
    predecessor,
    frozenSource,
    `${migration.file} inverse reconstruction matches the exact predecessor bytes`,
  )
  assert.equal(
    opsListFrameSha256(predecessor),
    migration.predecessorSha256,
    `${migration.file} inverse reconstruction preserves its frozen SHA-256`,
  )
}

assert.doesNotThrow(() => alarmMount.app.unmount())
assert.doesNotThrow(() => commandMount.app.unmount())
dom.window.close()

console.log(`ops_list_frame_migration_test passed (${scenarios.length} exact-DOM scenarios)`)

import assert from "node:assert/strict"
import {existsSync, readFileSync} from "node:fs"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  expectedNodeVersion,
  installDom,
  integrationRequire,
} from "./reka_adapter_test_support.mjs"

assert.equal(
  process.versions.node,
  expectedNodeVersion,
  `DataLink inspector renderer contracts use pinned Node ${expectedNodeVersion}`,
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const rendererDirectory = resolve(testDirectory, "../vue/data_link_inspector")
const paths = {
  panel: resolve(testDirectory, "../vue/DataLinkInspectorPanel.vue"),
  rowSection: resolve(rendererDirectory, "RowSection.vue"),
  effectsList: resolve(rendererDirectory, "EffectsList.vue"),
  formPresentation: resolve(rendererDirectory, "FormPresentation.vue"),
}

const dom = installDom('<div id="renderer-contracts"></div>')
const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const {transformSync} = integrationRequire("esbuild")
const {createApp} = integrationRequire("vue")

const compileSfc = async (name, path, localModules = {}) => {
  const source = await readFile(path, "utf8")
  const parsed = parse(source, {filename: path})

  assert.deepEqual(parsed.errors, [], `${name} parses with the pinned Vue compiler`)
  assert.ok(parsed.descriptor.scriptSetup, `${name} keeps its typed setup contract`)
  assert.equal(parsed.descriptor.scriptSetup.lang, "ts")
  assert.ok(parsed.descriptor.template, `${name} keeps its native template contract`)

  const compiled = compileScript(parsed.descriptor, {
    id: `data-link-inspector-${name}`,
    inlineTemplate: true,
  })
  const transformed = transformSync(compiled.content, {
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

  return loadedModule.exports.default
}

const [RowSection, EffectsList] = await Promise.all([
  compileSfc("row-section", paths.rowSection),
  compileSfc("effects-list", paths.effectsList),
])
const FormPresentation = await compileSfc("form-presentation", paths.formPresentation, {
  "./EffectsList.vue": EffectsList,
})

const panelSource = await readFile(paths.panel, "utf8")
const parsedPanel = parse(panelSource, {filename: paths.panel})
assert.deepEqual(parsedPanel.errors, [], "DataLinkInspectorPanel parses with the pinned Vue compiler")
assert.doesNotThrow(() =>
  compileScript(parsedPanel.descriptor, {
    id: "data-link-inspector-panel",
    inlineTemplate: true,
    fs: {fileExists: existsSync, readFile: (path) => readFileSync(path, "utf8")},
  }),
)

const deepFreeze = (value) => {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value)
    Object.values(value).forEach(deepFreeze)
  }

  return value
}

const mount = (component, props) => {
  const frozenProps = deepFreeze(props)
  const before = JSON.stringify(frozenProps)
  const host = dom.window.document.createElement("div")
  dom.window.document.querySelector("#renderer-contracts").append(host)
  const app = createApp(component, frozenProps)
  app.mount(host)

  assert.equal(JSON.stringify(frozenProps), before, "renderer props remain immutable")
  assert.equal(host.children.length, 1, "renderer adds no wrapper element")

  return {
    root: host.firstElementChild,
    unmount() {
      app.unmount()
      host.remove()
    },
  }
}

const rowPresentation = {
  attrs: {id: "selection", class: "space-y-2", "data-data-link-selection": ""},
  heading: {class: "hud-label", text: "Selection"},
  list_class: "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
  rows: [
    {
      key: "State",
      label: {class: "text-base-content/60", text: "State"},
      value: {
        class: "font-mono text-base-content break-all",
        attrs: {"data-data-link-selection-field": "State"},
        text: "resolved",
      },
    },
    {
      key: "Target",
      label: {class: "text-base-content/60", text: "Target"},
      value: {
        class: "font-mono text-base-content break-all",
        attrs: {"data-data-link-selection-field": "Target"},
        text: "telemetry point",
      },
    },
  ],
}
const rowRenderer = mount(RowSection, {presentation: rowPresentation})
const rowRoot = rowRenderer.root

assert.equal(rowRoot.tagName, "SECTION")
assert.equal(rowRoot.id, "selection")
assert.equal(rowRoot.getAttribute("class"), "space-y-2")
assert.equal(rowRoot.getAttribute("data-data-link-selection"), "")
assert.equal(rowRoot.firstElementChild.tagName, "H3")
assert.equal(rowRoot.firstElementChild.textContent, "Selection")
assert.equal(rowRoot.lastElementChild.tagName, "DL")
assert.deepEqual(
  Array.from(rowRoot.querySelectorAll("dt, dd"), (element) => [element.tagName, element.textContent]),
  [
    ["DT", "State"],
    ["DD", "resolved"],
    ["DT", "Target"],
    ["DD", "telemetry point"],
  ],
)
assert.equal(
  rowRoot.querySelectorAll("dd")[1].getAttribute("data-data-link-selection-field"),
  "Target",
)
rowRenderer.unmount()

const effects = [
  {
    attrs: {
      class: "rounded border p-2 border-warning/30",
      "data-revision-decision-effect": "mark_conflict",
    },
    label: {class: "font-semibold uppercase tracking-wide", text: "Conflict"},
    summary: {
      attrs: {
        class: "text-base-content/75",
        "data-revision-decision-effect-summary": "mark_conflict",
      },
      text: "removes this identity from canonical reads until resolved",
    },
  },
  {
    attrs: {
      class: "rounded border p-2 border-success/30",
      "data-revision-decision-effect": "mark_canonical",
    },
    label: {class: "font-semibold uppercase tracking-wide", text: "Canonical"},
    summary: {
      attrs: {
        class: "text-base-content/75",
        "data-revision-decision-effect-summary": "mark_canonical",
      },
      text: "sets this identity canonical for default dashboard reads",
    },
  },
]
const effectsRenderer = mount(EffectsList, {
  id: "dashboard-revision-decision-effect-preview",
  effects,
  key_attribute: "data-revision-decision-effect",
})
const effectsRoot = effectsRenderer.root

assert.equal(effectsRoot.tagName, "DIV")
assert.equal(effectsRoot.id, "dashboard-revision-decision-effect-preview")
assert.equal(effectsRoot.getAttribute("class"), "grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2")
assert.deepEqual(
  Array.from(effectsRoot.children, (element) => element.getAttribute("data-revision-decision-effect")),
  ["mark_conflict", "mark_canonical"],
)
assert.deepEqual(
  Array.from(effectsRoot.children, (element) =>
    Array.from(element.children, (child) => child.textContent),
  ),
  [
    ["Conflict", "removes this identity from canonical reads until resolved"],
    ["Canonical", "sets this identity canonical for default dashboard reads"],
  ],
)
effectsRenderer.unmount()

const form = {
  attrs: {
    id: "dashboard-revision-decision-form",
    class: "space-y-3",
    "phx-submit": "apply_revision_decision",
  },
  hidden_fields: [
    {
      id: "dashboard-revision-decision-observation-identity-id",
      type: "hidden",
      name: "revision_decision[observation_identity_id]",
      value: "identity-1",
    },
    {
      id: "dashboard-revision-decision-source-event-id",
      type: "hidden",
      name: "revision_decision[source_decision_event_id]",
      value: "event-1",
    },
  ],
  fields: [
    {
      wrapper_class: "fieldset",
      label: {class: "hud-label block mb-1.5", text: "Decision"},
      attrs: {
        id: "revision_decision_decision",
        name: "revision_decision[decision]",
        required: false,
        multiple: false,
        class: "w-full select",
      },
      options: [
        {
          label: "Mark conflict",
          value: "mark_conflict",
          selected: true,
          disabled: false,
          title: null,
        },
        {
          label: "Mark canonical",
          value: "mark_canonical",
          selected: false,
          disabled: true,
          title: "Unavailable for this identity",
        },
      ],
    },
    {
      wrapper_class: "fieldset",
      label: {class: "hud-label block mb-1.5", text: "Reason"},
      attrs: {
        id: "revision_decision_decision_reason",
        name: "revision_decision[decision_reason]",
        type: "text",
        value: "operator_review",
        required: false,
        class: "w-full input",
      },
    },
  ],
  confirmation: {
    row: {
      attrs: {
        id: "dashboard-revision-decision-confirm-row",
        class: "flex items-start gap-2 rounded border border-warning/40 bg-base-100/70 p-2 text-xs",
      },
    },
    input: {
      attrs: {
        id: "dashboard-revision-decision-confirm",
        type: "checkbox",
        name: "revision_decision[confirmed]",
        value: "confirmed",
        required: true,
        class: "checkbox checkbox-xs mt-0.5",
      },
    },
    label: {class: "text-base-content/80", text: "Confirm telemetry revision decision"},
  },
  submit: {
    attrs: {
      id: "dashboard-revision-decision-submit",
      type: "submit",
      class: "btn btn-xs btn-warning btn-outline w-full justify-start",
    },
    icon_class: "hero-check-circle h-3.5 w-3.5",
    text: "Apply revision decision",
  },
}
const formRenderer = mount(FormPresentation, {
  presentation: form,
  effects,
  effects_id: "dashboard-revision-decision-effect-preview",
  effect_key_attribute: "data-revision-decision-effect",
})
const formRoot = formRenderer.root

assert.equal(formRoot.tagName, "FORM")
assert.equal(formRoot.id, "dashboard-revision-decision-form")
assert.equal(formRoot.getAttribute("phx-submit"), "apply_revision_decision")
assert.equal(formRoot.getAttribute("class"), "space-y-3")
assert.deepEqual(
  Array.from(formRoot.children, (element) => element.tagName),
  ["INPUT", "INPUT", "DIV", "DIV", "LABEL", "BUTTON"],
  "hidden fields, effects, visible fields, confirmation, and submit remain ordered",
)
assert.deepEqual(
  Array.from(formRoot.querySelectorAll(':scope > input[type="hidden"]'), (input) => [
    input.id,
    input.name,
    input.value,
  ]),
  [
    [
      "dashboard-revision-decision-observation-identity-id",
      "revision_decision[observation_identity_id]",
      "identity-1",
    ],
    [
      "dashboard-revision-decision-source-event-id",
      "revision_decision[source_decision_event_id]",
      "event-1",
    ],
  ],
)

const select = formRoot.querySelector("#revision_decision_decision")
const options = Array.from(select.options)
assert.equal(select.name, "revision_decision[decision]")
assert.equal(select.required, false)
assert.equal(select.multiple, false)
assert.deepEqual(options.map((option) => option.value), ["mark_conflict", "mark_canonical"])
assert.deepEqual(options.map((option) => option.selected), [true, false])
assert.deepEqual(options.map((option) => option.disabled), [false, true])
assert.deepEqual(options.map((option) => option.getAttribute("title")), [null, "Unavailable for this identity"])

const reason = formRoot.querySelector("#revision_decision_decision_reason")
assert.equal(reason.tagName, "INPUT")
assert.equal(reason.type, "text")
assert.equal(reason.name, "revision_decision[decision_reason]")
assert.equal(reason.value, "operator_review")
assert.equal(reason.required, false)

const confirmationRow = formRoot.querySelector("#dashboard-revision-decision-confirm-row")
const confirmation = confirmationRow.querySelector("input")
assert.deepEqual(
  Array.from(confirmationRow.children, (element) => element.tagName),
  ["INPUT", "SPAN"],
)
assert.equal(confirmation.type, "checkbox")
assert.equal(confirmation.name, "revision_decision[confirmed]")
assert.equal(confirmation.value, "confirmed")
assert.equal(confirmation.required, true)
assert.equal(confirmationRow.querySelector("span").textContent.trim(), "Confirm telemetry revision decision")

const submit = formRoot.querySelector("#dashboard-revision-decision-submit")
assert.equal(submit.type, "submit")
assert.equal(submit.querySelector("span").getAttribute("class"), "hero-check-circle h-3.5 w-3.5")
assert.equal(submit.textContent.trim(), "Apply revision decision")
assert.deepEqual(
  Array.from(
    formRoot.querySelector("#dashboard-revision-decision-effect-preview").children,
    (element) => element.getAttribute("data-revision-decision-effect"),
  ),
  ["mark_conflict", "mark_canonical"],
)

confirmation.checked = true
assert.deepEqual(Array.from(new dom.window.FormData(formRoot).entries()), [
  ["revision_decision[observation_identity_id]", "identity-1"],
  ["revision_decision[source_decision_event_id]", "event-1"],
  ["revision_decision[decision]", "mark_conflict"],
  ["revision_decision[decision_reason]", "operator_review"],
  ["revision_decision[confirmed]", "confirmed"],
])
formRenderer.unmount()

console.log("data_link_inspector_renderers_test passed")

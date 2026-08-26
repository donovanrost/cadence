import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import vm from "node:vm"

const scenarioLedger = Object.freeze([
  "both public component names remain compatibility wrappers",
  "one shared recursive renderer owns presentation node behavior",
  "the shared type describes only the recursive presentation DTO",
  "arbitrary tags raw attrs and node keys pass through unchanged",
  "recursive child keys text and ordering remain exact",
  "the renderer adds no events state sanitization or Phoenix interpretation",
])
const coveredScenarios = []
const cover = (name, callback) => {
  assert.equal(name, scenarioLedger[coveredScenarios.length])
  callback()
  coveredScenarios.push(name)
}

assert.equal(
  process.versions.node,
  "24.16.0",
  "CadencePresentationNode contracts use pinned Node 24.16.0",
)

const testDirectory = dirname(fileURLToPath(import.meta.url))
const runtimeContextWrapperPath = resolve(
  testDirectory,
  "../vue/DashboardRuntimeContextSelector.vue",
)
const selectedDatumWrapperPath = resolve(
  testDirectory,
  "../vue/DashboardSelectedDatumActions.vue",
)
const componentPath = resolve(
  testDirectory,
  "../vue/ui/components/CadencePresentationNode.vue",
)
const typesPath = resolve(testDirectory, "../vue/ui/presentation_types.ts")
const registryPath = resolve(testDirectory, "../vue/index.ts")

const [runtimeContextWrapper, selectedDatumWrapper, componentSource, typesSource, registrySource] =
  await Promise.all([
    readFile(runtimeContextWrapperPath, "utf8"),
    readFile(selectedDatumWrapperPath, "utf8"),
    readFile(componentPath, "utf8"),
    readFile(typesPath, "utf8"),
    readFile(registryPath, "utf8"),
  ])

const wrapperSources = [runtimeContextWrapper, selectedDatumWrapper]

cover("both public component names remain compatibility wrappers", () => {
  assert.match(registrySource, /import\.meta\.glob\("\.\/\*\*\/\*\.vue", \{eager: true\}\)/)

  for (const source of wrapperSources) {
    assert.match(
      source,
      /import CadencePresentationNode from "\.\/ui\/components\/CadencePresentationNode\.vue"/,
    )
    assert.match(source, /import type \{PresentationNode\} from "\.\/ui\/presentation_types"/)
    assert.match(source, /defineProps<\{presentation: PresentationNode\}>\(\)/)
    assert.match(source, /<CadencePresentationNode :node="props\.presentation" \/>/)
    assert.doesNotMatch(source, /PresentationNodeRenderer|defineComponent|\bh\(/)
  }
})

cover("one shared recursive renderer owns presentation node behavior", () => {
  assert.equal((componentSource.match(/defineComponent\(/g) || []).length, 1)
  assert.match(componentSource, /name: "CadencePresentationNode"/)
  assert.match(componentSource, /node: \{type: Object as PropType<PresentationNode>, required: true\}/)
  assert.match(componentSource, /componentProps\.node\.tag/)
  assert.match(componentSource, /\.\.\.componentProps\.node\.attrs, key: componentProps\.node\.key/)
  assert.match(componentSource, /componentProps\.node\.children\.map\(\(child\) =>/)
  assert.match(componentSource, /h\(CadencePresentationNode, \{key: child\.key, node: child\}\)/)
  assert.doesNotMatch(runtimeContextWrapper, /type PresentationNode\s*=/)
  assert.doesNotMatch(selectedDatumWrapper, /type PresentationNode\s*=/)
})

cover("the shared type describes only the recursive presentation DTO", () => {
  assert.equal((typesSource.match(/export type /g) || []).length, 1)
  assert.match(
    typesSource,
    /export type PresentationNode = \{\n  key: string\n  tag: string\n  attrs: Record<string, string>\n  children: Array<string \| PresentationNode>\n\}/,
  )
})

const componentScript = componentSource.match(/<script lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
assert.ok(componentScript, "CadencePresentationNode.vue must have a TypeScript script block")

const executableComponentScript = componentScript
  .replace(/^import .*$/gm, "")
  .replace("Object as PropType<PresentationNode>", "Object")
  .replace(
    "export default CadencePresentationNode",
    "globalThis.CadencePresentationNode = CadencePresentationNode",
  )

const renderContext = {
  defineComponent: (options) => options,
  h: undefined,
}
vm.createContext(renderContext)
vm.runInContext(executableComponentScript, renderContext, {filename: componentPath})

const component = renderContext.CadencePresentationNode
renderContext.h = (type, props, children) => {
  if (type === component) {
    return {
      kind: "component",
      key: props.key,
      rendered: type.setup({node: props.node})(),
    }
  }

  return {kind: "element", tag: type, props, children}
}

const presentation = {
  key: "root-key",
  tag: "cadence-arbitrary-root",
  attrs: {
    id: "server-root",
    class: "server classes remain raw",
    "data-payload": "<opaque>&\"value\"",
    "phx-click": "server-owned-event",
  },
  children: [
    "leading text",
    {
      key: "child-key",
      tag: "server-selected-child",
      attrs: {title: "raw title", "aria-label": "server label"},
      children: [
        "nested prefix",
        {
          key: "grandchild-key",
          tag: "mark",
          attrs: {class: "server-mark"},
          children: ["grandchild text"],
        },
        "nested suffix",
      ],
    },
    "trailing text",
  ],
}
const originalPresentation = structuredClone(presentation)
const rendered = component.setup({node: presentation})()

cover("arbitrary tags raw attrs and node keys pass through unchanged", () => {
  assert.equal(rendered.kind, "element")
  assert.equal(rendered.tag, "cadence-arbitrary-root")
  assert.deepEqual({...rendered.props}, {...presentation.attrs, key: "root-key"})

  const renderedChild = rendered.children[1]
  assert.equal(renderedChild.kind, "component")
  assert.equal(renderedChild.key, "child-key")
  assert.equal(renderedChild.rendered.tag, "server-selected-child")
  assert.deepEqual({...renderedChild.rendered.props}, {
    ...presentation.children[1].attrs,
    key: "child-key",
  })
  assert.deepEqual(presentation, originalPresentation, "rendering must not mutate the server DTO")
})

cover("recursive child keys text and ordering remain exact", () => {
  assert.deepEqual(
    Array.from(rendered.children, (child) =>
      typeof child === "string" ? child : child.key,
    ),
    ["leading text", "child-key", "trailing text"],
  )

  const renderedChild = rendered.children[1].rendered
  assert.deepEqual(
    Array.from(renderedChild.children, (child) =>
      typeof child === "string" ? child : child.key,
    ),
    ["nested prefix", "grandchild-key", "nested suffix"],
  )

  const renderedGrandchild = renderedChild.children[1]
  assert.equal(renderedGrandchild.key, "grandchild-key")
  assert.equal(renderedGrandchild.rendered.tag, "mark")
  assert.deepEqual(Array.from(renderedGrandchild.rendered.children), ["grandchild text"])
})

cover("the renderer adds no events state sanitization or Phoenix interpretation", () => {
  assert.doesNotMatch(
    componentSource,
    /defineEmits|emit\(|ref\(|reactive\(|computed\(|watch\(|onMounted|onBeforeUnmount/,
  )
  assert.doesNotMatch(componentSource, /sanitize|escape|allowlist|denylist|v-html|innerHTML/)
  assert.doesNotMatch(componentSource, /phx-|LiveView|route|reka-ui/)
  assert.equal(rendered.props["phx-click"], "server-owned-event")
  assert.equal(rendered.props["data-payload"], "<opaque>&\"value\"")
})

assert.deepEqual(coveredScenarios, scenarioLedger)
console.log(`cadence_presentation_node_test passed (${scenarioLedger.length} scenarios)`)

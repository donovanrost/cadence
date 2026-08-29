import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarios = Object.freeze([
  "the frozen production parent is the exact attested source authority",
  "DashboardCanvas peels the keyed CadenceCollapsible layer before predecessor comparison",
  "DashboardGrid peels the sectionOpen prop watcher before predecessor comparison",
  "presentation peels only the named data-state chevron selector",
  "all three reconstructed sources retain their frozen SHA-256 values",
])

assert.equal(scenarios.length, 5)

const frozenParent = "0f3e44c78250511758a27a5f150792ba0791719a"
const testDirectory = dirname(fileURLToPath(import.meta.url))
const repositoryRoot = resolve(testDirectory, "../../../..")
const files = Object.freeze({
  canvas: {
    relativePath: "apps/cadence_web/assets/vue/DashboardCanvas.vue",
    sha256: "c8233b02420c5796450efe8c1cc6f329cde706ba065d7611dbdec80bdb5c909f",
  },
  grid: {
    relativePath: "apps/cadence_web/assets/vue/DashboardGrid.vue",
    sha256: "cdf039198a03d8233687ccae498bdcf3748e4d2312ffcee862f74d18f7ecee02",
  },
  presentation: {
    relativePath:
      "apps/cadence_web/lib/cadence_web/live/ops_dashboard_show_live/dashboard_canvas_presentation.ex",
    sha256: "f24ac2d4a7030f9294fe2c5cfb737b6f17fb2accfa16c27bdd26a7fe9f92b8c7",
  },
})
const sha256 = (source) => createHash("sha256").update(source).digest("hex")
const occurrences = (source, fragment) => source.split(fragment).length - 1
const replaceOnce = (source, migrated, predecessor, label) => {
  assert.equal(occurrences(source, migrated), 1, `${label} migrated layer occurs exactly once`)
  return source.replace(migrated, predecessor)
}

const peelDashboardCanvas = (source) => {
  const migratedImports = `import {reactive} from "vue"

import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"
import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"
import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"
`
  const migratedState = `const sectionOpenByKey = reactive(new Map())
const sectionOpen = (group) => {
  if (!sectionOpenByKey.has(group.key)) {
    sectionOpenByKey.set(group.key, Object.hasOwn(group.section.root.attrs, "open"))
  }

  return sectionOpenByKey.get(group.key)
}
const rememberSectionOpen = (group, open) => {
  sectionOpenByKey.set(group.key, open)
}
const sectionContentId = (group) => \`${"${group.section.root.attrs.id}"}-content\`
const sectionRootAttrs = (group) => {
  const {open: _serverOpen, ...attrs} = group.section.root.attrs
  return attrs
}`
  const predecessorState = `const sectionOpenByKey = new Map()
const sectionOpen = (group) =>
  sectionOpenByKey.has(group.key)
    ? sectionOpenByKey.get(group.key)
    : Object.hasOwn(group.section.root.attrs, "open")
const rememberSectionOpen = (group, event) => {
  sectionOpenByKey.set(group.key, event.currentTarget.open)
}`
  const migratedTemplate = `        <CadenceCollapsible
          v-if="group.section"
          :content-id="sectionContentId(group)"
          :open="sectionOpen(group)"
          :unmount-on-hide="false"
          @request-change="rememberSectionOpen(group, $event)"
        >
          <div v-bind="sectionRootAttrs(group)">
            <CadenceCollapsibleTrigger>
              <button type="button" v-bind="group.section.summary.attrs">
                <span v-bind="group.section.summary.icon.attrs"></span>
                <div v-bind="group.section.summary.copy.attrs">
                  <h2 v-bind="group.section.summary.copy.title.attrs">{{
                    group.section.summary.copy.title.text
                  }}</h2>
                  <p
                    v-if="group.section.summary.copy.description"
                    v-bind="group.section.summary.copy.description.attrs"
                  >{{ group.section.summary.copy.description.text }}</p>
                </div>
                <span
                  v-if="group.section.summary.count"
                  v-bind="group.section.summary.count.attrs"
                >{{ group.section.summary.count.text }}</span>
              </button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>
              <div class="contents">
                <DashboardGrid
                  :presentation="group.grid"
                  :section-open="sectionOpen(group)"
                  @layout_changed="forwardLayoutChanged"
                />
              </div>
            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>`
  const predecessorTemplate = `        <details
          v-if="group.section"
          v-bind="group.section.root.attrs"
          :open="sectionOpen(group)"
          @toggle="rememberSectionOpen(group, $event)"
        >
          <summary v-bind="group.section.summary.attrs">
            <span v-bind="group.section.summary.icon.attrs"></span>
            <div v-bind="group.section.summary.copy.attrs">
              <h2 v-bind="group.section.summary.copy.title.attrs">{{
                group.section.summary.copy.title.text
              }}</h2>
              <p
                v-if="group.section.summary.copy.description"
                v-bind="group.section.summary.copy.description.attrs"
              >{{ group.section.summary.copy.description.text }}</p>
            </div>
            <span
              v-if="group.section.summary.count"
              v-bind="group.section.summary.count.attrs"
            >{{ group.section.summary.count.text }}</span>
          </summary>

          <DashboardGrid
            :presentation="group.grid"
            @layout_changed="forwardLayoutChanged"
          />
        </details>`

  let reconstructed = replaceOnce(
    source,
    migratedTemplate,
    predecessorTemplate,
    "DashboardCanvas template",
  )
  reconstructed = replaceOnce(
    reconstructed,
    migratedState,
    predecessorState,
    "DashboardCanvas keyed state",
  )
  reconstructed = replaceOnce(
    reconstructed,
    migratedImports,
    "",
    "DashboardCanvas adapter imports",
  )
  assert.doesNotMatch(reconstructed, /CadenceCollapsible|sectionContentId|sectionRootAttrs|reactive/)
  return reconstructed
}

const peelDashboardGrid = (source) => {
  const predecessorSectionMount = `    this.sectionDetails = this.el.closest && this.el.closest("details[data-dashboard-section]")
    if (this.sectionDetails) {
      this.handleSectionToggle = () => {
        if (this.sectionResizeFrame !== null) {
          cancelAnimationFrame(this.sectionResizeFrame)
          this.sectionResizeFrame = null
        }
        if (!this.sectionDetails.open) return
        this.sectionResizeFrame = requestAnimationFrame(() => {
          this.sectionResizeFrame = null
          this.grid.prevWidth = undefined
          this.grid.onResize()
        })
      }
      this.sectionDetails.addEventListener("toggle", this.handleSectionToggle)
    }
`
  const predecessorSectionDestroy = `    if (this.sectionResizeFrame !== null) {
      cancelAnimationFrame(this.sectionResizeFrame)
      this.sectionResizeFrame = null
    }
    if (this.sectionDetails && this.handleSectionToggle) {
      this.sectionDetails.removeEventListener("toggle", this.handleSectionToggle)
    }
`
  const migratedResizeMethod = `
  cancelSectionResize() {
    if (this.sectionResizeFrame !== null) {
      cancelAnimationFrame(this.sectionResizeFrame)
      this.sectionResizeFrame = null
    }
  },

  scheduleSectionResize() {
    this.cancelSectionResize()

    this.sectionResizeFrame = requestAnimationFrame(() => {
      this.sectionResizeFrame = null
      this.grid.prevWidth = undefined
      this.grid.onResize()
    })
  },
`
  const migratedWatcher = `
watch(
  () => props.sectionOpen,
  (open, previousOpen) => {
    if (!controller || open === previousOpen) return
    if (open && previousOpen === false) {
      controller.scheduleSectionResize()
    } else if (!open) {
      controller.cancelSectionResize()
    }
  },
  {flush: "post"},
)
`

  let reconstructed = replaceOnce(
    source,
    'import {onBeforeUnmount, onMounted, onUpdated, ref, watch} from "vue"',
    'import {onBeforeUnmount, onMounted, onUpdated, ref} from "vue"',
    "DashboardGrid Vue import",
  )
  reconstructed = replaceOnce(
    reconstructed,
    `    this.grid.on("change", () => this.scheduleLayoutPush())
    this.grid.on("dragstop resizestop", () => this.updated())
    this.syncEditMode()
`,
    `    this.grid.on("change", () => this.scheduleLayoutPush())
    this.grid.on("dragstop resizestop", () => this.updated())
    this.syncEditMode()
${predecessorSectionMount}`,
    "DashboardGrid native section mount",
  )
  reconstructed = replaceOnce(
    reconstructed,
    "    clearTimeout(this.pushTimer)\n    this.cancelSectionResize()\n",
    `    clearTimeout(this.pushTimer)\n${predecessorSectionDestroy}`,
    "DashboardGrid native section destroy",
  )
  reconstructed = replaceOnce(
    reconstructed,
    migratedResizeMethod,
    "",
    "DashboardGrid prop-driven resize method",
  )
  reconstructed = replaceOnce(
    reconstructed,
    "  presentation: {type: Object, required: true},\n  sectionOpen: {type: Boolean, default: true},",
    "  presentation: {type: Object, required: true},",
    "DashboardGrid sectionOpen prop",
  )
  reconstructed = replaceOnce(
    reconstructed,
    migratedWatcher,
    "",
    "DashboardGrid sectionOpen watcher",
  )
  assert.doesNotMatch(reconstructed, /sectionOpen|scheduleSectionResize|\bwatch\b/)
  return reconstructed
}

const peelPresentation = (source) =>
  replaceOnce(
    source,
    "group-data-[state=open]/dashboard-section:rotate-90",
    "group-open/dashboard-section:rotate-90",
    "presentation chevron state selector",
  )

const currentSources = Object.fromEntries(
  await Promise.all(
    Object.entries(files).map(async ([name, file]) => [
      name,
      await readFile(resolve(repositoryRoot, file.relativePath), "utf8"),
    ]),
  ),
)
const parentSources = Object.fromEntries(
  Object.entries(files).map(([name, file]) => [
    name,
    execFileSync("git", ["show", `${frozenParent}:${file.relativePath}`], {
      cwd: repositoryRoot,
      encoding: "utf8",
    }),
  ]),
)
const reconstructedSources = {
  canvas: peelDashboardCanvas(currentSources.canvas),
  grid: peelDashboardGrid(currentSources.grid),
  presentation: peelPresentation(currentSources.presentation),
}

for (const [name, file] of Object.entries(files)) {
  assert.equal(sha256(parentSources[name]), file.sha256, `${name} frozen parent SHA-256`)
  assert.equal(sha256(reconstructedSources[name]), file.sha256, `${name} inverse SHA-256`)
  assert.equal(
    reconstructedSources[name],
    parentSources[name],
    `${name} reconstructs ${frozenParent} byte-for-byte`,
  )
}

console.log(
  `dashboard_canvas_section_disclosures_migration_test passed (${scenarios.length} scenarios; ` +
    `3 exact ${frozenParent} reconstructions)`,
)

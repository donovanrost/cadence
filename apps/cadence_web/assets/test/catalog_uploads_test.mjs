import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {stripTypeScriptTypes} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"
import {
  flushVue,
  installDom,
  integrationRequire,
  loadSfc,
} from "./reka_adapter_test_support.mjs"

const scenarioLedger = [
  "new database and add revision are non-SSR catalog-owned LiveVue surfaces",
  "the installed useLiveUpload composable owns selection entries progress validity and submission",
  "cancellation remains the exact cancel_upload LiveView event through an explicit Vue emit",
  "Phoenix retains allow_upload validation importer detection persistence navigation and toggle decisions",
  "both uploads remain any type one file and 50 MiB with non-auto upload behavior",
  "catalog_database and catalog_revision field names nesting IDs types copy and classes stay exact",
  "upload and entry errors remain server-mapped into the exact existing user-facing messages",
  "detected unsupported and empty importer presentation branches remain server-authoritative",
  "submit disabled state is authored by Phoenix from the detected importer result",
  "the add-revision CadenceCollapsible is controlled only by Phoenix revision_form_open",
  "the trigger requests exactly toggle-revision-form without optimistic local state",
  "closed content unmounts and reopening creates a fresh CatalogUploadForm lifecycle",
  "the add-revision trigger and upload slot retain their exact DOM identities and structure",
  "the new database cancel route and add-revision toggle remain exact",
  "existing catalog save persistence metadata redirect and failure behavior is byte-pinned by source slice",
  "focused LiveView scenarios still exercise unsupported supported persistence cancellation and scope",
  "the authenticated catalog LiveSession route and mission-sidebar layout remain untouched",
  "only catalog LiveViews components Vue files and focused tests are mutable in this slice",
]

assert.equal(process.versions.node, "24.16.0", "catalog upload contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 18)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  uploadForm: resolve(__dirname, "../vue/CatalogUploadForm.vue"),
  databaseNew: resolve(__dirname, "../vue/CatalogDatabaseNew.vue"),
  databaseShow: resolve(__dirname, "../vue/CatalogDatabaseShow.vue"),
  collapsibleRoot: resolve(__dirname, "../vue/ui/reka/CadenceCollapsible.vue"),
  collapsibleTrigger: resolve(__dirname, "../vue/ui/reka/CadenceCollapsibleTrigger.vue"),
  collapsibleContent: resolve(__dirname, "../vue/ui/reka/CadenceCollapsibleContent.vue"),
  newLive: resolve(
    __dirname,
    "../../lib/cadence_web/live/catalog/catalog_database_new_live.ex",
  ),
  showLive: resolve(
    __dirname,
    "../../lib/cadence_web/live/catalog/catalog_database_show_live.ex",
  ),
  components: resolve(__dirname, "../../lib/cadence_web/live/catalog/components.ex"),
  newTest: resolve(
    __dirname,
    "../../test/cadence_web/live/catalog/catalog_database_new_live_test.exs",
  ),
  showTest: resolve(
    __dirname,
    "../../test/cadence_web/live/catalog/catalog_database_show_live_test.exs",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
}

const {
  uploadForm,
  databaseNew,
  databaseShow,
  collapsibleRoot,
  collapsibleTrigger,
  collapsibleContent,
  newLive,
  showLive,
  components,
  newTest,
  showTest,
  router,
} = Object.fromEntries(
  await Promise.all(
    Object.entries(paths).map(async ([name, path]) => [name, await readFile(path, "utf8")]),
  ),
)

const sha256 = (source) => createHash("sha256").update(source).digest("hex")

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} remains source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertBalancedTemplate = (source, label) => {
  const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]
  assert.ok(template, `${label} keeps a template block`)

  const stack = []
  const voidElements = new Set([
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
  ])

  for (const match of template.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${label}: ${name} closes the current element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], `${label} template tags are balanced`)
}

const assertScriptSyntax = (source, label) => {
  const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
  assert.ok(script, `${label} keeps a TypeScript setup block`)

  const withoutImports = script.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  const javascript = stripTypeScriptTypes(withoutImports, {mode: "strip"})

  assert.doesNotThrow(() => new Function(javascript), `${label} setup syntax parses`)
}

for (const [label, source] of [
  ["CatalogUploadForm.vue", uploadForm],
  ["CatalogDatabaseNew.vue", databaseNew],
  ["CatalogDatabaseShow.vue", databaseShow],
]) {
  assertBalancedTemplate(source, label)
  assertScriptSyntax(source, label)
}

const {compileScript, parse} = integrationRequire("@vue/compiler-sfc")
const parsedDatabaseShow = parse(databaseShow, {filename: paths.databaseShow})
assert.deepEqual(parsedDatabaseShow.errors, [], "CatalogDatabaseShow parses with pinned Vue")
assert.doesNotThrow(
  () => compileScript(parsedDatabaseShow.descriptor, {id: "catalog-database-show", inlineTemplate: true}),
  "CatalogDatabaseShow compiles with the pinned Vue template compiler",
)

assert.match(uploadForm, /^import \{computed, reactive, ref\} from "vue"$/m)
assert.match(uploadForm, /^import \{useLiveUpload\} from "live_vue"$/m)
assert.equal(uploadForm.match(/useLiveUpload\(/g)?.length, 1)
assert.match(
  uploadForm,
  /useLiveUpload\(\s*\(\) => props\.upload,\s*\{\s*changeEvent: "validate",\s*submitEvent: "save",?\s*\}/s,
)
assert.match(uploadForm, /entries,\s*progress,\s*addFiles,\s*submit,\s*clear,\s*inputEl,/s)
assert.match(uploadForm, /valid: uploadValid/)
assert.match(uploadForm, /document\.getElementById\(props\.upload\.ref\)/)
assert.match(uploadForm, /inputEl\.value = serverUploadInput/)
assert.match(uploadForm, /addFiles\(Array\.from\(files\)\)/)
assert.match(uploadForm, /emit\("cancel-upload", \{ref\}\)/)
assert.match(uploadForm, /emit\("validate", \{\[props\.form\.name\]: formValues\(\)\}\)/)
assert.match(uploadForm, /hiddenField\.name = field\.name/)
assert.match(uploadForm, /hiddenField\.value = values\[field\.key\] \?\? ""/)
assert.match(uploadForm, /if \(props\.submit_disabled \|\| !syncHiddenFormFields\(\)\) return/)
assert.match(uploadForm, /\n  submit\(\)\n/)
assert.match(uploadForm, /:name="form\.file_input\.name"/)
assert.match(uploadForm, /:accept="upload\.accept \|\| undefined"/)
assert.match(uploadForm, /:multiple="upload\.max_entries > 1"/)
assert.match(uploadForm, /:aria-invalid="!uploadValid"/)
assert.match(uploadForm, /<progress\s+:value="progress"\s+max="100"/s)
assert.match(uploadForm, /\{\{ entry\.client_name \}\} \(\{\{ entry\.client_type \|\| "unknown" \}\}\)/)
assert.match(uploadForm, /No importer supports this file\. Accepted formats: YAML/)
assert.match(uploadForm, /Select a file to see the detected importer\./)
assert.match(uploadForm, /Detected importer:/)
assert.match(uploadForm, /:disabled="submit_disabled"/)
assert.doesNotMatch(uploadForm, /fetch\(|axios|useRouter|useRoute|window\.location/)

assert.match(databaseNew, /^import CatalogUploadForm from "\.\/CatalogUploadForm\.vue"$/m)
assert.match(
  databaseNew,
  /^import CadenceFormPageFrame from "\.\/ui\/components\/CadenceFormPageFrame\.vue"$/m,
)
assert.equal(databaseNew.match(/<CatalogUploadForm\b/g)?.length, 1)
assert.match(databaseNew, /<CadenceFormPageFrame :id="page\.id">/)
assert.doesNotMatch(databaseNew, /<div :id="page\.id" class="space-y-6 max-w-2xl">/)
assert.match(databaseNew, /@validate="emit\('validate', \$event\)"/)
assert.match(databaseNew, /@cancel-upload="emit\('cancel-upload', \$event\)"/)
assert.match(databaseNew, /:id="page\.cancel\.id"/)
assert.match(databaseNew, /data-phx-link="redirect"/)
assert.match(databaseNew, /data-phx-link-state="push"/)

assert.match(databaseShow, /^import CatalogUploadForm from "\.\/CatalogUploadForm\.vue"$/m)
assert.match(
  databaseShow,
  /^import CadenceCollapsible from "\.\/ui\/reka\/CadenceCollapsible\.vue"$/m,
)
assert.match(
  databaseShow,
  /^import CadenceCollapsibleContent from "\.\/ui\/reka\/CadenceCollapsibleContent\.vue"$/m,
)
assert.match(
  databaseShow,
  /^import CadenceCollapsibleTrigger from "\.\/ui\/reka\/CadenceCollapsibleTrigger\.vue"$/m,
)
assert.doesNotMatch(databaseShow, /from "reka-ui"/)
assert.equal(databaseShow.match(/<CatalogUploadForm\b/g)?.length, 1)
assert.match(databaseShow, /@validate="emit\('validate', \$event\)"/)
assert.match(databaseShow, /@cancel-upload="emit\('cancel-upload', \$event\)"/)
assert.doesNotMatch(databaseShow, /<slot name="revision_form"/)

for (const adapter of [
  "CadenceCollapsible",
  "CadenceCollapsibleTrigger",
  "CadenceCollapsibleContent",
]) {
  assert.equal(
    databaseShow.match(new RegExp(`<${adapter}\\b`, "g"))?.length,
    1,
    `${adapter} is composed exactly once`,
  )
}

assert.match(
  databaseShow,
  /<CadenceCollapsible\s+content-id="catalog-revision-upload-slot"\s+:open="revision_form_open"\s+@request-change="emit\('toggle-revision-form', \{\}\)"\s*>\s*<div id="catalog-database-show-surface" class="space-y-6">/s,
)
assert.equal(
  databaseShow.match(/content-id="catalog-revision-upload-slot"/g)?.length,
  1,
  "the controlled root owns the one stable content ID source",
)
assert.equal(
  databaseShow.match(/@request-change="emit\('toggle-revision-form', \{\}\)"/g)?.length,
  1,
  "the adapter request maps to the Phoenix toggle intent exactly once",
)
assert.doesNotMatch(databaseShow, /\b(?:CollapsibleRoot|CollapsibleTrigger|CollapsibleContent)\b/)
assert.doesNotMatch(databaseShow, /as-child|aria-controls="catalog-revision-upload-slot"/)
assert.doesNotMatch(databaseShow, /v-model(?::open)?|default-open|force-?mount/i)
assert.doesNotMatch(databaseShow, /unmount-on-hide/)
assert.doesNotMatch(databaseShow, /v-if="revision_form_open"/)
assert.doesNotMatch(databaseShow, /\b(?:computed|reactive|ref|watch)\s*\(/)

const toggleSource = sourceSlice(
  databaseShow,
  "          <CadenceCollapsibleTrigger>",
  "          </CadenceCollapsibleTrigger>",
  "add revision trigger",
)

assert.match(
  toggleSource,
  /<button\s+id="add-revision-toggle"\s+type="button"\s+class="btn"\s+:class="revision_form_open \? 'btn-ghost' : 'btn-primary'"\s*>/s,
)
assert.match(toggleSource, /\{\{ revision_form_open \? "Cancel" : "\+ Add revision" \}\}/)
assert.doesNotMatch(toggleSource, /@click|emit\(/)

const uploadSlotSource = sourceSlice(
  databaseShow,
  "    <CadenceCollapsibleContent>",
  "    </CadenceCollapsibleContent>",
  "revision upload collapsible content",
)

assert.match(
  uploadSlotSource,
  /<CadenceCollapsibleContent>\s*<div>\s*<CatalogUploadForm/s,
)
assert.doesNotMatch(uploadSlotSource, /v-if|v-show|force-?mount/i)
assert.doesNotMatch(uploadSlotSource, /\bid=/)
assert.equal(databaseShow.match(/id="add-revision-toggle"/g)?.length, 1)
assert.equal(databaseShow.match(/catalog-revision-upload-slot/g)?.length, 1)
assert.match(collapsibleRoot, /:unmount-on-hide="true"/)
assert.match(collapsibleTrigger, /:aria-controls="collapsible\.contentId\.value"/)
assert.match(collapsibleContent, /:id="collapsible\.contentId\.value"/)

assert.deepEqual(
  Array.from(databaseShow.matchAll(/\bemit\('([^']+)'/g), ([, event]) => event),
  ["toggle-revision-form", "validate", "cancel-upload"],
  "the disclosure and upload bridge emit exactly the three Phoenix-owned events",
)

const emitsBlock = databaseShow.match(/const emit = defineEmits<\{([\s\S]*?)\}>\(\)/)?.[1]
assert.ok(emitsBlock, "CatalogDatabaseShow keeps an auditable emit contract")
assert.equal(
  emitsBlock.trim(),
  [
    '"toggle-revision-form": [payload: Record<string, never>]',
    "validate: [payload: Record<string, Record<string, string>>]",
    '"cancel-upload": [payload: {ref: string}]',
  ].join("\n  "),
)

for (const hrefBinding of [
  "navigation.mission.href",
  "navigation.catalog.href",
  "revision.href",
  "run.href",
]) {
  assert.match(
    databaseShow,
    new RegExp(
      `:href="${hrefBinding.replaceAll(".", "\\.")}"\\s+data-phx-link="redirect"\\s+data-phx-link-state="push"`,
      "s",
    ),
    `${hrefBinding} retains the server-authored LiveView navigation attributes`,
  )
}

assert.equal(databaseShow.match(/data-phx-link="redirect"/g)?.length, 4)
assert.equal(databaseShow.match(/data-phx-link-state="push"/g)?.length, 4)

for (const [label, source, componentName] of [
  ["new database", newLive, "CatalogDatabaseNew"],
  ["database show", showLive, "CatalogDatabaseShow"],
]) {
  assert.equal(source.match(/<\.vue\b/g)?.length, 1, `${label} keeps one LiveVue host`)
  assert.match(source, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
  assert.ok(source.includes(`v-component="${componentName}"`))
  assert.match(source, /upload=\{upload_dto\(@uploads\.artifact\)\}/)
  assert.match(source, /detected_importer=\{detected_importer_dto\(@uploads\.artifact\.entries\)\}/)
  assert.match(source, /submit_disabled=\{submit_disabled\?\(@uploads\.artifact\.entries\)\}/)
  assert.match(source, /v-on:validate=\{JS\.push\("validate"\)\}/)
  assert.match(source, /v-on:cancel-upload=\{JS\.push\("cancel_upload"\)\}/)
  assert.match(source, /v-ssr=\{false\}/)
  assert.match(source, /<\.live_file_input upload=\{@uploads\.artifact\} \/>/)
  assert.match(source, /phx-submit="save"/)
  assert.doesNotMatch(source, /<\.detected_preview/)

  assert.match(
    source,
    /allow_upload\(:artifact,\s*accept: :any,\s*max_entries: 1,\s*max_file_size: 50 \* 1024 \* 1024\s*\)/s,
  )
  assert.match(source, /def handle_event\("cancel_upload", %\{"ref" => ref\}, socket\)/)
  assert.match(source, /def handle_event\("validate", %\{"catalog_(?:database|revision)" => params\}, socket\)/)
}

const showToggleSource = sourceSlice(
  showLive,
  '  def handle_event("toggle_revision_form", _params, socket) do',
  '  @impl true\n  def handle_event("validate"',
  "server-owned revision disclosure toggle",
)

for (const authority of [
  "toggled = !socket.assigns.show_revision_form",
  "cancel_active_uploads(:artifact)",
  "assign(:revision_form, empty_revision_form())",
  "assign(socket, :show_revision_form, toggled)",
]) {
  assert.ok(showToggleSource.includes(authority), `${authority} remains Phoenix-owned`)
}

assert.equal(
  sha256(showToggleSource),
  "030831ad211637d417a2d2d781db9fa26c27f9cb9ba5bf979d7bcecc0b2fb550",
  "Phoenix disclosure cancellation and reset behavior remains byte-identical",
)

const showRenderSource = sourceSlice(
  showLive,
  "  def render(assigns) do",
  "  defp database_details_dto(",
  "server-owned CatalogDatabaseShow render contract",
)
const hiddenRevisionForm = sourceSlice(
  showRenderSource,
  "        <form",
  "        </form>",
  "hidden Phoenix revision upload form",
)
const showVueHost = sourceSlice(
  showRenderSource,
  "        <.vue",
  "        />",
  "CatalogDatabaseShow LiveVue host",
)

for (const contract of [
  ":if={@show_revision_form}",
  'id="catalog-revision-upload-live-form"',
  'phx-change="validate"',
  'phx-submit="save"',
  'style="display: none"',
  "<.live_file_input upload={@uploads.artifact} />",
]) {
  assert.ok(hiddenRevisionForm.includes(contract), `${contract} stays on the hidden Phoenix form`)
}

for (const contract of [
  'id="catalog-database-show-component"',
  'v-component="CatalogDatabaseShow"',
  "revision_form_open={@show_revision_form}",
  'v-on:toggle-revision-form={JS.push("toggle_revision_form")}',
  'v-on:validate={JS.push("validate")}',
  'v-on:cancel-upload={JS.push("cancel_upload")}',
  "v-ssr={false}",
]) {
  assert.ok(showVueHost.includes(contract), `${contract} remains an exact server bridge`)
}

assert.equal(showVueHost.match(/v-on:/g)?.length, 3)
assert.doesNotMatch(showVueHost, /v-on:save|v-model/)
assert.equal(
  sha256(showRenderSource),
  "95f33f3a97652b09eccc8bb5276096ceb1b281db755e18caf48604a6b1f7ba2c",
  "the hidden form, explicit props, and event bridge remain byte-identical",
)

assert.equal(
  sha256(
    sourceSlice(
      newLive,
      '  def handle_event("save", params, socket) do',
      "  defp create_catalog_database(",
      "new database save and upload",
    ),
  ),
  "60ccdf240590f202494bb0cc8c751a1a50c4298bf45d65647d192375e2c6a618",
  "new database save persistence and redirect behavior remains byte-identical",
)

assert.equal(
  sha256(
    sourceSlice(
      showLive,
      '  def handle_event("save", params, socket) do',
      "  defp assign_database_details(",
      "add revision save and upload",
    ),
  ),
  "f14288fe20e01eebf61707ccdbc1da60499f2b78fe25e3d73d723a1decf85705",
  "add revision save persistence and redirect behavior remains byte-identical",
)

for (const exactContract of [
  'id: "catalog-upload-form"',
  'name: "catalog_database"',
  'name: "#{form_name}[#{key}]"',
  'id: "catalog-revision-upload-form"',
  'name: "catalog_revision"',
  'id: "catalog-revision-upload-submit"',
  'class: "file-input file-input-bordered w-full"',
  'label: "Upload & import"',
  'label: "Upload revision"',
  'remove_label: "Remove"',
]) {
  assert.ok(newLive.includes(exactContract) || showLive.includes(exactContract), exactContract)
}

for (const mapping of [
  'def upload_error_message(:too_large), do: "File exceeds the 50 MB limit."',
  'def upload_error_message(:not_accepted), do: "File type is not accepted."',
  'def upload_error_message(:too_many_files), do: "Only one file at a time."',
  'def upload_error_message(other), do: "Upload failed: #{inspect(other)}"',
]) {
  assert.ok(components.includes(mapping), `${mapping} remains exact`)
}

for (const dtoContract of [
  "max_file_size: upload.max_file_size",
  "entries: Enum.map(upload.entries, &upload_entry_dto(upload, &1))",
  "Enum.map(upload.errors, fn {ref, error} -> upload_error_dto(ref, error) end)",
  '%{status: "detected", display_name: descriptor.display_name}',
  '%{status: "unsupported", display_name: nil}',
  '%{status: "empty", display_name: nil}',
]) {
  assert.ok(components.includes(dtoContract), `${dtoContract} remains server-authored`)
}

assert.doesNotMatch(components, /def upload_card|def detected_preview|def upload_error_alert/)

for (const [source, scenarios] of [
  [
    newTest,
    [
      "renders the new database form",
      "shows a friendly banner when no importer matches the file",
      "discovers packaged built-ins through the extension catalog",
      "uploading a valid YAML file creates a database revision import and navigates to the run",
      "cancels the selected upload through the preserved LiveView event",
    ],
  ],
  [
    showTest,
    [
      "renders JSON-safe database details, navigation, revisions, imports, and status semantics",
      "missing database redirects to catalog index",
      "add-revision form is hidden by default and shown on toggle",
      "cancelling the add-revision reveal hides the form",
      "uploads a supported file as a new revision and navigates to the import run",
      "refreshes matching import and revision DTOs when an import completes",
      "does not expose a catalog database outside the current organization scope",
      "unauthenticated requests redirect to sign in",
    ],
  ],
]) {
  for (const scenario of scenarios) {
    assert.ok(source.includes(`test "${scenario}"`), `${scenario} remains covered`)
  }
}

assert.equal(newTest.match(/file_input\(view, "#catalog-upload-live-form"/g)?.length, 4)
assert.equal(
  showTest.match(/file_input\(view, "#catalog-revision-upload-live-form"/g)?.length,
  2,
)
assert.match(newTest, /assert vue\.props == Jason\.decode!\(Jason\.encode!\(vue\.props\)\)/)
assert.match(showTest, /assert is_binary\(Jason\.encode!\(vue\.props\)\)/)
assert.match(
  showTest,
  /assert vue\.handlers == %\{\s*"cancel-upload" => JS\.push\("cancel_upload"\),\s*"toggle-revision-form" => JS\.push\("toggle_revision_form"\),\s*"validate" => JS\.push\("validate"\)\s*\}/s,
)

const catalogSession = sourceSlice(
  router,
  "    live_session :catalog,",
  "\n    live_session :comms,",
  "catalog LiveSession",
)

for (const routeContract of [
  "{CadenceWeb.OrganizationAuth, :require_organization_scope}",
  "{CadenceWeb.MissionAuth, :load_mission}",
  "{CadenceWeb.UserAuth, :attach_user_menu}",
  "layout: {CadenceWeb.Layouts, :mission_sidebar} do",
  'live "/missions/:mission_id/catalog/new", CatalogDatabaseNewLive, :new',
  'live "/missions/:mission_id/catalog/databases/:catalog_database_id",',
  "CatalogDatabaseShowLive,",
]) {
  assert.ok(catalogSession.includes(routeContract), `${routeContract} remains in catalog session`)
}

assert.equal(
  sha256(catalogSession),
  "97cbfdd714c7620054e78154ada952a9cf7215ae097e42bddce8cb63ffd224fd",
  "the authenticated catalog LiveSession, current-scope mounts, layout, and routes stay byte-identical",
)

const dom = installDom()
const [collapsibleRootSfc, collapsibleTriggerSfc, collapsibleContentSfc] = await Promise.all([
  loadSfc(paths.collapsibleRoot),
  loadSfc(paths.collapsibleTrigger),
  loadSfc(paths.collapsibleContent),
])
const {createApp, defineComponent, h, nextTick, onMounted, onUnmounted, ref} =
  integrationRequire("vue")
const CadenceCollapsible = collapsibleRootSfc.component
const CadenceCollapsibleTrigger = collapsibleTriggerSfc.component
const CadenceCollapsibleContent = collapsibleContentSfc.component
const disclosureOpen = ref(false)
const requestedStates = []
const mountedUploadInstances = []
const unmountedUploadInstances = []
let nextUploadInstance = 0

const CatalogUploadLifecycleProbe = defineComponent({
  name: "CatalogUploadLifecycleProbe",
  setup() {
    const instance = ++nextUploadInstance
    onMounted(() => mountedUploadInstances.push(instance))
    onUnmounted(() => unmountedUploadInstances.push(instance))

    return () =>
      h("form", {
        id: "catalog-revision-upload-form",
        "data-upload-instance": String(instance),
      })
  },
})

const CatalogDisclosureOracle = defineComponent({
  name: "CatalogDisclosureOracle",
  setup() {
    return () =>
      h(
        CadenceCollapsible,
        {
          open: disclosureOpen.value,
          contentId: "catalog-revision-upload-slot",
          onRequestChange: (nextOpen) => requestedStates.push(nextOpen),
        },
        {
          default: () =>
            h(
              "div",
              {
                id: "catalog-database-show-surface",
                class: "space-y-6",
              },
              [
                h("header", {id: "catalog-show-header"}, [
                  h(
                    CadenceCollapsibleTrigger,
                    null,
                    {
                      default: () =>
                        h(
                          "button",
                          {
                            id: "add-revision-toggle",
                            type: "button",
                            class: [
                              "btn",
                              disclosureOpen.value ? "btn-ghost" : "btn-primary",
                            ],
                          },
                          disclosureOpen.value ? "Cancel" : "+ Add revision",
                        ),
                    },
                  ),
                ]),
                h("section", {id: "catalog-database-summary"}),
                h(
                  CadenceCollapsibleContent,
                  null,
                  {
                    default: () => h("div", null, [h(CatalogUploadLifecycleProbe)]),
                  },
                ),
                h("section", {id: "catalog-revision-history"}),
                h("section", {id: "catalog-import-attempts"}),
              ],
            ),
        },
      )
  },
})

const app = createApp(CatalogDisclosureOracle)
app.mount(dom.window.document.querySelector("#app"))
await flushVue(nextTick)

const publicRoot = dom.window.document.querySelector("#catalog-database-show-surface")
const trigger = dom.window.document.querySelector("#add-revision-toggle")
const content = () => dom.window.document.querySelector("#catalog-revision-upload-slot")

assert.equal(dom.window.document.querySelector("#app").children.length, 1)
assert.equal(publicRoot.parentElement.id, "app")
assert.equal(publicRoot.tagName, "DIV")
assert.equal(publicRoot.className, "space-y-6")
assert.equal(publicRoot.getAttribute("data-state"), "closed")
assert.equal(publicRoot.getAttribute("data-disabled"), null)
assert.equal(trigger.tagName, "BUTTON")
assert.equal(trigger.type, "button")
assert.equal(trigger.disabled, false)
assert.equal(trigger.getAttribute("aria-controls"), "catalog-revision-upload-slot")
assert.equal(trigger.getAttribute("aria-expanded"), "false")
assert.equal(trigger.getAttribute("data-state"), "closed")
assert.equal(trigger.textContent, "+ Add revision")
assert.equal(content(), null)
assert.deepEqual(mountedUploadInstances, [])

trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true])
assert.equal(trigger.getAttribute("aria-expanded"), "false")
assert.equal(content(), null, "the request does not optimistically mount the upload form")

disclosureOpen.value = true
await flushVue(nextTick)
const firstContent = content()
const firstUploadForm = dom.window.document.querySelector("#catalog-revision-upload-form")
assert.ok(firstContent)
assert.equal(firstContent.tagName, "DIV")
assert.equal(firstContent.id, trigger.getAttribute("aria-controls"))
assert.equal(firstContent.getAttribute("data-state"), "open")
assert.equal(trigger.getAttribute("aria-expanded"), "true")
assert.equal(trigger.getAttribute("data-state"), "open")
assert.equal(trigger.textContent, "Cancel")
assert.deepEqual(mountedUploadInstances, [1])
assert.deepEqual(unmountedUploadInstances, [])

trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, false])
assert.equal(content(), firstContent, "content stays mounted until Phoenix closes it")

disclosureOpen.value = false
await flushVue(nextTick)
assert.equal(content(), null)
assert.equal(firstUploadForm.isConnected, false)
assert.deepEqual(unmountedUploadInstances, [1])

trigger.click()
await flushVue(nextTick)
assert.deepEqual(requestedStates, [true, false, true])
assert.equal(content(), null, "the reopen request remains server-authoritative")

disclosureOpen.value = true
await flushVue(nextTick)
const reopenedContent = content()
const reopenedUploadForm = dom.window.document.querySelector("#catalog-revision-upload-form")
assert.ok(reopenedContent)
assert.equal(reopenedContent.id, "catalog-revision-upload-slot")
assert.equal(trigger.getAttribute("aria-controls"), reopenedContent.id)
assert.notEqual(reopenedUploadForm, firstUploadForm)
assert.deepEqual(mountedUploadInstances, [1, 2])
assert.deepEqual(unmountedUploadInstances, [1])

app.unmount()
dom.window.close()

console.log("catalog_uploads_test passed")

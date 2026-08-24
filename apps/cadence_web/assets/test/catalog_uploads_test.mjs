import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {stripTypeScriptTypes} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

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
  "the new database cancel route and add-revision toggle remain exact",
  "existing catalog save persistence metadata redirect and failure behavior is byte-pinned by source slice",
  "focused LiveView scenarios still exercise unsupported supported persistence cancellation and scope",
  "the authenticated catalog LiveSession route and mission-sidebar layout remain untouched",
  "only catalog LiveViews components Vue files and focused tests are mutable in this slice",
]

assert.equal(process.versions.node, "24.16.0", "catalog upload contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 14)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  uploadForm: resolve(__dirname, "../vue/CatalogUploadForm.vue"),
  databaseNew: resolve(__dirname, "../vue/CatalogDatabaseNew.vue"),
  databaseShow: resolve(__dirname, "../vue/CatalogDatabaseShow.vue"),
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

  const withoutImports = script.replace(/^import .*$/gm, "")
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
assert.equal(databaseNew.match(/<CatalogUploadForm\b/g)?.length, 1)
assert.match(databaseNew, /<div :id="page\.id" class="space-y-6 max-w-2xl">/)
assert.match(databaseNew, /@validate="emit\('validate', \$event\)"/)
assert.match(databaseNew, /@cancel-upload="emit\('cancel-upload', \$event\)"/)
assert.match(databaseNew, /:id="page\.cancel\.id"/)
assert.match(databaseNew, /data-phx-link="redirect"/)
assert.match(databaseNew, /data-phx-link-state="push"/)

assert.match(databaseShow, /^import CatalogUploadForm from "\.\/CatalogUploadForm\.vue"$/m)
assert.equal(databaseShow.match(/<CatalogUploadForm\b/g)?.length, 1)
assert.match(databaseShow, /v-if="revision_form_open" id="catalog-revision-upload-slot"/)
assert.match(databaseShow, /@validate="emit\('validate', \$event\)"/)
assert.match(databaseShow, /@cancel-upload="emit\('cancel-upload', \$event\)"/)
assert.doesNotMatch(databaseShow, /<slot name="revision_form"/)

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

console.log("catalog_uploads_test passed")

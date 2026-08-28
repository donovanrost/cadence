import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Catalog Index page is one non-SSR LiveVue parent with one presentation prop",
  "Phoenix retains authenticated organization and mission scope plus every verified route",
  "Phoenix retains database ordering and latest revision and import-run selection",
  "the four import-run PubSub events rebuild the complete presentation DTO",
  "the root, header, breadcrumbs, action, empty state, card, rows, text, and classes stay exact",
  "CatalogIndex directly composes the immutable CatalogDatabaseTable child only when rows exist",
  "catalog-database-list stays in both client branches and the child wrapper stays nonempty-only",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the six pre-migration scenarios and 21 assertion sites remain one-for-one",
  "the authenticated browser scope, Catalog LiveSession mounts, and mission-sidebar layout stay exact",
  "Layouts.app remains the Phoenix host boundary with flash and current_scope",
  "CatalogDatabaseTable.vue stays pinned to the reviewed Cadence menu migration",
]

assert.equal(process.versions.node, "24.16.0", "Catalog Index contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const paths = {
  component: resolve(__dirname, "../vue/CatalogIndex.vue"),
  child: resolve(__dirname, "../vue/CatalogDatabaseTable.vue"),
  liveView: resolve(__dirname, "../../lib/cadence_web/live/catalog/catalog_index_live.ex"),
  liveViewTest: resolve(
    __dirname,
    "../../test/cadence_web/live/catalog/catalog_index_live_test.exs",
  ),
  router: resolve(__dirname, "../../lib/cadence_web/router.ex"),
  catalog: resolve(__dirname, "../../../cadence/lib/cadence/catalog.ex"),
}

const [component, child, liveView, liveViewTest, router, catalog] = await Promise.all(
  Object.values(paths).map((path) => readFile(path, "utf8")),
)

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

const assertionSiteCount = (source) => source.match(/^\s+(?:assert|refute)\b/gm)?.length ?? 0

const assertBalancedTemplate = (source) => {
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

  for (const match of source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "CatalogIndex.vue template tags are balanced")
}

assert.equal(
  child.match(
    /^import CadenceTableFrame from "\.\/ui\/components\/CadenceTableFrame\.vue"$/gm,
  )?.length,
  1,
  "CatalogDatabaseTable.vue has one CadenceTableFrame import before compatibility peeling",
)
assert.equal(
  child.match(/<\/?CadenceTableFrame\b/g)?.length,
  2,
  "CatalogDatabaseTable.vue has one CadenceTableFrame boundary before compatibility peeling",
)

const predecessorChild = child
  .replace('import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"\n', "")
  .replace(
    '  <CadenceTableFrame id="catalog-databases-table">',
    '  <table id="catalog-databases-table" class="table">',
  )
  .replace("  </CadenceTableFrame>", "  </table>")

assert.doesNotMatch(
  predecessorChild,
  /CadenceTableFrame/,
  "CatalogDatabaseTable.vue predecessor has no residual CadenceTableFrame shell",
)

assert.equal(
  createHash("sha256").update(predecessorChild).digest("hex"),
  "97cf3163799f89d80e6f254d5ae84e3ee0177d9992dcd89e9b1b3b12b7dca2fd",
  "CatalogDatabaseTable.vue remains the explicitly reviewed child",
)

const script = component.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = component.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "CatalogIndex.vue keeps an auditable TypeScript setup block")
assert.ok(template, "CatalogIndex.vue keeps an auditable template block")
assertBalancedTemplate(template)

assert.match(script, /^import CatalogDatabaseTable from "\.\/CatalogDatabaseTable\.vue"$/m)
assert.equal(script.match(/import .*CatalogDatabaseTable\.vue/g)?.length, 1)
assert.match(
  script,
  /type CatalogDatabaseTableProps = InstanceType<typeof CatalogDatabaseTable>\["\$props"\]/,
)
assert.match(script, /rows: CatalogDatabaseTableProps\["rows"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.doesNotMatch(script, /computed|ref\(|watch\(|fetch\(|useRoute|router|sort\(|filter\(/)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.breadcrumbs.attrs",
  "props.presentation.header.breadcrumbs.mission.attrs",
  "props.presentation.header.breadcrumbs.separator.attrs",
  "props.presentation.header.breadcrumbs.current.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.header.actions.attrs",
  "props.presentation.header.new_database.attrs",
  "props.presentation.header.new_database.icon.attrs",
  "props.presentation.empty_state.list.attrs",
  "props.presentation.empty_state.root.attrs",
  "props.presentation.empty_state.title.attrs",
  "props.presentation.empty_state.description.attrs",
  "props.presentation.card.root.attrs",
  "props.presentation.card.body.attrs",
  "props.presentation.card.child_wrapper.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const textBinding of [
  "props.presentation.header.breadcrumbs.mission.text",
  "props.presentation.header.breadcrumbs.separator.text",
  "props.presentation.header.breadcrumbs.current.text",
  "props.presentation.header.title.text",
  "props.presentation.header.subtitle.text",
  "props.presentation.header.new_database.text",
  "props.presentation.empty_state.title.text",
  "props.presentation.empty_state.description.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.match(template, /v-if="props\.presentation\.empty_state\.visible"/)
assert.match(template, /v-else-if="props\.presentation\.card\.visible"/)
assert.match(template, /<CatalogDatabaseTable :rows="props\.presentation\.card\.rows" \/>/)
assert.equal(template.match(/<CatalogDatabaseTable\b/g)?.length, 1)

const cardBranch = template.indexOf('v-else-if="props.presentation.card.visible"')
const childWrapper = template.indexOf('v-bind="props.presentation.card.child_wrapper.attrs"')
const childComposition = template.indexOf("<CatalogDatabaseTable")

assert.ok(cardBranch >= 0 && childWrapper > cardBranch && childComposition > childWrapper)
assert.doesNotMatch(
  component,
  /\/missions|data-phx-link|catalog-database-list|catalog-databases-table-component|new-database-link/,
)
assert.doesNotMatch(
  component,
  /Mission database library|No catalog databases yet|New database|space-y-6|border-primary|card bg-base-200/,
)
assert.doesNotMatch(component, /v-html|<\.vue|v-component=/)

assert.match(child, /import StatusBadge from "\.\/StatusBadge\.vue"/)
assert.match(predecessorChild, /id="catalog-databases-table" class="table"/)
assert.match(child, /:id="row\.id"/)
assert.match(child, /:id="row\.actions_id"/)
assert.equal(child.match(/data-phx-link="redirect"/g)?.length, 4)
assert.equal(child.match(/data-phx-link-state="push"/g)?.length, 4)

const mountSource = sourceSlice(
  liveView,
  "  def mount(_params, _session, socket) do",
  "  @impl true\n  def handle_info",
  "CatalogIndexLive mount",
)

assert.match(mountSource, /socket\.assigns\.current_mission/)
assert.match(mountSource, /socket\.assigns\.current_scope\.organization_id/)
assert.match(mountSource, /if connected\?\(socket\), do: Events\.subscribe_import_runs\(mission\.mission_id\)/)
assert.match(mountSource, /assign\(:page_title, "Catalog"\)/)
assert.match(mountSource, /assign\(:nav_item, :catalog\)/)
assert.match(mountSource, /assign_databases\(organization_id, mission\.mission_id\)/)

const pubSubSource = sourceSlice(
  liveView,
  "  def handle_info({event, _run}, socket)",
  "  defp assign_databases(socket, organization_id, mission_id) do",
  "Catalog Index PubSub refresh",
)

for (const event of [
  ":import_run_started",
  ":import_run_updated",
  ":import_run_completed",
  ":import_run_failed",
]) {
  assert.ok(pubSubSource.includes(event), `${event} continues to refresh Catalog Index`)
}

assert.equal(pubSubSource.match(/:import_run_(?:started|updated|completed|failed)/g)?.length, 4)
assert.match(pubSubSource, /assign_databases\(socket, organization_id, mission\.mission_id\)/)

const assignDatabasesSource = sourceSlice(
  liveView,
  "  defp assign_databases(socket, organization_id, mission_id) do",
  "  @impl true\n  def render(assigns) do",
  "Catalog Index database assignment",
)

assert.match(assignDatabasesSource, /Catalog\.list_databases\(organization_id, mission_id\)/)
assert.match(
  assignDatabasesSource,
  /Catalog\.latest_revision_by_database\(organization_id, mission_id\)/,
)
assert.match(
  assignDatabasesSource,
  /Catalog\.latest_import_run_by_database\(organization_id, mission_id\)/,
)
assert.match(
  assignDatabasesSource,
  /Enum\.map\(databases, &database_table_row\(&1, mission_id, latest_revisions, latest_runs\)\)/,
)
assert.match(assignDatabasesSource, /:catalog_index_presentation/)
assert.match(
  assignDatabasesSource,
  /page_presentation_dto\(socket\.assigns\.current_mission, rows\)/,
)

const renderSource = sourceSlice(
  liveView,
  "  def render(assigns) do",
  "  @doc false\n  def presentation_attrs",
  "CatalogIndexLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="catalog-index-component"/)
assert.match(renderSource, /v-component="CatalogIndex"/)
assert.match(renderSource, /presentation=\{@catalog_index_presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.card|<\.empty_state|CatalogDatabaseTable/)
assert.doesNotMatch(renderSource, /catalog-database-list|catalog-databases-table-component/)

const rawAttrsSource = sourceSlice(
  liveView,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp page_presentation_dto(mission, rows) do",
  "Catalog Index raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const presentationSource = sourceSlice(
  liveView,
  "  defp page_presentation_dto(mission, rows) do",
  "  defp navigate_attrs(href, extra_attrs) do",
  "Catalog Index page presentation DTO",
)

for (const text of [
  "Catalog",
  "Mission database library. Revisions are imported here; runtime usage is selected later.",
  "New database",
  "No catalog databases yet",
  "Use + New database above to import the first revision.",
]) {
  assert.ok(presentationSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-6",
  "border-b border-primary/20 pb-4",
  "flex items-end justify-between gap-4",
  "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60",
  "hover:text-primary transition-colors",
  "text-base-content/20",
  "text-primary/90",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "flex items-center gap-2",
  "btn btn-primary btn-sm gap-1",
  "hero-plus h-4 w-4",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hud-label",
  "card bg-base-200 border border-base-300",
  "card-body p-0",
]) {
  assert.ok(presentationSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

for (const id of [
  "new-database-link",
  "catalog-database-list",
  "catalog-databases-table-component",
]) {
  assert.ok(presentationSource.includes(`"${id}"`), `${id} stays in the page DTO`)
}

assert.match(presentationSource, /"visible" => rows == \[\]/)
assert.match(presentationSource, /"visible" => rows != \[\]/)
assert.match(presentationSource, /"rows" => rows/)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}"/)
assert.match(presentationSource, /~p"\/missions\/#\{mission\.mission_id\}\/catalog\/new"/)

const rowProjectionSource = sourceSlice(
  liveView,
  "  defp database_table_row(database, mission_id, latest_revisions, latest_runs) do",
  "  defp import_status_badge(:running)",
  "Catalog database row projection",
)

assert.match(rowProjectionSource, /Map\.get\(latest_revisions, database_id\)/)
assert.match(rowProjectionSource, /Map\.get\(latest_runs, database_id\)/)
assert.match(rowProjectionSource, /latest_revision_dto\(revision, mission_id\)/)
assert.match(rowProjectionSource, /latest_import_dto\(run, mission_id\)/)
assert.match(rowProjectionSource, /\/catalog\/databases\/#\{database_id\}/)
assert.match(rowProjectionSource, /\/catalog\/revisions\/#\{revision\.catalog_revision_id\}/)
assert.match(rowProjectionSource, /\/catalog\/imports\/#\{run\.import_run_id\}/)

const databaseOrderingSource = sourceSlice(
  catalog,
  "  @spec list_databases(binary(), binary(), keyword())",
  "  @spec persist_artifact(binary(), Artifact.t())",
  "catalog database ordering",
)

assert.match(databaseOrderingSource, /row\.organization_id == \^organization_id/)
assert.match(databaseOrderingSource, /row\.mission_id == \^mission_id/)
assert.match(databaseOrderingSource, /order_by\(\[row\], asc: row\.name, asc: row\.catalog_database_id\)/)

const latestImportSource = sourceSlice(
  catalog,
  "  @spec latest_import_run_by_database(binary(), binary())",
  "  @spec fetch_revision(binary(), binary(), binary())",
  "latest catalog import-run selection",
)

assert.match(latestImportSource, /not is_nil\(row\.catalog_database_id\)/)
assert.match(latestImportSource, /order_by\(\[row\], desc: row\.started_at, desc: row\.import_run_id\)/)
assert.match(latestImportSource, /Map\.put_new\(acc, catalog_database_id, run\)/)

const latestRevisionSource = sourceSlice(
  catalog,
  "  @spec latest_revision_by_database(binary(), binary())",
  "  @spec start_revision_import(binary(), binary(), binary(), Artifact.t(), binary(), keyword())",
  "latest catalog revision selection",
)

assert.match(
  latestRevisionSource,
  /order_by\(\[row\], desc: row\.revision_number, desc: row\.inserted_at\)/,
)
assert.match(latestRevisionSource, /Map\.put_new\(acc, catalog_database_id, revision\)/)

const catalogListTests = sourceSlice(
  liveViewTest,
  '  describe "catalog database list" do',
  '  describe "sidebar" do',
  "pre-migration catalog database list scenarios",
)
const sidebarTests = sourceSlice(
  liveViewTest,
  '  describe "sidebar" do',
  '  describe "pubsub updates" do',
  "pre-migration Catalog sidebar scenario",
)
const pubSubTests = sourceSlice(
  liveViewTest,
  '  describe "pubsub updates" do',
  '  describe "presentation contract" do',
  "pre-migration Catalog PubSub scenario",
)

for (const [source, scenarios, assertionSites] of [
  [
    catalogListTests,
    [
      "shows empty state with a new-database CTA when no catalog databases exist",
      "renders a + New database CTA in the page header",
      "lists persisted catalog databases with latest revision and import status",
      "only shows databases in this mission",
    ],
    16,
  ],
  [sidebarTests, ["marks Catalog as the active nav item"], 3],
  [pubSubTests, ["re-renders latest run status when a revision import completes"], 2],
]) {
  assert.equal(source.match(/^    test "/gm)?.length, scenarios.length)
  assert.equal(assertionSiteCount(source), assertionSites)

  for (const scenario of scenarios) {
    assert.ok(source.includes(`test "${scenario}"`), `${scenario} remains one-for-one`)
  }
}

assert.doesNotMatch(catalogListTests, /\bhtml\b\s*=|html =~/)
assert.match(catalogListTests, /catalog_index_presentation\(view\)/)
assert.match(catalogListTests, /has_element\?\(view, "#catalog-upload-form"\)/)
assert.match(pubSubTests, /catalog_database_row\(view, database\.catalog_database_id\)/)
assert.match(pubSubTests, /render\(view\)/)

const presentationTests = sourceSlice(
  liveViewTest,
  '  describe "presentation contract" do',
  "  defp catalog_index_presentation(view)",
  "focused Catalog Index presentation tests",
)

assert.match(presentationTests, /has_element\?\(view, "#catalog-index-component"\)/)
assert.match(presentationTests, /vue\.component == "CatalogIndex"/)
assert.match(presentationTests, /vue\.ssr == false/)
assert.match(presentationTests, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(presentationTests, /Jason\.decode!\(Jason\.encode!\(presentation\)\)/)
assert.match(presentationTests, /CatalogIndexLive\.presentation_attrs/)
assert.match(presentationTests, /"nil" => nil/)
assert.match(presentationTests, /"false" => false/)
assert.match(presentationTests, /"true" => true/)
assert.match(presentationTests, /"number" => 7/)

const authenticatedScopeSource = sourceSlice(
  router,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "    live_session :organization,",
  "authenticated browser scope",
)

assert.match(authenticatedScopeSource, /pipe_through \[:browser, :require_authenticated_scope\]/)

const catalogSessionSource = sourceSlice(
  router,
  "    live_session :catalog,",
  "    live_session :comms,",
  "Catalog LiveSession",
)

assert.match(catalogSessionSource, /CadenceWeb\.OrganizationAuth, :require_organization_scope/)
assert.match(catalogSessionSource, /CadenceWeb\.MissionAuth, :load_mission/)
assert.match(catalogSessionSource, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(catalogSessionSource, /layout: \{CadenceWeb\.Layouts, :mission_sidebar\} do/)
assert.match(
  catalogSessionSource,
  /live "\/missions\/:mission_id\/catalog", CatalogIndexLive, :index/,
)
assert.equal(
  catalogSessionSource.match(/live "\/missions\/:mission_id\/catalog", CatalogIndexLive, :index/g)
    ?.length,
  1,
)
assert.doesNotMatch(catalogSessionSource, /require_organization_admin|require_platform_admin/)

console.log("catalog_index_test passed")

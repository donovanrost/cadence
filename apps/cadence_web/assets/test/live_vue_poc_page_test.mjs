import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "contracts use pinned Node 24.16.0")

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/LiveVuePocPage.vue")
const demoPath = resolve(__dirname, "../vue/LiveVueDemo.vue")
const liveViewPath = resolve(__dirname, "../../lib/cadence_web/live/live_vue_poc_live.ex")
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")

const [pageSource, demoSource, liveViewSource, routerSource] = await Promise.all([
  readFile(pagePath, "utf8"),
  readFile(demoPath, "utf8"),
  readFile(liveViewPath, "utf8"),
  readFile(routerPath, "utf8"),
])

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} remains source-auditable`)
  return source.slice(startIndex, endIndex)
}

assert.equal(
  createHash("sha256").update(demoSource).digest("hex"),
  "dae5374c829924b5f45a3f40f731279ffff99bd042e583a6cea2b5889c1530e5",
  "LiveVueDemo.vue remains byte-for-byte immutable",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "LiveVuePocPage.vue has an auditable TypeScript setup block")
assert.ok(template, "LiveVuePocPage.vue has an auditable template block")
assert.match(script, /^import LiveVueDemo from "\.\/LiveVueDemo\.vue"$/m)
assert.equal(script.match(/import LiveVueDemo/g)?.length, 1)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.doesNotMatch(script, /ref\(|computed|watch\(|defineEmits|fetch\(|useRoute|router/)

assert.equal(template.match(/<LiveVueDemo\b/g)?.length, 1)
assert.match(template, /<LiveVueDemo :message="props\.presentation\.demo\.message" \/>/)

for (const attrs of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.demo.attrs",
]) {
  assert.ok(template.includes(`v-bind="${attrs}"`), `${attrs} stays Phoenix-authored`)
}

for (const text of [
  "props.presentation.header.title.text",
  "props.presentation.header.subtitle.text",
  "props.presentation.demo.message",
]) {
  assert.ok(template.includes(text), `${text} stays Phoenix-authored`)
}

assert.doesNotMatch(
  pageSource,
  /LiveVue PoC|authenticated Cadence LiveView shell|Vue is mounted inside a Cadence LiveView|livevue-poc-page|space-y-6/,
)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "LiveVuePocLive render boundary",
)

assert.equal(renderSource.match(/<\.vue\b/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="livevue-poc-page-component"/)
assert.match(renderSource, /v-component="LiveVuePocPage"/)
assert.match(renderSource, /presentation=\{@presentation\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|LiveVueDemo|livevue-poc-component/)

const presentationSource = sourceSlice(
  liveViewSource,
  "  defp page_presentation do",
  "\n  end\nend",
  "LiveVuePocLive presentation",
)

for (const contract of [
  '"id" => "livevue-poc-page"',
  '"class" => "space-y-6"',
  '"class" => "border-b border-primary/20 pb-4"',
  '"text" => "LiveVue PoC"',
  '"A Vue component mounted inside the authenticated Cadence LiveView shell."',
  '"id" => "livevue-poc-component"',
  '"message" => "Vue is mounted inside a Cadence LiveView"',
]) {
  assert.ok(presentationSource.includes(contract), `Phoenix retains ${contract}`)
}

const organizationRoute = sourceSlice(
  routerSource,
  "    live_session :organization,",
  "\n    live_session :provider_accounts,",
  "authenticated organization LiveSession",
)

assert.match(
  organizationRoute,
  /on_mount: \[\n        \{CadenceWeb\.OrganizationAuth, :require_organization_scope\},\n        \{CadenceWeb\.UserAuth, :attach_user_menu\}\n      \]/,
)
assert.match(organizationRoute, /layout: \{CadenceWeb\.Layouts, :sidebar\} do/)
assert.equal(organizationRoute.match(/live "\/livevue-poc", LiveVuePocLive, :index/g)?.length, 1)

const authenticatedScope = sourceSlice(
  routerSource,
  "  scope \"/\", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]",
  "\n    live_session :provider_accounts,",
  "authenticated browser scope",
)

assert.ok(authenticatedScope.includes(organizationRoute.trimEnd()))

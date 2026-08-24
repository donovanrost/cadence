import assert from "node:assert/strict"
import {access, readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

assert.equal(process.versions.node, "24.16.0", "contracts use pinned Node 24.16.0")

const scenarioLedger = [
  "the three existing GET URLs remain controller routes in their original browser pipelines",
  "admin mode POST and DELETE remain controller-owned with their session and redirect effects",
  "invitation POST remains controller-owned with validation, session renewal, and redirects",
  "all GET and POST error statuses remain assigned before controller live_render",
  "each page mounts one non-SSR LiveVue presentation host with a neutral container and no live layout",
  "each LiveView begins with Layouts.app and receives the browser current_scope snapshot",
  "Phoenix authors every route, form name, CSRF field, DOM ID, class, copy branch, and derived label",
  "Vue renders only JSON-safe presentation props and emits no events or mutations",
  "admin mode preserves the regular admin_mode[password] POST form",
  "no organization preserves pending invitation singular/plural logic and the regular DELETE sign-out form",
  "organization invitation preserves available and unavailable cards plus non-password error values",
  "the pre-existing browser and no-organization scenarios remain and now assert LiveVue contracts",
]

assert.equal(scenarioLedger.length, 12)

const __dirname = dirname(fileURLToPath(import.meta.url))
const webRoot = resolve(__dirname, "../..")

const paths = {
  router: resolve(webRoot, "lib/cadence_web/router.ex"),
  adminController: resolve(webRoot, "lib/cadence_web/controllers/admin_mode_controller.ex"),
  noOrganizationController: resolve(
    webRoot,
    "lib/cadence_web/controllers/no_organization_controller.ex",
  ),
  invitationController: resolve(
    webRoot,
    "lib/cadence_web/controllers/organization_invitation_controller.ex",
  ),
  adminLive: resolve(webRoot, "lib/cadence_web/live/admin_mode_live.ex"),
  noOrganizationLive: resolve(webRoot, "lib/cadence_web/live/no_organization_live.ex"),
  invitationLive: resolve(webRoot, "lib/cadence_web/live/organization_invitation_live.ex"),
  adminPresentation: resolve(
    webRoot,
    "lib/cadence_web/live/admin_mode_live/presentation.ex",
  ),
  noOrganizationPresentation: resolve(
    webRoot,
    "lib/cadence_web/live/no_organization_live/presentation.ex",
  ),
  invitationPresentation: resolve(
    webRoot,
    "lib/cadence_web/live/organization_invitation_live/presentation.ex",
  ),
  adminComponent: resolve(webRoot, "assets/vue/AdminModePage.vue"),
  noOrganizationComponent: resolve(webRoot, "assets/vue/NoOrganizationPage.vue"),
  invitationComponent: resolve(webRoot, "assets/vue/OrganizationInvitationPage.vue"),
  browserTest: resolve(webRoot, "test/cadence_web/controllers/browser_shell_test.exs"),
  noOrganizationTest: resolve(
    webRoot,
    "test/cadence_web/controllers/no_organization_controller_test.exs",
  ),
  invitationTest: resolve(
    webRoot,
    "test/cadence_web/controllers/organization_invitation_controller_test.exs",
  ),
}

const sources = Object.fromEntries(
  await Promise.all(
    Object.entries(paths).map(async ([key, path]) => [key, await readFile(path, "utf8")]),
  ),
)

const sourceSlice = (source, startMarker, endMarker, label) => {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start + startMarker.length)

  assert.ok(start >= 0, `${label} start remains present`)
  assert.ok(end > start, `${label} end remains present`)

  return source.slice(start, end)
}

const authenticatedRoutes = sourceSlice(
  sources.router,
  '  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "\n    get \"/missions/:mission_id/catalog/artifacts/:artifact_id/download\"",
  "authenticated controller page routes",
)

for (const route of [
  'get "/admin-mode", AdminModeController, :new',
  'post "/admin-mode", AdminModeController, :create',
  'delete "/admin-mode", AdminModeController, :delete',
  'get "/no-organization", NoOrganizationController, :show',
]) {
  assert.ok(authenticatedRoutes.includes(route), `${route} stays authenticated`)
  assert.equal(sources.router.split(route).length - 1, 1, `${route} remains unique`)
}

const publicInvitationRoutes = sourceSlice(
  sources.router,
  '  scope "/", CadenceWeb do\n    pipe_through :browser\n\n    get "/invitations',
  '\n  end\n\n  scope "/", CadenceWeb do\n    pipe_through [:browser, :require_authenticated_scope]',
  "public invitation controller routes",
)

for (const route of [
  'get "/invitations/:invitation_token", OrganizationInvitationController, :show',
  'post "/invitations/:invitation_token", OrganizationInvitationController, :update',
]) {
  assert.ok(publicInvitationRoutes.includes(route), `${route} stays in :browser`)
  assert.equal(sources.router.split(route).length - 1, 1, `${route} remains unique`)
}

const controllerContracts = [
  [sources.adminController, "CadenceWeb.AdminModeLive", "Presentation.build()"],
  [
    sources.noOrganizationController,
    "CadenceWeb.NoOrganizationLive",
    "Presentation.build(pending_invitations_count)",
  ],
  [
    sources.invitationController,
    "CadenceWeb.OrganizationInvitationLive",
    "Presentation.build(assigns, error_message)",
  ],
]

for (const [controller, liveView, presentation] of controllerContracts) {
  assert.match(controller, /import Phoenix\.LiveView\.Controller, only: \[live_render: 3\]/)
  assert.ok(controller.includes(`live_render(${liveView},`), `${liveView} is controller rendered`)
  assert.ok(controller.includes(`session: live_session(conn, ${presentation})`))
  assert.match(controller, /container: \{:div, class: "contents"\}/)
  assert.match(controller, /"user_session_token" => get_session\(conn, :user_session_token\)/)
  assert.match(
    controller,
    /"current_organization_id" => get_session\(conn, :current_organization_id\)/,
  )
  assert.match(
    controller,
    /"admin_mode_expires_at" => get_session\(conn, :admin_mode_expires_at\)/,
  )
  assert.match(controller, /"presentation" => presentation/)
}

for (const mutation of [
  "put_session(:admin_mode_expires_at, AdminMode.expires_at())",
  "delete_session(:admin_mode_expires_at)",
  'put_flash(:info, "Admin mode enabled.")',
  'put_flash(:info, "Admin mode disabled.")',
  'redirect(to: ~p"/admin")',
  'redirect(to: ~p"/")',
]) {
  assert.ok(sources.adminController.includes(mutation), `admin controller retains ${mutation}`)
}

for (const mutation of [
  "renew_browser_session()",
  "put_session(:user_session_token, acceptance_result.session_token)",
  "put_session(:current_organization_id, acceptance_result.current_organization_id)",
  'put_flash(:info, "Invitation accepted. Your durable operator account is ready.")',
  "redirect(to: redirect_target(acceptance_result))",
  "configure_session(renew: true)",
  "clear_session()",
]) {
  assert.ok(
    sources.invitationController.includes(mutation),
    `invitation controller retains ${mutation}`,
  )
}

for (const status of [
  "defp error_status(:organization_invitation_not_found), do: :not_found",
  "defp error_status(:organization_invitation_expired), do: :gone",
  "defp error_status(:organization_invitation_unavailable), do: :gone",
  "defp error_status(_reason), do: :unprocessable_entity",
]) {
  assert.ok(sources.invitationController.includes(status), `status contract remains ${status}`)
}

const liveContracts = [
  [sources.adminLive, "admin-mode-page-component", "AdminModePage"],
  [sources.noOrganizationLive, "no-organization-page-component", "NoOrganizationPage"],
  [
    sources.invitationLive,
    "organization-invitation-page-component",
    "OrganizationInvitationPage",
  ],
]

for (const [liveView, id, component] of liveContracts) {
  assert.match(liveView, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
  assert.ok(liveView.includes(`id="${id}"`), `${id} stays stable`)
  assert.ok(liveView.includes(`v-component="${component}"`))
  assert.match(liveView, /presentation=\{@presentation\}/)
  assert.match(liveView, /v-ssr=\{false\}/)
  assert.match(liveView, /class="contents"/)
  assert.match(liveView, /layout: false/)
  assert.match(liveView, /ScopeLoader\.assign_scope_from_session\(session\)/)
  assert.equal(liveView.match(/<\.vue\b/g)?.length, 1)
}

const sfcParts = (source, label) => {
  const script = source.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
  const template = source.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

  assert.ok(script, `${label} keeps an auditable TypeScript setup block`)
  assert.ok(template, `${label} keeps an auditable template block`)

  return {script, template}
}

const assertBalancedTemplate = (source, label) => {
  const stack = []
  const voidElements = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input"])

  for (const match of source.matchAll(/<\/?([a-z][\w-]*)(?:\s[^<>]*?)?>/gs)) {
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

for (const [component, label] of [
  [sources.adminComponent, "AdminModePage.vue"],
  [sources.noOrganizationComponent, "NoOrganizationPage.vue"],
  [sources.invitationComponent, "OrganizationInvitationPage.vue"],
]) {
  const {script, template} = sfcParts(component, label)

  assertBalancedTemplate(template, label)
  assert.match(script, /defineProps<\{presentation: \w+Presentation\}>\(\)/)
  assert.doesNotMatch(script, /defineEmits|ref\(|reactive\(|computed|watch\(|fetch\(|useRoute|router/)
  assert.doesNotMatch(component, /phx-|@submit|@click|@input|@change/)
  assert.doesNotMatch(component, /class="(?!contents)/)
}

for (const binding of [
  'v-bind="presentation.root.attrs"',
  'v-bind="presentation.form.attrs"',
  'v-bind="presentation.form.password.input.attrs"',
  'v-bind="presentation.form.submit.attrs"',
]) {
  assert.ok(sources.adminComponent.includes(binding), `AdminModePage preserves ${binding}`)
}

for (const binding of [
  'v-if="presentation.pending_invitations"',
  'v-bind="presentation.pending_invitations.root.attrs"',
  'v-bind="presentation.pending_invitations.link.attrs"',
  'v-bind="presentation.sign_out.form.attrs"',
  'v-bind="presentation.sign_out.button.attrs"',
]) {
  assert.ok(
    sources.noOrganizationComponent.includes(binding),
    `NoOrganizationPage preserves ${binding}`,
  )
}

for (const binding of [
  'v-if="presentation.error"',
  'v-bind="presentation.cards.root.attrs"',
  'v-for="card in presentation.cards.items"',
  'v-if="presentation.form"',
  'v-for="field in presentation.form.fields"',
  'v-bind="presentation.form.actions.submit.attrs"',
]) {
  assert.ok(
    sources.invitationComponent.includes(binding),
    `OrganizationInvitationPage preserves ${binding}`,
  )
}

for (const routeOrCopy of [
  "/admin-mode",
  "Enter admin mode",
  "Re-enter your password to temporarily enable platform-wide administration.",
  "admin_mode[password]",
  "admin-mode-form",
  "btn btn-primary w-full",
]) {
  assert.ok(
    sources.adminPresentation.includes(routeOrCopy),
    `admin presentation owns ${routeOrCopy}`,
  )
  assert.ok(!sources.adminComponent.includes(routeOrCopy), `admin Vue does not own ${routeOrCopy}`)
}

for (const routeOrCopy of [
  "/session",
  "/notifications",
  "No organization access",
  "pending invitation.",
  "pending invitations.",
  "Sign out",
  "_method",
  "delete",
]) {
  assert.ok(
    sources.noOrganizationPresentation.includes(routeOrCopy),
    `no-organization presentation owns ${routeOrCopy}`,
  )
  assert.ok(
    !sources.noOrganizationComponent.includes(routeOrCopy),
    `no-organization Vue does not own ${routeOrCopy}`,
  )
}

for (const routeOrCopy of [
  '/invitations/#{invitation_token}',
  "organization-invitation",
  "Accept your invitation and establish durable operator access.",
  "This invitation is no longer available.",
  "organization_invitation_acceptance[display_name]",
  "organization_invitation_acceptance[password]",
  "organization_invitation_acceptance[password_confirmation]",
  "Accept Invitation",
]) {
  assert.ok(
    sources.invitationPresentation.includes(routeOrCopy),
    `invitation presentation owns ${routeOrCopy}`,
  )
  assert.ok(
    !sources.invitationComponent.includes(routeOrCopy),
    `invitation Vue does not own ${routeOrCopy}`,
  )
}

for (const presentation of [
  sources.adminPresentation,
  sources.noOrganizationPresentation,
  sources.invitationPresentation,
]) {
  assert.match(presentation, /\{_name, value\}, rendered when value in \[nil, false\]/)
  assert.match(presentation, /\{name, true\}, rendered/)
  assert.match(presentation, /Map\.put\(rendered, name, ""\)/)
  assert.match(presentation, /Map\.put\(rendered, name, to_string\(value\)\)/)
  assert.match(presentation, /Plug\.CSRFProtection\.get_csrf_token_for\(action\)/)
}

const noOrganizationScenarios = [
  "renders for authenticated user with no membership and no invitations",
  "renders pending-invitations block when the user has unread invitation notifications",
  "uses plural copy for multiple invitations",
  "redirects to /sign-in when unauthenticated",
]

for (const scenario of noOrganizationScenarios) {
  assert.ok(sources.noOrganizationTest.includes(`test "${scenario}"`), `${scenario} remains`)
}

assert.match(sources.noOrganizationTest, /Test\.get_vue\(view, id: "no-organization-page-component"\)/)
assert.match(sources.browserTest, /Test\.get_vue\(admin_mode_view, id: "admin-mode-page-component"\)/)
assert.match(
  sources.browserTest,
  /Test\.get_vue\(invitation_view, id: "organization-invitation-page-component"\)/,
)
assert.equal(sources.invitationTest.match(/^  test "/gm)?.length, 5)
assert.match(sources.invitationTest, /html_response\(response, 404\)/)
assert.equal(sources.invitationTest.match(/html_response\(410\)/g)?.length, 2)
assert.equal(sources.invitationTest.match(/html_response\(422\)/g)?.length, 2)

for (const legacyPath of [
  resolve(webRoot, "lib/cadence_web/controllers/admin_mode_html.ex"),
  resolve(webRoot, "lib/cadence_web/controllers/admin_mode_html/new.html.heex"),
  resolve(webRoot, "lib/cadence_web/controllers/no_organization_html.ex"),
  resolve(webRoot, "lib/cadence_web/controllers/no_organization_html/show.html.heex"),
  resolve(webRoot, "lib/cadence_web/controllers/organization_invitation_html.ex"),
  resolve(webRoot, "lib/cadence_web/controllers/organization_invitation_html/show.html.heex"),
]) {
  await assert.rejects(access(legacyPath), `${legacyPath} legacy controller template stays removed`)
}

console.log("controller_pages_test passed")

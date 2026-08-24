import assert from "node:assert/strict"
import {createHash} from "node:crypto"
import {readFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scenarioLedger = [
  "the complete Notifications page is one always-present non-SSR LiveVue parent with one presentation prop",
  "Phoenix owns current-scope user identity, notification queries, authorization, mutations, flashes, and navigation",
  "Phoenix owns root, header, empty-state, panel, row, action, and state presentation decisions",
  "assign_notifications recomputes the complete presentation at every existing refresh call site",
  "created notifications prepend and updated notifications replace without changing PubSub ordering semantics",
  "NotificationsPage directly composes the byte-for-byte immutable NotificationsPanel child once",
  "the parent declares and transparently re-emits both child payload contracts",
  "the page root, header, empty state, inner panel wrapper, rows, actions, IDs, text, tags, and classes stay exact",
  "notification bodies retain the immutable child's conditional omission semantics",
  "raw attrs preserve HEEx nil, false, true, string, and number behavior",
  "the seven pre-migration LiveView scenarios and every outcome oracle remain one-for-one",
  "the authenticated user route, pipeline, mounts, action, and user-shell layout stay unchanged",
  "router, LiveView, parent, and tests use semantic source slices; only immutable NotificationsPanel.vue is hashed",
]

assert.equal(process.versions.node, "24.16.0", "notification contracts use pinned Node 24.16.0")
assert.equal(scenarioLedger.length, 13)

const __dirname = dirname(fileURLToPath(import.meta.url))
const pagePath = resolve(__dirname, "../vue/NotificationsPage.vue")
const childPath = resolve(__dirname, "../vue/NotificationsPanel.vue")
const liveViewPath = resolve(__dirname, "../../lib/cadence_web/live/notifications_live.ex")
const liveViewTestPath = resolve(
  __dirname,
  "../../test/cadence_web/live/notifications_live_test.exs",
)
const routerPath = resolve(__dirname, "../../lib/cadence_web/router.ex")
const userAuthPath = resolve(__dirname, "../../lib/cadence_web/live/user_auth.ex")
const bellPath = resolve(__dirname, "../../lib/cadence_web/live/notifications_bell.ex")

const [pageSource, childSource, liveViewSource, liveViewTestSource, routerSource, userAuthSource, bellSource] =
  await Promise.all([
    readFile(pagePath, "utf8"),
    readFile(childPath, "utf8"),
    readFile(liveViewPath, "utf8"),
    readFile(liveViewTestPath, "utf8"),
    readFile(routerPath, "utf8"),
    readFile(userAuthPath, "utf8"),
    readFile(bellPath, "utf8"),
  ])

const sourceSlice = (source, start, end, label) => {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)

  assert.ok(startIndex >= 0 && endIndex > startIndex, `${label} must remain source-auditable`)
  return source.slice(startIndex, endIndex)
}

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
  const tags = source.matchAll(/<\/?([A-Za-z][\w.-]*)(?:\s[^<>]*?)?>/gs)

  for (const match of tags) {
    const token = match[0]
    const name = match[1]

    if (token.startsWith("</")) {
      assert.equal(stack.pop(), name, `${name} closes the current SFC element`)
    } else if (!token.endsWith("/>") && !voidElements.has(name)) {
      stack.push(name)
    }
  }

  assert.deepEqual(stack, [], "SFC template tags are balanced")
}

assert.equal(
  createHash("sha256").update(childSource).digest("hex"),
  "921716083b0ce692a629d3183c384a06c4719fb157444e154cebf77fbbc0e79c",
  "NotificationsPanel.vue remains the explicitly immutable child",
)

const script = pageSource.match(/<script setup lang="ts">\n([\s\S]*?)\n<\/script>/)?.[1]
const template = pageSource.match(/<template>\n([\s\S]*?)\n<\/template>/)?.[1]

assert.ok(script, "NotificationsPage.vue must have a TypeScript script setup block")
assert.ok(template, "NotificationsPage.vue must have a template block")
assertBalancedTemplate(template)

assert.match(script, /import NotificationsPanel from "\.\/NotificationsPanel\.vue"/)
assert.match(script, /type NotificationsPanelProps = InstanceType<typeof NotificationsPanel>\["\$props"\]/)
assert.match(script, /defineProps<\{presentation: Presentation\}>\(\)/)
assert.match(script, /"accept-invitation": \[payload: NotificationPayload\]/)
assert.match(script, /"mark-read": \[payload: NotificationPayload\]/)
assert.equal(template.match(/<NotificationsPanel\b/g)?.length, 1)
assert.match(template, /:notifications="props\.presentation\.panel\.notifications"/)
assert.match(template, /@accept-invitation="emit\('accept-invitation', \$event\)"/)
assert.match(template, /@mark-read="emit\('mark-read', \$event\)"/)
assert.match(template, /v-if="props\.presentation\.empty_state"/)
assert.match(template, /v-else-if="props\.presentation\.panel"/)

for (const binding of [
  "props.presentation.root.attrs",
  "props.presentation.header.attrs",
  "props.presentation.header.body.attrs",
  "props.presentation.header.content.attrs",
  "props.presentation.header.title.attrs",
  "props.presentation.header.subtitle.attrs",
  "props.presentation.empty_state.wrapper.attrs",
  "props.presentation.empty_state.body.attrs",
  "props.presentation.empty_state.icon.attrs",
  "props.presentation.empty_state.title.attrs",
  "props.presentation.empty_state.description.attrs",
  "props.presentation.panel.attrs",
]) {
  assert.ok(template.includes(`v-bind="${binding}"`), `${binding} stays DTO-owned`)
}

for (const textBinding of [
  "props.presentation.header.title.text",
  "props.presentation.header.subtitle.text",
  "props.presentation.empty_state.title.text",
  "props.presentation.empty_state.description.text",
]) {
  assert.ok(template.includes(`{{ ${textBinding} }}`), `${textBinding} stays DTO-owned`)
}

assert.doesNotMatch(
  pageSource,
  /No notifications|All caught up|Invitations, access grants|space-y-4|max-w-2xl|hero-bell|border-primary/,
)
assert.doesNotMatch(pageSource, /fetch\(|sort\(|\.sort\(|filter\(|\.filter\(|pushEvent|v-html/)
assert.doesNotMatch(pageSource, /<\.vue|v-component=|phx-click|phx-change|phx-submit/)

for (const childContract of [
  'defineProps<{notifications: Notification[]}>()',
  '"accept-invitation": [payload: {notification_id: string}]',
  '"mark-read": [payload: {notification_id: string}]',
  "notification_id: notification.notification_id",
  'id="notifications-panel" aria-label="Notifications"',
  'id="notifications-list" class="space-y-2" role="list"',
  'v-if="notification.body"',
  "emit('accept-invitation', payload(notification))",
  "emit('mark-read', payload(notification))",
]) {
  assert.ok(childSource.includes(childContract), `${childContract} remains in the immutable child`)
}

const mountSource = sourceSlice(
  liveViewSource,
  "  def mount(_params, _session, socket) do",
  '  @impl true\n  def handle_event("accept_invitation"',
  "NotificationsLive mount",
)

assert.match(mountSource, /socket\.assigns\.current_scope\.user\.user_id/)
assert.match(mountSource, /Cadence\.Notifications\.list_notifications\(user_id\)/)
assert.match(mountSource, /assign_notifications/)

const acceptEventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("accept_invitation"',
  '  @impl true\n  def handle_event("mark_read"',
  "accept-invitation event",
)

for (const contract of [
  "Cadence.Notifications.fetch_notification(id)",
  "notification.user_id == user_id",
  ":organization_invitation <- notification.kind",
  'Map.get(notification.metadata, "organization_invitation_id")',
  "Cadence.Accounts.accept_invitation_as_user(user_id, invitation_id)",
  'put_flash(:info, "Joined #{org_name}.")',
  'push_navigate(to: ~p"/")',
  "accept_error_message(reason)",
  'put_flash(:error, "That notification is no longer available.")',
]) {
  assert.ok(acceptEventSource.includes(contract), `${contract} remains server-owned`)
}

assert.doesNotMatch(
  sourceSlice(
    acceptEventSource,
    "        {:ok, %{invitation: _invitation}} ->",
    "        {:error, reason} ->",
    "successful invitation branch",
  ),
  /assign_notifications|list_notifications/,
)

const markEventSource = sourceSlice(
  liveViewSource,
  '  def handle_event("mark_read"',
  "  @impl true\n  def handle_info({:notification_created",
  "mark-read event",
)

assert.match(markEventSource, /mark_notification_read\(socket, id\)/)

const pubSubSource = sourceSlice(
  liveViewSource,
  "  def handle_info({:notification_created",
  "  @impl true\n  def render(assigns) do",
  "NotificationsLive PubSub handlers",
)

assert.match(pubSubSource, /assign_notifications\(socket, \[n \| socket\.assigns\.notifications\]\)/)
assert.match(pubSubSource, /assign_notifications\(socket, replace_in_list\(socket\.assigns\.notifications, n\)\)/)
assert.match(pubSubSource, /Cadence\.Notifications\.list_notifications\(user_id\)/)

const renderSource = sourceSlice(
  liveViewSource,
  "  def render(assigns) do",
  "  @doc false",
  "NotificationsLive render boundary",
)

assert.equal(renderSource.match(/<\.vue/g)?.length, 1)
assert.match(renderSource, /<Layouts\.app flash=\{@flash\} current_scope=\{@current_scope\}>/)
assert.match(renderSource, /id="notifications-page-component"/)
assert.match(renderSource, /v-component="NotificationsPage"/)
assert.match(renderSource, /presentation=\{@notifications_page_presentation\}/)
assert.match(renderSource, /v-on:accept-invitation=\{JS\.push\("accept_invitation"\)\}/)
assert.match(renderSource, /v-on:mark-read=\{JS\.push\("mark_read"\)\}/)
assert.match(renderSource, /v-ssr=\{false\}/)
assert.match(renderSource, /class="contents"/)
assert.doesNotMatch(renderSource, /<\.page_header|<\.empty_state|NotificationsPanel|notification_rows/)

const rawAttrsSource = sourceSlice(
  liveViewSource,
  "  @doc false\n  def presentation_attrs(attrs) when is_map(attrs) do",
  "  defp mark_notification_read(socket, id) do",
  "Notifications raw attribute projection",
)

assert.match(rawAttrsSource, /value in \[nil, false\]/)
assert.match(rawAttrsSource, /\{name, true\}, rendered/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, ""\)/)
assert.match(rawAttrsSource, /Map\.put\(rendered, name, to_string\(value\)\)/)

const assignmentSource = sourceSlice(
  liveViewSource,
  "  defp assign_notifications(socket, notifications) do",
  "  defp notification_row(%Notification{} = notification) do",
  "complete Notifications presentation assignment",
)

assert.match(assignmentSource, /notification_rows = Enum\.map\(notifications, &notification_row\/1\)/)
assert.match(assignmentSource, /assign\(:notifications, notifications\)/)
assert.match(
  assignmentSource,
  /assign\(:notifications_page_presentation, page_presentation\(notification_rows\)\)/,
)

for (const topLevelKey of ["root", "header", "empty_state", "panel"]) {
  assert.ok(assignmentSource.includes(`"${topLevelKey}" =>`), `${topLevelKey} stays in presentation`)
}

for (const text of [
  "Notifications",
  "Invitations, access grants, and system notices.",
  "No notifications",
  "All caught up.",
]) {
  assert.ok(assignmentSource.includes(`"${text}"`), `${text} stays Phoenix-owned`)
}

for (const className of [
  "space-y-4 max-w-2xl mx-auto",
  "border-b border-primary/20 pb-4",
  "mt-2 text-2xl font-bold text-base-content tracking-tight",
  "mt-1 max-w-3xl text-sm text-base-content/70",
  "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
  "hero-bell mx-auto h-10 w-10 text-base-content/30 block",
  "hud-label mt-3",
  "mt-2 max-w-md mx-auto text-sm text-base-content/70",
]) {
  assert.ok(assignmentSource.includes(`"${className}"`), `${className} stays Phoenix-owned`)
}

assert.match(assignmentSource, /"id" => "notifications-page"/)
assert.match(assignmentSource, /"id" => "notifications-empty-state"/)
assert.match(assignmentSource, /"id" => "notifications-panel-component"/)
assert.match(assignmentSource, /"notifications" => notification_rows/)
assert.match(assignmentSource, /empty_state_presentation\(notifications_empty\?\)/)
assert.match(assignmentSource, /panel_presentation\(notifications_empty\?, notification_rows\)/)

const markMutationSource = sourceSlice(
  liveViewSource,
  "  defp mark_notification_read(socket, id) do",
  "  defp assign_notifications(socket, notifications) do",
  "mark-read mutation",
)

assert.match(markMutationSource, /socket\.assigns\.current_scope\.user\.user_id/)
assert.match(markMutationSource, /Cadence\.Notifications\.mark_notification_read\(id, user_id\)/)
assert.match(markMutationSource, /replace_in_list\(socket\.assigns\.notifications, updated\)/)
assert.match(markMutationSource, /\{:error, _reason\} ->\n        \{:noreply, socket\}/)

for (const scenario of [
  'test "renders empty state when there are no notifications"',
  'test "renders invitation data and existing actions through LiveVue"',
  'test "accepts the invitation, flashes success, and navigates to /"',
  'test "flashes error if the invitation is already accepted"',
  'test "marks an owned notification read and updates its Vue prop"',
  'test "a new notification appears in the list via PubSub"',
  'test "unauthenticated request redirects to /sign-in"',
]) {
  assert.equal(
    liveViewTestSource.split(scenario).length - 1,
    1,
    `${scenario} remains present one-for-one`,
  )
}

assert.match(
  liveViewTestSource,
  /LiveVue\.Test\.get_vue\(view, id: "notifications-page-component"\)/,
)
assert.match(liveViewTestSource, /element\("#notifications-page-component"\)/)
assert.match(liveViewTestSource, /render_hook\(phoenix_event, payload\)/)
assert.match(liveViewTestSource, /Map\.keys\(vue\.props\) == \["presentation"\]/)
assert.match(liveViewTestSource, /Jason\.decode!\(Jason\.encode!\(presentation\)\) == presentation/)
assert.match(liveViewTestSource, /NotificationsLive\.presentation_attrs/)
assert.match(liveViewTestSource, /"nil" => nil/)
assert.match(liveViewTestSource, /"false" => false/)
assert.match(liveViewTestSource, /"true" => true/)
assert.match(liveViewTestSource, /"number" => 7/)

assert.match(
  routerSource,
  /scope "\/", CadenceWeb do\n    pipe_through \[:browser, :require_authenticated_scope\]/,
)

const userSessionSource = sourceSlice(
  routerSource,
  "    live_session :user,",
  "    live_session :admin,",
  "user LiveSession",
)

assert.match(userSessionSource, /CadenceWeb\.UserAuth, :require_user_scope/)
assert.match(userSessionSource, /CadenceWeb\.UserAuth, :attach_notifications_bell/)
assert.match(userSessionSource, /CadenceWeb\.UserAuth, :attach_user_menu/)
assert.match(userSessionSource, /layout: \{CadenceWeb\.Layouts, :user_shell\}/)
assert.match(userSessionSource, /live "\/notifications", NotificationsLive, :index/)
assert.doesNotMatch(userSessionSource, /require_organization_scope|load_mission|require_platform_admin/)

const requireUserSource = sourceSlice(
  userAuthSource,
  "  def on_mount(:require_user_scope",
  "  def on_mount(:attach_notifications_bell",
  "require-user mount",
)

assert.match(requireUserSource, /ScopeLoader\.assign_scope_from_session/)
assert.match(requireUserSource, /%Scope\{user: %_\{} = _user\}/)
assert.match(requireUserSource, /redirect\(socket, to: "\/sign-in"\)/)

const bellAttachSource = sourceSlice(
  bellSource,
  "  def attach(%{assigns: %{current_scope:",
  "  def attach(socket) do",
  "notifications-bell attachment",
)

assert.match(bellAttachSource, /Phoenix\.LiveView\.connected\?\(socket\)/)
assert.match(bellAttachSource, /Notifications\.subscribe\(user_id\)/)
assert.match(bellAttachSource, /attach_hook\(/)
assert.match(bellAttachSource, /:notifications_bell/)
assert.match(bellAttachSource, /:handle_info/)

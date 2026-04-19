# User menu popover — design

## Summary

Replace the plain-text `display_name (email)` label in the top-right of every authenticated shell with a clickable **user menu**: a trigger (display name + chevron) that opens a popover panel anchored to the trigger. The panel shows identity, current organization context with an inline org switcher for multi-org users, a system-administration link for platform admins, and sign out. Existing shell-level sign out buttons stay.

## Goals

- Make identity & org context an interactive affordance, not a passive label.
- Give multi-org users an in-shell way to switch organizations.
- Give platform admins a one-click jump to `/admin` from anywhere in the app.
- Reclaim header density by dropping the parenthesized email from the top bar; surface the email inside the panel where it has room to breathe.
- Keep the visual and interaction vocabulary of the HUD layer — no new CSS rules, no new component primitives beyond what daisyUI already provides.

## Non-goals

- Sidebar footer org block (mentioned during brainstorm; spun off as a separate future spec).
- Theme toggle, keyboard-shortcut overlay, "my missions" quick list, notification summary inside the user menu.
- Avatars / initials. No avatar concept exists yet; adding one implies upload, storage, and fallback behavior that is out of scope.
- A full-viewport-height slide-in rail. The popover pattern was selected for consistency with `notifications_bell` and because the content does not fill a rail.
- Removing the existing shell-level sign out buttons. They stay, per explicit user direction, for visual balance of the sidebar drawer footer.
- A dedicated org-chooser page. The switcher lives in the popover only.

## Affected surfaces

Three shell templates get a one-line swap each:

- `apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex` — replaces the email `<span>` in the header.
- `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex` — replaces the `display_name (email)` spans in both the desktop header bar and the mobile top bar.
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` — same two replacements as `sidebar.html.heex`.

The sidebar footer "Sign out" form in `sidebar.html.heex` and `mission_sidebar.html.heex` is untouched. The header-level "Sign out" form in `user_shell.html.heex` is untouched. `notifications_bell` is untouched.

## Component

**New stateless component** `CadenceWeb.UI.user_menu/1` in `apps/cadence_web/lib/cadence_web/components/ui.ex`, parallel to `notifications_bell/1`.

```elixir
attr :scope, :map, required: true
attr :memberships, :list, default: []
attr :platform_admin?, :boolean, default: false

def user_menu(assigns)
```

- `scope` — a `%CadenceWeb.CurrentScope{}` (or equivalent) that carries `user` and `organization`.
- `memberships` — a list of `%Cadence.Accounts.OrganizationMembership{}` with the `organization` association loaded. Used by the inline org switcher.
- `platform_admin?` — boolean derived upstream from capability check; when true the System Administration link is rendered.

The component has no server-owned state. Open/close is a CSS/daisyUI concern. Org switch and sign out are form submits to controller actions, not LiveView events.

## Trigger

A daisyUI ghost button in the top bar, to the right of `notifications_bell`:

```
  🔔   Jane Rost ▾
```

Markup outline:

```heex
<button type="button" tabindex="0" class="btn btn-ghost btn-sm gap-1" aria-haspopup="menu">
  <span class="text-xs text-base-content/60">{@scope.user.display_name}</span>
  <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform"></span>
</button>
```

- Resting: muted `text-base-content/60`, matches current treatment.
- Hover: ghost-button hover from daisyUI; chevron remains upright.
- Open: chevron rotated 180° via daisyUI dropdown's focus-within state or equivalent Tailwind arbitrary-variant.
- The email is no longer rendered in the trigger. It lives inside the panel.

## Panel

Uses the same daisyUI primitive as `notifications_bell`: `dropdown dropdown-end` with a `dropdown-content` panel.

```
                                          ┌──────────────────────────────┐
                                          │  Jane Rost                   │
                                          │  jane@example.com            │
                                          ├──────────────────────────────┤
                                          │  ORGANIZATION                │
                                          │  Acme Space            ▾    │   ← multi-org only
                                          ├──────────────────────────────┤
                                          │  ⚙  System administration    │   ← platform admin only
                                          ├──────────────────────────────┤
                                          │  ⎋  Sign out                 │
                                          └──────────────────────────────┘
```

Panel surface:

- `w-72` (288px) fixed width.
- `bg-base-200 border border-primary/20 shadow-lg`, no `hud-grid` (the panel is small; the grid pattern would read as noise at this size).
- Sharp corners (Tokyo Night default).
- `p-2` container padding; rows use `px-3 py-2`.
- Section separators use `border-t border-primary/10` (the softer inner divider), not the brighter `primary/20`.

Animation:

- Default daisyUI open/close plus a 120ms fade + 4px slide-up on enter, applied via Tailwind utilities on `dropdown-content` with an `opacity-0 translate-y-1` initial state gated by a `[&:not(:focus-within)]` selector.
- No custom CSS added. No JavaScript beyond what daisyUI ships.
- If the Tailwind-only animation proves janky in practice, the fallback is daisyUI's default transition alone — ship without the slide rather than introduce new CSS.

## Content — four conditional blocks

Each block is conditionally rendered based on `@scope`, `@memberships`, and `@platform_admin?`. Ordering is fixed.

### 1. Identity block (always)

```heex
<div class="px-3 py-2">
  <p class="text-sm font-semibold text-base-content">{@scope.user.display_name}</p>
  <p class="text-xs text-base-content/50 truncate">{@scope.user.email}</p>
</div>
```

Fallback: when `display_name` is blank, render the email in both slots (email only).

### 2. Organization block

Three shapes selected by `memberships` length and `scope.organization` presence:

| Condition | Rendering |
| --- | --- |
| `scope.organization` is `nil` | Block omitted entirely. (No-org users on `/no-organization`, `/invitations`.) |
| Exactly one membership | `ORGANIZATION` `hud-label` + org display name as read-only text. No chevron, not clickable. |
| More than one membership | `ORGANIZATION` `hud-label` + current org display name + `▾` chevron. Clicking expands an inline list of the user's other active memberships inside the same panel. Each other-org row is a `<button type="submit">` wrapped in a `<.form method="put" action={~p"/session/organization"}>` carrying a CSRF token and an `organization_id` hidden input. Phoenix's `<.form method="put">` emits the hidden `_method` override so the action dispatches to `PUT /session/organization` as described in the data-flow section. |

The inline-expand state is CSS-only (a `<details>`/`<summary>` pair, styled to match the HUD vocabulary), so it adds no JavaScript and no server round trip until the user actually switches.

### 3. System administration link

Rendered only when `@platform_admin?` is true.

```heex
<.link navigate={~p"/admin"} role="menuitem" class="flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary">
  <span class="hero-cog-6-tooth h-4 w-4 opacity-80"></span>
  System administration
</.link>
```

Section divider above: `border-t border-primary/10`.

### 4. Sign out (always)

Copy-paste of the existing shell-level form markup so the submission path is unchanged:

```heex
<.form for={%{}} as={:session} action={~p"/session"} method="delete">
  <button type="submit" role="menuitem" class="flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary">
    <span class="hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"></span>
    Sign out
  </button>
</.form>
```

Section divider above: `border-t border-primary/10`.

### Empty / broken states

- `current_scope` present but `current_scope.user` is nil → the whole menu is not rendered. The shells already guard on this.
- `display_name` is unexpectedly blank → fall back to email in the identity block.
- `memberships` is empty but `scope.organization` is set → treat as the single-membership shape (label only). This is a defensive fallback; it should not occur under normal conditions.

## Data flow

### Sources of `memberships` and `platform_admin?`

Two execution contexts need the values: LiveView-backed pages and controller-rendered pages (the no-org flow renders `user_shell` from a controller).

**LiveView context** — a new on-mount hook `CadenceWeb.UserAuth.attach_user_menu`:

- Called from the same `live_session` blocks that already attach `:attach_notifications_bell`.
- Reads `current_scope.user.user_id`.
- Calls `Cadence.Accounts.list_user_memberships(user_id)` once; assigns `:user_menu_memberships`.
- Derives `platform_admin?` via the existing capability check used by `CadenceWeb.AdminAuth`; assigns `:user_menu_platform_admin?`.
- Does not subscribe to PubSub. Membership changes are rare enough that a page refresh is acceptable for v1.

**Controller context** — a new plug `CadenceWeb.Plugs.AssignUserMenuContext`:

- Runs in the `:browser` pipeline after `UserAuth.fetch_current_user`.
- Same two assigns (`:user_menu_memberships`, `:user_menu_platform_admin?`) but on `conn.assigns`.
- When there is no authenticated user, assigns `[]` and `false`.

Shell templates read `assigns[:user_menu_memberships]` and `assigns[:user_menu_platform_admin?]` and forward them to `<.user_menu>`.

### Organization switch

Route: `PUT /session/organization`.

Action: a new `update/2` (named `switch_organization/2` in this doc for clarity) in the existing `CadenceWeb.UserSessionController`:

1. Read `organization_id` from params.
2. Call `Cadence.Accounts.fetch_user_membership(user_id, organization_id)` (new helper — see below). If it does not return an active membership, redirect back with a flash error. **This authorization check is mandatory.** Without it, any authenticated user could place any `organization_id` into their session.
3. On success, call the existing `maybe_put_current_organization/2` helper (promoted from private to package-local or duplicated — implementation detail) to write `:current_organization_id` into the session.
4. Redirect to `/` so the next page load reissues the scope via `ScopeLoader` with the new org.

The switch is **sticky** — it uses the same `:current_organization_id` session key that `CadenceWeb.Plugs.FetchBrowserCurrentScope` and `CadenceWeb.ScopeLoader` already read. No new session mechanism is introduced.

### Sign out

Reuses `DELETE /session` unchanged. No controller changes required.

### New Accounts API surface

Two small additions to `Cadence.Accounts`, each under ~20 lines, each with a matching proxy in the `Cadence` facade:

**`list_user_memberships/1`:**

```elixir
@spec list_user_memberships(binary()) :: [OrganizationMembership.t()]
def list_user_memberships(user_id) when is_binary(user_id)
```

Internally: reuses the existing private `active_membership_query/1`, preloads the `organization` association, orders by organization display name, maps rows to domain structs.

**`fetch_user_membership/2`:**

```elixir
@spec fetch_user_membership(binary(), binary()) ::
        {:ok, OrganizationMembership.t()} | {:error, :not_found}
def fetch_user_membership(user_id, organization_id)
  when is_binary(user_id) and is_binary(organization_id)
```

Internally: `active_membership_query(user_id)` filtered by `organization_id`, `Repo.one/1`, map to domain struct or return `{:error, :not_found}`. Used by the switch-org action as an authorization guard.

Both helpers go in `apps/cadence/lib/cadence/accounts.ex` next to `preferred_organization_membership/2` and `list_organization_members/1`. Both are exposed on the `Cadence` facade.

## Accessibility

- Trigger is a real `<button>`, tab-focusable, Enter/Space opens the panel.
- Trigger has `aria-haspopup="menu"` and `aria-expanded` that mirrors the dropdown's open state.
- Panel has `role="menu"`; each actionable row has `role="menuitem"`.
- The identity block has `role="presentation"` (it's content, not actionable).
- Escape closes the panel and outside-click dismisses it — daisyUI's default dropdown behavior.
- When the multi-org block is expanded, each other-org row is its own `<button>` in tab order.
- Focus management across an org switch is automatic: the action is a form POST that redirects, so focus resets to the new page's document root.

## Responsive behavior

- The mobile top bar (`lg:hidden`) in both sidebar shells already renders identity information. The trigger replaces the existing email span there, producing the same popover behavior on mobile.
- `dropdown-end` aligns the panel to the right edge of the trigger. At the narrowest viewports the `w-72` panel can approach the viewport edge; if end-to-end testing shows clipping, the fix is a `right-2` safety margin on the `dropdown-content`. No responsive-specific panel variant is built.

## Testing

### Component tests

`apps/cadence_web/test/cadence_web/components/ui_test.exs` (add to the existing module if present, otherwise create):

- Identity block renders for any `scope.user`.
- Org block hidden when `scope.organization` is nil.
- Org block renders label-only when `memberships` length is 1.
- Org block renders expandable switcher when `memberships` length > 1; each other-org row is a submit button targeting `PUT /session/organization` with the correct `organization_id`.
- System-admin link renders only when `platform_admin?` is true.
- Sign-out form is always present and targets `DELETE /session`.
- Identity block falls back to email when `display_name` is blank.

### Controller tests

`apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs`:

- `PUT /session/organization` with a valid active membership updates the `:current_organization_id` session key and redirects to `/`.
- `PUT /session/organization` for an org the user is not an active member of redirects back with a flash error and does **not** modify the session.
- Unauthenticated `PUT /session/organization` redirects to `/sign-in` (existing pipeline behavior; verify it's not bypassed).

### Accounts tests

For the two new helpers:

- `list_user_memberships/1` returns only active memberships, with the `organization` association preloaded, ordered by organization display name.
- `list_user_memberships/1` returns an empty list for a user with no memberships.
- `fetch_user_membership/2` returns `{:ok, membership}` for an active membership and `{:error, :not_found}` for any other case (nonexistent, revoked, wrong user).

### Integration / LiveView

- Existing LiveView tests under `live_session :admin` and `live_session :organization` pick up the `:attach_user_menu` hook automatically.
- One new integration test per shell (`user_shell`, `sidebar`, `mission_sidebar`) verifies the popover trigger and panel render with the expected identity and org content for a seeded user.

No new Playwright/feature test. The open/close interaction is CSS-only and the content assertions are covered by component + controller tests.

## Out-of-scope follow-ups

- Sidebar drawer footer: add an organization summary above the existing "Sign out" button in `sidebar.html.heex` and `mission_sidebar.html.heex`. Has its own design questions (collapsed-sidebar behavior, role rendering, duplication with the nav's org header). Will get its own spec.
- Expand the panel's content set (theme toggle, keyboard shortcuts, "my missions"). Defer until there's concrete demand.
- Convert the multi-org switcher into a recents-aware / searchable list once an org count large enough to need search exists.

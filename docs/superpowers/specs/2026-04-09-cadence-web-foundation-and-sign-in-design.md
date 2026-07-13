# Cadence Web Foundation and `/sign-in` Rebuild

**Date:** 2026-04-09
**Branch:** `arch/review`
**Status:** Design approved, pending implementation plan

## Problem

The current `cadence_web` umbrella app has:

- Zero LiveView modules (deps include `phoenix ~> 1.8.1` but not `phoenix_live_view`).
- No asset pipeline — no `tailwind`, `esbuild`, or `heroicons` deps, no `assets/` source directory, and a single hand-written 381-line `priv/static/assets/app.css` served directly.
- Controller-rendered HEEx templates with bespoke custom class names (`panel--hero`, `status-card`, `sign-in-form`, `eyebrow`, etc.) with no shared component vocabulary.
- A `/sign-in` page that renders two parallel forms (a durable operator login form and a setup-access login form), with `setup_access_available?` branching in the controller and separate error fields for each form.

This produces two problems the rewrite is explicitly trying to avoid:

1. **CSS drift.** Legacy Cadence's hand-rolled CSS grew into soup when AI drove most of the development, because every new page was a blank canvas with no shared vocabulary. The current `cadence_web` is already starting the same pattern.
2. **Components are not written.** Legacy AI-generated work inlined markup instead of extracting components, because there was no clear place for components to live and no stable primitive set to compose.

A separate but related problem is the `/sign-in` page itself: two parallel forms make the page overloaded and muddy which credential type an operator should use. A single unified login form is the target.

## Goals

- Stand up the asset pipeline and LiveView runtime in `cadence_web` so subsequent frontend work has a stable foundation.
- Establish a small, purposeful HEEx primitive component set that AI-driven development can compose instead of reinventing markup per page.
- Rebuild `/sign-in` as the first consumer of that foundation: a single LiveView-backed email+password form with a unified server-side auth handler.
- Leave the codebase in a state where the next slice (authenticated shell, then platform admin) can layer on cleanly without revisiting this foundation.
- Do not break `/setup`, `/operator`, or `/invitations/:token` in the transition.

## Non-goals

Out of scope for this slice, explicitly:

- `/setup` page redesign — stays on the compat shim.
- `/operator` page redesign — stays on the compat shim.
- `/invitations/:token` page redesign — stays on the compat shim.
- Platform admin routes (`/admin` and descendants) — future slice.
- Authenticated shell chrome: sidebar, navbar, user/org menu, notification bell, organization switcher.
- Password reset / forgot password flow.
- "Remember me" persistent sessions.
- Organization admin UI (distinct from platform admin UI).
- Rich-interactivity surfaces (timeline editor, context side panel, 3D orbital views) — future slices, possibly with targeted JS hooks.

## Anchoring decisions

The following decisions are inputs to this design and are not re-litigated here:

- **Frontend stack:** pure Phoenix LiveView + Tailwind. No daisyUI, no LiveSvelte, no LiveVue. Rich-interactivity surfaces will use targeted Phoenix JS hooks (the legacy pattern with `scichart`, `gridstack`, `dagre`, `@tanstack/table-core`) when they're needed; LiveSvelte revisits only if hooks concretely fail.
- **Aesthetic:** carry forward the legacy "Tokyo Night / Vaporwave / HUD mission control" look — sharp corners, dark base with subtle grid/mesh background, cyan primary, purple secondary, pink accent, hover-glow cards. The legacy CSS under `legacy/cadence_legacy/assets/css/` is visual reference, not code to port.
- **Page shape:** prefer focused pages per responsibility. No single page should accumulate multiple unrelated forms and status cards.
- **Single login form on `/sign-in`:** the parallel durable/setup-access forms go away. The server dispatches to the right credential kind based on the email's active credentials; setup-access is invisible to the user.

## Foundation

### Mix deps

Add to `apps/cadence_web/mix.exs`:

- `{:phoenix_live_view, "~> 1.1"}`
- `{:tailwind, "~> 0.3", runtime: Mix.env() == :dev}`
- `{:esbuild, "~> 0.10", runtime: Mix.env() == :dev}`
- `{:heroicons, github: "tailwindlabs/heroicons", tag: "v2.1.1", sparse: "optimized", app: false, compile: false, depth: 1}`

### Asset source layout

This slice commits to **Tailwind v4**, matching legacy Cadence's choice (legacy's `assets/css/app.css` used the v4 `@import "tailwindcss"` syntax with `@plugin` directives). Tailwind v4 is CSS-first: theme tokens, plugin registration, and content source globs all live inside `app.css` via `@theme`, `@plugin`, and `@source` directives. There is **no** traditional `tailwind.config.js` file.

New directory at `apps/cadence_web/assets/`:

- `css/app.css` — the sole Tailwind v4 entry point. Contains, in order:
  1. `@import "tailwindcss" source(none);` — Tailwind v4 base import.
  2. `@source "../../lib/cadence_web";` — content globs pointing Tailwind at the HEEx templates and Elixir files.
  3. `@source "../js";` — content globs for any classes referenced from JS.
  4. `@plugin "../vendor/heroicons";` — heroicons plugin (path relative to `app.css`; see below).
  5. A `@theme` block mapping the Tokyo Night palette (ported as color values, not CSS code, from `legacy/cadence_legacy/assets/css/app.css`) to Tailwind color tokens: `--color-base-100`, `--color-base-200`, `--color-base-300`, `--color-base-content`, `--color-primary`, `--color-secondary`, `--color-accent`, `--color-info`, `--color-success`, `--color-warning`, `--color-error`, and their `-content` pairs. Plus radius, border, and depth variables for the HUD aesthetic.
  6. The legacy compat `@layer` (see Transition section).
  7. Any small global rules (body background mesh, font-family) that are cleaner as raw CSS than as utility classes.
- `js/app.js` — LiveView socket setup, empty hooks registry for future use.
- `vendor/heroicons.js` — the Phoenix 1.8 heroicons Tailwind plugin. This is a small JavaScript file that reads SVGs from `deps/heroicons/optimized` (installed by the `heroicons` Mix github dep) and exposes them as `hero-*` utility classes. Phoenix 1.8's `phx.new` template ships a reference version of this file; the same file is copied in here.

### Config

Add to `config/config.exs`:

- `config :tailwind, version: "4.0.9"` (or latest 4.x at implementation time), plus a default profile that reads `apps/cadence_web/assets/css/app.css` and writes `apps/cadence_web/priv/static/assets/app.css`.
- `config :esbuild, version: "0.21.5"` (pinned), plus a default profile that reads `apps/cadence_web/assets/js/app.js` and writes `apps/cadence_web/priv/static/assets/app.js`, with `--bundle --target=es2022`.
- Dev watchers in `config/dev.exs` wired into `CadenceWeb.Endpoint` so both tasks run on file changes.

Add Mix aliases at the umbrella root or in `apps/cadence_web/mix.exs`:

- `assets.setup` — installs tailwind and esbuild binaries
- `assets.build` — runs both tasks once
- `assets.deploy` — production build with `--minify`

### Runtime wiring

- `CadenceWeb.Endpoint` gains `socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]`, where `@session_options` is the existing session config module attribute (adding it if it does not exist yet).
- The `:browser` pipeline in `CadenceWeb.Router` swaps `plug :fetch_flash` for `plug :fetch_live_flash` and updates the root layout plug to reference the new `CadenceWeb.Layouts` module.
- `CadenceWeb.Layouts` module at `lib/cadence_web/components/layouts.ex`, with HEEx templates at `lib/cadence_web/components/layouts/`:
  - `layouts/root.html.heex` — HTML skeleton, asset tags wired to the new Tailwind/esbuild output (`/assets/app.css` and `/assets/app.js`), CSRF meta, live reload hooks in dev, flash group.
  - `layouts.ex` uses `embed_templates "layouts/*"` to pull the templates in, following Phoenix 1.8 convention.
  - An `app/1` function component defined in `layouts.ex` wrapping pages with the outer frame (grid background, min-height, mesh overlay), the legacy's `.app-root` / `.app-shell` structure expressed as Tailwind utilities inside the component body.
- `lib/cadence_web.ex` (the `CadenceWeb` module) gets a `live_view` helper matching the Phoenix 1.8 convention: imports `Phoenix.LiveView`, uses the new `CadenceWeb.Layouts` as the default layout, imports the new `CadenceWeb.UI` primitive module and the existing `CadenceWeb.CoreComponents` for shared helpers.

## Primitive component set

A new module `CadenceWeb.UI` at `lib/cadence_web/components/ui.ex` exposing the smallest set of function components that `/sign-in` actually needs. Each primitive uses Tailwind utilities internally — no hand-written CSS classes.

Initial primitives:

- `panel/1` — hero panel shape (dark base, subtle border, inner glow, padding). Accepts `variant={:hero | :compact}` and an inner slot.
- `eyebrow/1` — small uppercase label, cyan accent.
- `hero_title/1` — oversized headline with tight leading.
- `hero_copy/1` — supporting prose paragraph with muted foreground.
- `text_field/1` — labeled input (type `:email | :text | :password`), wraps a Phoenix form field, supports `autocomplete`, shows an inline error from the field.
- `button/1` — `variant={:primary | :secondary | :ghost}`, renders as a form submit by default, supports a `kind={:button | :submit}` override.
- `form_error/1` — error line under a form, tied to a specific error string or absent.

Constraints on the primitive set:

- Each component is 20–40 lines of HEEx + Tailwind. No inheritance, no deep slot composition, no macro gymnastics.
- Components live in one module (`CadenceWeb.UI`) for this slice. If it grows past ~400 lines, subsequent slices split it by concern.
- No navbar, sidebar, user/org menu, notification bell, or authenticated-shell chrome in this set. Those are explicitly deferred.
- The primitive set is intentionally driven by demand from `/sign-in`. A second consumer (admin landing, in a future slice) will extend it, but it must not be built speculatively in this slice.

## `/sign-in` rebuild

### LiveView

New `CadenceWeb.UserSessionLive` at `lib/cadence_web/live/user_session_live.ex`:

- Mounts at `GET /sign-in` via a LiveView route in the `:redirect_if_authenticated_scope` pipeline.
- Renders a single `<.panel variant={:hero}>` containing:
  - `<.eyebrow>` — "Cadence Access"
  - `<.hero_title>` — single headline for sign-in
  - `<.hero_copy>` — short context line
  - One form with email + password fields using `<.text_field>`, with fields scoped under the `user` form-name (params arrive at the controller as `%{"user" => %{"email" => ..., "password" => ...}}`)
  - A primary `<.button>` — "Sign In"
  - Optional `<.form_error>` under the form for error display
- Client-side interaction via `phx-change` on the form for live validation feedback (empty fields, missing `@`, etc.).
- **No `phx-submit` handler.** The form submits via a standard HTML `action={~p"/sign-in"}` attribute posting to the `UserSessionController.create` action. This is the Phoenix 1.8 blessed pattern for auth forms because session cookie establishment must happen in a controller (not in a LiveView socket), and it keeps session state transitions on a normal HTTP request. The LiveView owns the UX (validation, rendering, error display from flash); the controller owns the session transition.
- On error, the controller redirects back to `/sign-in` with a `:error` flash; the LiveView picks that up on re-mount and displays it through `<.form_error>`.
- No parallel second form. No setup-access-specific UI.

### Credential dispatch strategy

The controller does **not** cascade login attempts. Cascading (try durable first, fall back to bootstrap on `:invalid_credentials`) has three drawbacks:

1. It does two password verifications in the fallback case (expensive and creates a timing side-channel distinguishing "wrong durable password" from "wrong bootstrap password").
2. It leaks bootstrap/setup-access knowledge into the controller layer.
3. It makes the controller responsible for coordinating two Accounts-layer calls with different error handling, which is exactly the kind of business logic that belongs in the Accounts context.

Instead, the dispatch is moved into the Accounts context via a new `Accounts.sign_in/2` function that looks up the user's active credentials first, picks which credential kind applies, and calls exactly one password verification path. This keeps the controller trivially thin and keeps the "what counts as a valid login" decision where the credential schema lives.

### Accounts layer — new `sign_in/2`

New function `Cadence.Accounts.sign_in/2`:

```
@spec sign_in(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
def sign_in(email, password) when is_binary(email) and is_binary(password) do
  normalized_email = User.normalize_email(email)

  with %UserRow{} = user_row <-
         Repo.get_by(UserRow,
           email: normalized_email,
           lifecycle_state: Atom.to_string(:active)
         ),
       %User{} = user <- UserRow.to_domain(user_row),
       {:ok, credential_kind} <- resolve_credential_kind(user) do
    case credential_kind do
      :durable -> login_user_with_user(user, password)
      :bootstrap_admin -> login_bootstrap_admin_with_user(user, password)
    end
  else
    nil -> {:error, :invalid_credentials}
    {:error, _reason} = error -> error
  end
end

defp resolve_credential_kind(%User{user_id: user_id}) do
  has_password = active_credential?(user_id, @password_provider_key)
  has_bootstrap = active_credential?(user_id, @bootstrap_provider_key)

  cond do
    has_password ->
      {:ok, :durable}

    has_bootstrap and bootstrap_admin_enabled?() and setup_pending?() ->
      {:ok, :bootstrap_admin}

    true ->
      {:error, :invalid_credentials}
  end
end

defp setup_pending? do
  # Mirrors `Cadence.initial_setup_pending?/0` on the facade, but lives as a
  # private helper inside Accounts to avoid reaching back through the root
  # Cadence module from a context. Calls `Cadence.Setup.fetch_initial_workflow/0`
  # and `Cadence.Setup.active?/1` directly; treats `:invalid_setup_state` as
  # "pending" to match the facade's defensive default.
end
```

**Precedence rules, explicit:**

- **Durable wins if present.** If a user has an active `password` credential, `sign_in/2` always dispatches to the durable login path — even if they also have a `bootstrap_env` credential and setup is still pending. A durable credential is the canonical login method once it exists; the bootstrap credential becomes dead data that can be garbage-collected later.
- **Bootstrap admin only during first-run setup.** If a user has only a `bootstrap_env` credential, `sign_in/2` dispatches to the bootstrap login path only if `bootstrap_admin_enabled?()` **and** `setup_pending?()` (the private helper that checks `Cadence.Setup.fetch_initial_workflow/0` + `Cadence.Setup.active?/1`) are both true. Once first-run setup is marked complete, the bootstrap credential is no longer usable through `sign_in/2` — even though it still exists in the database — and the user gets `:invalid_credentials`. This matches the current UI's "setup access form disappears after setup completes" behavior but tightens it: previously the current server accepted bootstrap logins even after setup completed (because `login_bootstrap_admin/2` itself only gates on `bootstrap_admin_enabled?`), the UI just hid the form. The new unified `sign_in/2` enforces the tighter gate.
- **Neither credential present or unusable.** Returns `:invalid_credentials`. No timing distinction between "email not found," "email found but no credentials," and "email found with wrong password" — all three paths fail with the same error.

**Preserving existing functions:** `Accounts.login_user/2` and `Accounts.login_bootstrap_admin/2` are **not deleted**. `BootstrapAdminSessionController` uses `login_bootstrap_admin/2` directly for first-run administration. The external `cadence_simulator` application does not use Cadence bootstrap authentication or create Cadence resources. The login functions may be internally refactored to share the `login_user_with_user/2` / `login_bootstrap_admin_with_user/2` helpers with `sign_in/2`, but their public shape stays.

**Cadence facade:** new `Cadence.sign_in/2` delegates to `Auth.sign_in/2`, which delegates to `Accounts.sign_in/2`. Matches the existing `Cadence.login_user/2` / `Cadence.login_bootstrap_admin/2` delegation chain.

### Controller

With the dispatch in the Accounts layer, `CadenceWeb.UserSessionController.create/2` collapses to:

```
def create(conn, %{"user" => credentials}) do
  with {:ok, {email, password}} <- ControlPlaneParams.durable_session(credentials),
       {:ok, session} <- Cadence.sign_in(email, password) do
    finalize_sign_in(conn, session, "Signed in.")
  else
    {:error, reason} ->
      conn
      |> put_flash(:error, human_message(reason))
      |> redirect(to: ~p"/sign-in")
  end
end
```

Param validation uses the existing `CadenceWeb.ControlPlaneParams.durable_session/1` helper — it accepts the same `%{"email" => ..., "password" => ...}` shape the new unified flow needs, and no `ControlPlaneParams` changes are required. `setup_access_session/1` stays for `BootstrapAdminSessionController` but is no longer called from `UserSessionController`.

No `setup_access_fallback_enabled?/0` helper. No bootstrap admin knowledge in the controller. No dual branching. The `"Setup access session established."` flash message is gone — sign-ins are all labeled the same way from the user's perspective, since the dispatch is invisible.

Error handling uses `put_flash(:error, human_message(reason)) |> redirect(to: ~p"/sign-in")`, not re-rendering with form assigns, because the form lives in a LiveView and flash is the cleanest handoff for a controller action to pass error state back to it. The `human_message/1` private helper replaces the old `error_message/1` — it maps reason atoms to human strings and drops the dual-error-field distinction.

`finalize_sign_in/3`, `maybe_put_current_organization/2`, `renew_browser_session/1`, `revoke_session_token/1`, and `redirect_target/2` all stay unchanged. Setup-access sessions still land on `/setup` (because `Cadence.authenticate_api_token` still marks them as `temporary_setup_access`), and durable sessions still land on `/operator` (or the pre-login `user_return_to`).

### Deleted / simplified

From `UserSessionController`:
- `render_sign_in/5` and its two-form plumbing
- `setup_access_available?/0`
- `durable_form/0,1` and `setup_access_form/0,1`
- The `create_durable_session/2` and `create_setup_access_session/2` branches and their `Map.has_key?` dispatching in `create/2`
- Parallel `durable_error_message` / `setup_access_error_message` assigns
- `error_status/1` simplified (or removed if unused) — a single error path means we no longer need to distinguish bootstrap-disabled status codes from generic invalid credential codes for UI purposes

From `lib/cadence_web/controllers/user_session_html/new.html.heex` and `lib/cadence_web/controllers/user_session_html.ex`: deleted entirely, replaced by `CadenceWeb.UserSessionLive`.

From `lib/cadence_web/control_plane_params.ex`: **no changes.** `durable_session/1` stays (the new unified controller calls it). `setup_access_session/1` stays (`BootstrapAdminSessionController` still calls it).

From `apps/cadence/lib/cadence/accounts.ex`: **no deletions.** `login_user/2` and `login_bootstrap_admin/2` stay as-is (still used by `BootstrapAdminSessionController` and `cadence_simulator`). The new `sign_in/2` is additive.

From `apps/cadence/lib/cadence/auth.ex`: **no deletions.** Adds `sign_in/2` as a thin delegator to `Accounts.sign_in/2`.

From `apps/cadence/lib/cadence.ex`: **no deletions.** Adds `sign_in/2` as a thin delegator to `Auth.sign_in/2`.

### Router update

`router.ex`:

```
scope "/", CadenceWeb do
  pipe_through [:browser, :redirect_if_authenticated_scope]

  live "/sign-in", UserSessionLive, :new
  post "/sign-in", UserSessionController, :create
end
```

The `GET /sign-in` is now a `live` route; `POST /sign-in` stays on the controller.

## Tests

### New: `Accounts.sign_in/2` unit tests

Add unit tests for `Accounts.sign_in/2` in the appropriate existing accounts test file (`apps/cadence/test/cadence/accounts_test.exs` or equivalent). Cover the full dispatch matrix:

- **Durable credential only, correct password** → `{:ok, session}` with `session.temporary_setup_access? == false`.
- **Durable credential only, wrong password** → `{:error, :invalid_credentials}`.
- **Durable credential only, user unconfirmed** → `{:error, :invalid_credentials}`.
- **Durable credential only, user inactive** → `{:error, :invalid_credentials}`.
- **Bootstrap credential only, `bootstrap_admin_enabled?` true, setup pending, correct password** → `{:ok, session}` with `temporary_setup_access? == true`.
- **Bootstrap credential only, `bootstrap_admin_enabled?` true, setup pending, wrong password** → `{:error, :invalid_credentials}`.
- **Bootstrap credential only, `bootstrap_admin_enabled?` false** → `{:error, :invalid_credentials}` (gate rejects).
- **Bootstrap credential only, `bootstrap_admin_enabled?` true, setup complete** → `{:error, :invalid_credentials}` (tighter gate than the existing `login_bootstrap_admin/2`).
- **Both credentials present, correct durable password** → `{:ok, session}` via durable path (`temporary_setup_access? == false`). Verifies durable precedence.
- **Both credentials present, wrong durable password, correct bootstrap password** → `{:error, :invalid_credentials}`. Verifies no fallback from durable to bootstrap when durable is present.
- **Email not found** → `{:error, :invalid_credentials}`.

### Existing: `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`

Update assertions to match the new single-form shape:

- **Remove:** any assertion that the page renders a second form labeled "Setup Access" or similar.
- **Remove:** any assertion that a setup-access-specific error appears separately from a durable-login error.
- **Keep:** durable login success → redirect to `/operator`.
- **Keep:** durable login failure → error flash, rerender `/sign-in`.
- **Keep:** sign-out test, invitation acceptance test.
- **Add:** during first-run setup with bootstrap admin enabled, submitting the configured bootstrap admin credentials on `/sign-in` signs the user in and redirects to `/setup`. (Same POST endpoint, no separate form.)
- **Add:** after first-run setup completes, submitting the bootstrap admin credentials fails with `:invalid_credentials`.

### New: `apps/cadence_web/test/cadence_web/live/user_session_live_test.exs`

- `mount/3` smoke test — page renders with the single form, the hero header, and the sign-in button.
- `phx-change` validation — empty email field surfaces an inline error via the form component.
- The form posts to `UserSessionController.create` (assert the form action attribute points at `~p"/sign-in"`).

## Transition: CSS compat shim

`/setup`, `/operator`, and `/invitations/:token` currently reference hand-written class names from the old `priv/static/assets/app.css`: `panel--hero`, `status-card`, `sign-in-form`, `eyebrow`, `hero-title`, `hero-copy`, `summary-grid`, `status-card__label`, `status-card__title`, `status-card__body`, `button button--primary`, `button button--secondary`, `sign-in-form__actions`, `sign-in-form__note`, `panel__error`.

These pages are out of scope for this slice. To keep them rendering while the foundation lands, a compat shim in the new `assets/css/app.css` preserves these class names using Tailwind `@apply` rules built against the new palette. Schematic (the real implementation fills each rule with the actual utilities that reproduce the legacy visual):

```css
@layer legacy-compat {
  .panel--hero { @apply /* utilities that match legacy .panel--hero */; }
  .status-card { @apply /* ... */; }
  .status-card__label { @apply /* ... */; }
  .status-card__title { @apply /* ... */; }
  .status-card__body { @apply /* ... */; }
  .summary-grid { @apply /* ... */; }
  .sign-in-form { @apply /* ... */; }
  .sign-in-form__actions { @apply /* ... */; }
  .sign-in-form__note { @apply /* ... */; }
  .button { @apply /* ... */; }
  .button--primary { @apply /* ... */; }
  .button--secondary { @apply /* ... */; }
  .eyebrow { @apply /* ... */; }
  .hero-title { @apply /* ... */; }
  .hero-copy { @apply /* ... */; }
  .panel__error { @apply /* ... */; }
}
```

The actual utility lists come from reading the existing `apps/cadence_web/priv/static/assets/app.css` rules for each class and translating them into Tailwind utilities against the new palette. The implementation plan will enumerate the specific translations; for the design, it is enough to commit that the shim will reproduce the current visual for these classes with enough fidelity that `/setup`, `/operator`, and `/invitations/:token` do not regress visibly.

The shim is not a permanent component layer. It exists only to bridge the slices between "Tailwind pipeline exists" and "every page has been ported to the primitive set." Each subsequent slice that ports a page to primitives is responsible for removing the shim rules that page was using.

The old `priv/static/assets/app.css` (the static hand-rolled file) is deleted in this slice — the Tailwind build output replaces it at the same path. Because the old file was the sole stylesheet and the Tailwind build writes to the same path, the template `<link rel="stylesheet" href="/assets/app.css">` tag continues to work without change.

## Branch and commit shape

- Work happens on `arch/review` on top of `7305cd1 some basic ui`.
- The slice should land in three commits, not one monolith:
  1. **Asset pipeline foundation.** Add `phoenix_live_view`, `tailwind`, `esbuild`, `heroicons` to `apps/cadence_web/mix.exs`. Add `config :tailwind` and `config :esbuild` to `config/config.exs`. Wire dev watchers in `config/dev.exs`. No template changes. No LiveView runtime wiring yet. After this commit, the tree compiles and all existing tests pass (new deps are not yet used).
  2. **Asset sources, layouts, and compat shim.** Create `apps/cadence_web/assets/{css,js,vendor}/` with `app.css`, `app.js`, and `heroicons.js`. Port the Tokyo Night palette into the `@theme` block and write the legacy compat shim for the existing class names. Add `CadenceWeb.Layouts` module with `root.html.heex` and an `app/1` function component. Wire `CadenceWeb.Endpoint` with the LiveView socket and `CadenceWeb.Router` with `fetch_live_flash` and the new root layout. Update `lib/cadence_web.ex` with a `live_view` helper. Delete the hand-rolled static `apps/cadence_web/priv/static/assets/app.css` (the Tailwind build will overwrite the same path). After this commit, `/sign-in`, `/setup`, `/operator`, and `/invitations/:token` all still render via their existing controllers, styled by the compat shim. All existing tests pass.
  3. **Unified `sign_in/2`, primitive component set, `/sign-in` LiveView, and test updates.** In `cadence`: add `Accounts.sign_in/2` with the credential-kind dispatch and precedence rules, add `Auth.sign_in/2` and `Cadence.sign_in/2` delegators, add the unit tests for `Accounts.sign_in/2`. In `cadence_web`: add `CadenceWeb.UI` with the initial primitives, add `CadenceWeb.UserSessionLive`, collapse `UserSessionController.create/2` to the single `Cadence.sign_in/2` call, update the router to make `GET /sign-in` a `live` route, delete `user_session_html.ex` and `user_session_html/new.html.heex`, update `browser_shell_test.exs` assertions to match the single-form shape, add `user_session_live_test.exs`. After this commit, `/sign-in` is served by the LiveView, dispatched through `Accounts.sign_in/2`, and all tests pass.
- Each commit must leave the tree compiling and all tests passing. The commits are sized so that no intermediate state has broken tests.

## Open questions

None blocking. One thing to revisit in the next slice: whether the authenticated shell (sidebar + navbar + user/org menu) belongs as a separate `CadenceWeb.Layouts.authenticated_app/1` function component, or as a full set of shell primitives in `CadenceWeb.UI.Shell`. That's a decision for the next slice's design doc, not this one.

## Future slices (sketch, not committed by this doc)

For context only:

1. **Authenticated shell** — sidebar, user/org menu, flash plumbing for LiveView, nav chrome.
2. **Platform admin landing** — `/admin`, gated on `platform_admin` capability, stats cards (orgs / users / invitations), quick-action links. Legacy's `AdminLive.Index` is the visual reference.
3. **Platform admin: organization list and detail** — CRUD for organizations at the platform level.
4. **Platform admin: user list and session revocation** — view all users, their memberships, revoke active sessions.
5. **Platform admin: invitation issuance outside the setup flow** — a platform admin can invite people after first-run setup has completed.
6. **Retire `/setup`** — once platform admin owns org creation and invitation issuance for platform admins, collapse or remove first-run setup surface.

Each of those will have its own design doc and implementation plan.

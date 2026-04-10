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
- **Single login form on `/sign-in`:** the parallel durable/setup-access forms go away. Setup-access becomes an invisible server-side fallback.

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

### Controller

`CadenceWeb.UserSessionController.create/2` is refactored to a unified cascading auth flow. Param validation uses the existing `CadenceWeb.ControlPlaneParams` helpers without modifying them — `durable_session/1` normalizes the primary path, `setup_access_session/1` normalizes the fallback path, both expecting the shape `%{"email" => ..., "password" => ...}`.

Schematic (not final code — the implementation plan will flesh this out):

```
def create(conn, %{"user" => credentials}) do
  with {:ok, {email, password}} <- ControlPlaneParams.durable_session(credentials) do
    case Cadence.login_user(email, password) do
      {:ok, session} ->
        finalize_sign_in(conn, session, "Signed in.")

      {:error, :invalid_credentials} ->
        if setup_access_fallback_enabled?() do
          attempt_setup_access_fallback(conn, credentials)
        else
          redirect_with_error(conn, :invalid_credentials)
        end

      {:error, reason} ->
        redirect_with_error(conn, reason)
    end
  else
    {:error, reason} -> redirect_with_error(conn, reason)
  end
end

defp attempt_setup_access_fallback(conn, credentials) do
  with {:ok, {email, password}} <- ControlPlaneParams.setup_access_session(credentials),
       {:ok, session} <- Cadence.login_bootstrap_admin(email, password) do
    finalize_sign_in(conn, session, "Setup access session established.")
  else
    {:error, _reason} -> redirect_with_error(conn, :invalid_credentials)
  end
end

defp setup_access_fallback_enabled? do
  Cadence.initial_setup_pending?() and Cadence.bootstrap_admin_enabled?()
end
```

`setup_access_fallback_enabled?/0` is a private helper in `UserSessionController` and does not need to be exposed from the `Cadence` facade. The setup-access path is invisible to the user: they type a single set of credentials, the server tries durable login first, and falls back to bootstrap login only during first-run setup when the bootstrap admin is enabled. Once setup is complete, the fallback path is gone and only durable credentials work.

Error handling uses `put_flash(:error, human_message(reason)) |> redirect(to: ~p"/sign-in")`, not re-rendering with form assigns, because the form lives in a LiveView and flash is the cleanest handoff for a controller action to pass error state back to it. The `error_message/1` private helper (existing) maps reason atoms to human messages and is simplified to drop the dual-error-field distinction.

`redirect_target/2` is unchanged: setup-access sessions still land on `/setup`, durable sessions on `/operator` (or the pre-login `user_return_to`).

### Deleted / simplified

From `UserSessionController`:
- `render_sign_in/5` and its two-form plumbing
- `setup_access_available?/0`
- `durable_form/0,1` and `setup_access_form/0,1`
- The `create_durable_session/2` and `create_setup_access_session/2` branches
- Parallel `durable_error_message` / `setup_access_error_message` assigns

From `lib/cadence_web/controllers/user_session_html/new.html.heex` and `lib/cadence_web/controllers/user_session_html.ex`: deleted entirely, replaced by `CadenceWeb.UserSessionLive`.

From `lib/cadence_web/control_plane_params.ex`: `setup_access_session/1` stays (the controller still calls it in the fallback), `durable_session/1` stays (the controller still calls it in the primary path). No `ControlPlaneParams` changes in this slice.

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

### Existing: `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`

Update assertions to match the new single-form shape:

- **Remove:** any assertion that the page renders a second form labeled "Setup Access" or similar.
- **Remove:** any assertion that a setup-access-specific error appears separately from a durable-login error.
- **Keep:** durable login success → redirect to `/operator`.
- **Keep:** durable login failure → error flash, rerender `/sign-in`.
- **Keep:** sign-out test, invitation acceptance test.
- **Add:** during first-run setup with bootstrap admin enabled, submitting the configured bootstrap admin credentials on `/sign-in` signs the user in via the fallback and redirects to `/setup`.
- **Add:** after first-run setup completes, submitting the bootstrap admin credentials fails with `:invalid_credentials` (fallback is no longer enabled).

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
  3. **Primitive component set, `/sign-in` LiveView, and test updates.** Add `CadenceWeb.UI` with the initial primitives. Add `CadenceWeb.UserSessionLive`. Refactor `UserSessionController.create/2` to the unified cascading auth flow. Update the router to make `GET /sign-in` a `live` route. Delete `user_session_html.ex` and `user_session_html/new.html.heex`. Update `browser_shell_test.exs` assertions to match the single-form shape. Add `user_session_live_test.exs`. After this commit, `/sign-in` is served by the LiveView and all tests pass.
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

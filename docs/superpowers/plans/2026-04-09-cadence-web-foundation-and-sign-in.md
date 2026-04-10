# Cadence Web Foundation and `/sign-in` Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Phoenix LiveView + Tailwind v4 asset pipeline in `cadence_web`, establish a small HEEx primitive component set, and rebuild `/sign-in` as a LiveView-backed single-form page that dispatches to the right credential kind via a new `Cadence.sign_in/2` function in the Accounts context.

**Architecture:** Introduce the asset toolchain first with zero runtime changes, then add asset sources + runtime wiring + a CSS compat shim that keeps the legacy pages rendering, then add `Accounts.sign_in/2` + UI primitives + the LiveView page + controller refactor as one coherent feature commit. Three milestone commits, TDD where the logic warrants it (Accounts), integration tests via LiveViewTest for the LiveView.

**Tech Stack:** Elixir, Phoenix 1.8, Phoenix LiveView 1.1, Tailwind CSS 4 (via the Hex `tailwind` package), esbuild (via the Hex `esbuild` package), heroicons (via github Mix dep), PostgreSQL via Ecto.

**Spec:** [`docs/superpowers/specs/2026-04-09-cadence-web-foundation-and-sign-in-design.md`](../specs/2026-04-09-cadence-web-foundation-and-sign-in-design.md)

---

## File inventory

Files that will be **created**:

| Path | Responsibility |
|---|---|
| `apps/cadence_web/assets/css/app.css` | Sole Tailwind v4 entry. Theme block, plugin imports, source globs, compat shim. |
| `apps/cadence_web/assets/js/app.js` | LiveView socket setup, empty hooks registry. |
| `apps/cadence_web/assets/vendor/heroicons.js` | Phoenix heroicons Tailwind plugin. |
| `apps/cadence_web/lib/cadence_web/components/ui.ex` | `CadenceWeb.UI` — HEEx primitive components (panel, eyebrow, hero_title, hero_copy, text_field, button, form_error). |
| `apps/cadence_web/lib/cadence_web/live/user_session_live.ex` | `CadenceWeb.UserSessionLive` — `/sign-in` page. |
| `apps/cadence/test/cadence/accounts_test.exs` | Unit tests for `Accounts.sign_in/2`. |
| `apps/cadence_web/test/cadence_web/live/user_session_live_test.exs` | LiveView tests for `/sign-in`. |

Files that will be **modified**:

| Path | Change |
|---|---|
| `apps/cadence_web/mix.exs` | Add `phoenix_live_view`, `tailwind`, `esbuild`, `heroicons` deps. Add `assets.*` aliases. |
| `config/config.exs` | Add `config :tailwind` and `config :esbuild` default profiles. |
| `config/dev.exs` | Add `watchers:` to `CadenceWeb.Endpoint` config. |
| `apps/cadence_web/lib/cadence_web.ex` | Add `live_view/0` helper. Import `CadenceWeb.UI` in `html_helpers/0`. |
| `apps/cadence_web/lib/cadence_web/endpoint.ex` | Add `socket "/live", Phoenix.LiveView.Socket, ...`. Extract `@session_options` to a module attribute shared between `Plug.Session` and the socket. |
| `apps/cadence_web/lib/cadence_web/router.ex` | Change `/sign-in` from `get` to `live`. Swap `plug :fetch_flash` for `plug :fetch_live_flash` in the `:browser` pipeline so LiveView-backed pages see controller-set flash messages after a redirect. |
| `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex` | Collapse `create/2` to a single `Cadence.sign_in/2` call. Delete dual-form plumbing and helpers. |
| `apps/cadence_web/lib/cadence_web/components/layouts/root.html.heex` | Add the `<script>` tag for `/assets/app.js`. |
| `apps/cadence/lib/cadence/accounts.ex` | Add `sign_in/2` public function, `resolve_credential_kind/1` private helper, `active_credential?/2` private helper, `fetch_active_user_by_email/1` private helper, `setup_pending?/0` private helper. No changes to `login_user/2` / `login_bootstrap_admin/2`. |
| `apps/cadence/lib/cadence/auth.ex` | Add `sign_in/2` delegator to `Accounts.sign_in/2`. |
| `apps/cadence/lib/cadence.ex` | Add `sign_in/2` delegator to `Auth.sign_in/2`. |
| `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs` | Rewrite tests to use unified `%{"user" => %{...}}` param shape, flash+redirect error handling, and the tightened bootstrap gate. |
| `.gitignore` | Add `apps/*/priv/static/assets/` to exclude Tailwind build output. |

Files that will be **deleted**:

| Path | Reason |
|---|---|
| `apps/cadence_web/lib/cadence_web/controllers/user_session_html.ex` | Replaced by `CadenceWeb.UserSessionLive`. |
| `apps/cadence_web/lib/cadence_web/controllers/user_session_html/new.html.heex` | Replaced by `CadenceWeb.UserSessionLive.render/1`. |
| `apps/cadence_web/priv/static/assets/app.css` (tracked git copy) | Replaced by Tailwind build output at the same path (now gitignored). |

---

## Critical conventions

**Working directory:** Run all commands from the umbrella root `/Users/donovanrost/projects/cadence/cadence` unless otherwise specified.

**Test commands:**
- Full suite: `mix test`
- Just `cadence`: `mix cmd --app cadence mix test`
- Just `cadence_web`: `mix cmd --app cadence_web mix test`
- Single file: `mix test apps/cadence_web/test/cadence_web/live/user_session_live_test.exs`
- Single test: `mix test apps/cadence/test/cadence/accounts_test.exs:42`

**Compile check:** `mix compile --warnings-as-errors` (the project treats warnings as errors — any new warning fails the build).

**Formatting:** `mix format` on any Elixir file you touch before committing. The project has a `.formatter.exs` at the umbrella root, and formatting drift is easy to miss until CI catches it.

**Credo:** `mix credo --strict` — the project recently added credo and is burning down violations. Don't introduce new violations. Every task that adds code should end by running `mix credo --strict` on the touched files to verify no new warnings were introduced.

**Asset builds:** `mix assets.setup` (once, installs binaries) and `mix assets.build` (rebuild).

---

## Milestone A — Asset pipeline foundation

Goal: add the dep and config foundation for Tailwind v4, esbuild, heroicons, and Phoenix LiveView. No runtime wiring yet. After Milestone A, the tree compiles and all existing tests pass because nothing in the running code references the new deps.

### Task A1: Add Mix deps to `cadence_web`

**Files:**
- Modify: `apps/cadence_web/mix.exs`

- [ ] **Step 1: Read the current deps list**

Read `apps/cadence_web/mix.exs`. Note the existing `deps/0` returns a list with `bandit`, `cadence`, `jason`, `phoenix`, `phoenix_html`, `phoenix_live_view`, `swoosh`.

Wait — check whether `phoenix_live_view` is actually in the list. If it's already there, skip the `phoenix_live_view` add in Step 2.

- [ ] **Step 2: Add new deps**

Edit `apps/cadence_web/mix.exs`. Replace the `deps/0` function so it returns:

```elixir
defp deps do
  [
    {:bandit, "~> 1.5"},
    {:cadence, in_umbrella: true},
    {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
    {:heroicons,
     github: "tailwindlabs/heroicons",
     tag: "v2.2.0",
     sparse: "optimized",
     app: false,
     compile: false,
     depth: 1},
    {:jason, "~> 1.4"},
    {:phoenix, "~> 1.8.1"},
    {:phoenix_html, "~> 4.3"},
    {:phoenix_live_view, "~> 1.1"},
    {:swoosh, "~> 1.17"},
    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev}
  ]
end
```

- [ ] **Step 3: Fetch the new deps**

Run: `mix deps.get`
Expected: successful fetch of `esbuild`, `heroicons`, `tailwind` (and any transitive deps). `phoenix_live_view` may already be pulled as a transitive.

- [ ] **Step 4: Verify the umbrella still compiles**

Run: `mix compile --warnings-as-errors`
Expected: clean compile with no new warnings.

- [ ] **Step 5: Commit**

```bash
git add apps/cadence_web/mix.exs mix.lock
git commit -m "$(cat <<'EOF'
feat(cadence_web): add frontend pipeline deps

Add phoenix_live_view, tailwind, esbuild, and heroicons to cadence_web
so the forthcoming LiveView + Tailwind v4 asset pipeline has something
to hang off of. No runtime changes yet — deps are added but nothing
references them.

EOF
)"
```

### Task A2: Add Tailwind and esbuild config profiles

**Files:**
- Modify: `config/config.exs`

- [ ] **Step 1: Add config :tailwind and config :esbuild**

Edit `config/config.exs`. Append the following after the existing `config :cadence_web, CadenceWeb.Mailer, ...` line but before `import_config "#{config_env()}.exs"`:

```elixir
config :tailwind,
  version: "4.0.9",
  cadence_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/cadence_web", __DIR__)
  ]

config :esbuild,
  version: "0.21.5",
  cadence_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/cadence_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../apps/cadence_web/deps", __DIR__)}
  ]
```

- [ ] **Step 2: Verify the config compiles**

Run: `mix compile`
Expected: clean compile. (The config values are not validated until the tasks actually run, so this just checks syntax.)

- [ ] **Step 3: Commit**

```bash
git add config/config.exs
git commit -m "$(cat <<'EOF'
feat(cadence_web): configure tailwind and esbuild for cadence_web profile

Pin Tailwind 4.0.9 and esbuild 0.21.5, and define a cadence_web profile
for each task that reads assets from apps/cadence_web/assets and writes
to apps/cadence_web/priv/static/assets.

EOF
)"
```

### Task A3: Add dev watchers

**Files:**
- Modify: `config/dev.exs`

- [ ] **Step 1: Add watchers to Endpoint config**

Edit `config/dev.exs`. Replace the existing `config :cadence_web, CadenceWeb.Endpoint, ...` block with:

```elixir
config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4001],
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cadence_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]
```

- [ ] **Step 2: Verify the config compiles**

Run: `mix compile`
Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add config/dev.exs
git commit -m "$(cat <<'EOF'
feat(cadence_web): wire tailwind and esbuild watchers in dev

So edits to app.css and app.js trigger rebuilds during `mix phx.server`.

EOF
)"
```

### Task A4: Add asset mix aliases

**Files:**
- Modify: `apps/cadence_web/mix.exs`

- [ ] **Step 1: Add an `aliases/0` function and wire it into the project config**

Edit `apps/cadence_web/mix.exs`. Update `project/0` to include `aliases: aliases()`:

```elixir
def project do
  [
    app: :cadence_web,
    version: "0.1.0",
    build_path: "../../_build",
    config_path: "../../config/config.exs",
    deps_path: "../../deps",
    lockfile: "../../mix.lock",
    elixirc_paths: elixirc_paths(Mix.env()),
    elixir: "~> 1.15",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    aliases: aliases()
  ]
end
```

Then add a new `aliases/0` function below `deps/0`:

```elixir
defp aliases do
  [
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["tailwind cadence_web", "esbuild cadence_web"],
    "assets.deploy": [
      "tailwind cadence_web --minify",
      "esbuild cadence_web --minify",
      "phx.digest"
    ]
  ]
end
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: clean.

- [ ] **Step 3: Verify aliases are visible**

Run: `mix cmd --app cadence_web mix help assets.build`
Expected: shows the alias definition.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/mix.exs
git commit -m "$(cat <<'EOF'
feat(cadence_web): add assets.setup/build/deploy mix aliases

Bundle the tailwind and esbuild tasks under assets.* so the standard
Phoenix asset commands work from cadence_web.

EOF
)"
```

### Task A5: Milestone A verification commit boundary

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: all tests pass. (No runtime changes in Milestone A — existing tests should be unaffected.)

- [ ] **Step 2: Run credo strict**

Run: `mix credo --strict`
Expected: no new violations introduced by this milestone.

- [ ] **Step 3: Confirm the three Milestone A commits are in place**

Run: `git log --oneline -5`
Expected: top three commits are Tasks A1–A4 (four commits total).

---

## Milestone B — Asset sources, runtime wiring, compat shim

Goal: create the actual asset source files (`assets/css/app.css`, `assets/js/app.js`, `assets/vendor/heroicons.js`), wire LiveView into the Endpoint and root layout, add a CSS compat shim that preserves the existing class names so legacy pages keep rendering, and delete the tracked hand-rolled static CSS so the Tailwind build owns that output path. After Milestone B, `mix assets.build` produces `priv/static/assets/app.css` + `priv/static/assets/app.js`, all existing pages still render (via the compat shim), all tests still pass, and the codebase is ready for a LiveView page.

### Task B1: Update `.gitignore` to exclude built assets

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add the umbrella-aware ignore pattern**

Read `.gitignore`. Find the line `/priv/static/assets/` and replace the block:

```
# Ignore assets that are produced by build tools.
/priv/static/assets/
```

with:

```
# Ignore assets that are produced by build tools.
/priv/static/assets/
/apps/*/priv/static/assets/
```

- [ ] **Step 2: Remove the tracked static CSS from git**

Run: `git rm apps/cadence_web/priv/static/assets/app.css`
Expected: the file is removed from the index. It stays on disk temporarily so existing pages keep working until the Tailwind build replaces it.

- [ ] **Step 3: Verify the ignore pattern takes effect**

Run: `git status --short`
Expected: `apps/cadence_web/priv/static/assets/app.css` is staged for deletion; if a new version exists it should NOT appear as untracked.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: gitignore umbrella-app built static assets

Tailwind and esbuild will write to apps/cadence_web/priv/static/assets/
on every build; those outputs should not be tracked. Remove the tracked
hand-rolled app.css that preceded this so the Tailwind build can write
there cleanly once the asset sources land.

EOF
)"
```

### Task B2: Create `assets/js/app.js`

**Files:**
- Create: `apps/cadence_web/assets/js/app.js`

- [ ] **Step 1: Create the assets directory structure**

Run: `mkdir -p apps/cadence_web/assets/js apps/cadence_web/assets/css apps/cadence_web/assets/vendor`
Expected: directories exist.

- [ ] **Step 2: Write `app.js`**

Create `apps/cadence_web/assets/js/app.js` with:

```js
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()

window.liveSocket = liveSocket
```

- [ ] **Step 3: Commit**

```bash
git add apps/cadence_web/assets/js/app.js
git commit -m "$(cat <<'EOF'
feat(cadence_web): add minimal LiveView app.js boot

Imports phoenix_html, opens the LiveSocket with CSRF token, and
exposes it on window for dev-tools debugging. No hooks registered yet.

EOF
)"
```

### Task B3: Create `assets/vendor/heroicons.js`

**Files:**
- Create: `apps/cadence_web/assets/vendor/heroicons.js`

- [ ] **Step 1: Write the heroicons Tailwind plugin**

This is the standard Phoenix 1.8 heroicons plugin file. Create `apps/cadence_web/assets/vendor/heroicons.js` with:

```js
// Heroicons Tailwind plugin.
//
// Adds `hero-<icon-name>` utility classes (and -solid, -mini, -micro variants)
// that mask heroicon SVGs as CSS backgrounds. Reads the SVGs from the
// tailwindlabs/heroicons Mix dep installed at deps/heroicons/optimized.

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  const iconsDir = path.join(__dirname, "../../../../deps/heroicons/optimized")
  const values = {}
  const icons = [
    ["", "/24/outline"],
    ["-solid", "/24/solid"],
    ["-mini", "/20/solid"],
    ["-micro", "/16/solid"]
  ]

  icons.forEach(([suffix, dir]) => {
    fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
      const name = path.basename(file, ".svg") + suffix
      values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
    })
  })

  matchComponents(
    {
      hero: ({name, fullPath}) => {
        const content = fs
          .readFileSync(fullPath)
          .toString()
          .replace(/\r?\n|\r/g, "")
        const size = theme("spacing.6")
        return {
          [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
          "-webkit-mask": `var(--hero-${name})`,
          mask: `var(--hero-${name})`,
          "mask-repeat": "no-repeat",
          "background-color": "currentColor",
          "vertical-align": "middle",
          display: "inline-block",
          width: size,
          height: size
        }
      }
    },
    {values}
  )
})
```

- [ ] **Step 2: Commit**

```bash
git add apps/cadence_web/assets/vendor/heroicons.js
git commit -m "$(cat <<'EOF'
feat(cadence_web): add heroicons tailwind plugin

Standard Phoenix 1.8 heroicons plugin — reads SVGs from the
tailwindlabs/heroicons Mix dep and exposes hero-* utility classes.

EOF
)"
```

### Task B4: Create `assets/css/app.css` with Tailwind v4 imports and `@theme` block

**Files:**
- Create: `apps/cadence_web/assets/css/app.css`

- [ ] **Step 1: Write the header, imports, and theme block**

Create `apps/cadence_web/assets/css/app.css` with:

```css
@import "tailwindcss" source(none);
@source "../../lib/cadence_web";
@source "../js";
@plugin "../vendor/heroicons";

/* Cadence "Tokyo Night / Vaporwave / HUD" theme. Color values are ported
   from the hand-rolled palette in the pre-Tailwind priv/static/assets/app.css
   (near-black blue bases, cyan primary, purple secondary, hot-pink accent).
   Sharp corners are intentional for the HUD aesthetic. */
@theme {
  --color-base-100: #09111b;
  --color-base-200: #0f1b2a;
  --color-base-300: #1a2638;
  --color-base-content: #edf4ff;
  --color-muted: #9cafc5;
  --color-primary: #86d6ff;
  --color-primary-content: #041019;
  --color-secondary: #bb9af7;
  --color-secondary-content: #15101f;
  --color-accent: #f5b66f;
  --color-accent-content: #1c1208;
  --color-info: #7aa2f7;
  --color-info-content: #0a1020;
  --color-success: #93f2c8;
  --color-success-content: #062018;
  --color-warning: #f5b66f;
  --color-warning-content: #1c1208;
  --color-error: #ff8e85;
  --color-error-content: #200606;

  --color-panel: rgba(10, 18, 29, 0.88);
  --color-panel-strong: rgba(15, 27, 42, 0.96);
  --color-line: rgba(138, 173, 212, 0.18);
  --color-line-strong: rgba(138, 173, 212, 0.32);

  --radius-box: 1rem;
  --radius-field: 1rem;
  --radius-selector: 999px;

  --font-sans: "IBM Plex Sans", "Avenir Next", "Segoe UI", sans-serif;
  --font-mono: "IBM Plex Mono", "SFMono-Regular", Consolas, monospace;
}

/* Page-level styles that are cleaner as raw CSS than utility classes. */
:root {
  color-scheme: dark;
  font-family: var(--font-sans);
}

html,
body {
  margin: 0;
  min-height: 100%;
  background:
    radial-gradient(circle at top left, rgba(134, 214, 255, 0.18), transparent 28rem),
    radial-gradient(circle at bottom right, rgba(245, 182, 111, 0.16), transparent 26rem),
    linear-gradient(180deg, #09111b 0%, #04080f 100%);
  color: var(--color-base-content);
}

body {
  min-height: 100vh;
}

a {
  color: inherit;
  text-decoration: none;
}

code {
  font-family: var(--font-mono);
  color: var(--color-primary);
}
```

- [ ] **Step 2: Install Tailwind and esbuild binaries**

Run: `mix assets.setup`
Expected: downloads the Tailwind 4.0.9 and esbuild 0.21.5 binaries into `_build`. First run is slow; subsequent runs are instant.

- [ ] **Step 3: Build assets to verify the Tailwind v4 entry is valid**

Run: `mix assets.build`
Expected: produces `apps/cadence_web/priv/static/assets/app.css` (overwriting the old file) and `apps/cadence_web/priv/static/assets/app.js`. No errors from Tailwind about missing imports, malformed `@theme`, or unresolved `@source` / `@plugin` paths.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/assets/css/app.css
git commit -m "$(cat <<'EOF'
feat(cadence_web): add tailwind v4 entry with cadence theme

Tokyo Night / Vaporwave HUD palette ported from the pre-Tailwind
hand-rolled app.css, expressed as a Tailwind v4 @theme block so utilities
like bg-base-200, text-primary, border-line can resolve. No components
yet; the compat shim arrives in the next commit.

EOF
)"
```

### Task B5: Add the legacy CSS compat shim

**Files:**
- Modify: `apps/cadence_web/assets/css/app.css`

The compat shim preserves the existing bespoke class names (`panel--hero`, `status-card`, `app-root`, etc.) so the currently-rendering `/setup`, `/operator`, `/invitations/:token`, and the existing `layouts/app.html.heex` continue to look right while we port pages slice by slice. Each rule below translates the corresponding rule from the original hand-rolled `priv/static/assets/app.css`.

- [ ] **Step 1: Append the `@layer legacy-compat` block**

Edit `apps/cadence_web/assets/css/app.css`. Append the following block at the end of the file:

```css
@layer legacy-compat {
  /* App shell — used by layouts/app.html.heex. */
  .app-root {
    position: relative;
    min-height: 100vh;
    overflow: hidden;
  }

  .app-root__mesh,
  .app-root__grid {
    position: absolute;
    inset: 0;
    pointer-events: none;
  }

  .app-root__mesh {
    background:
      linear-gradient(125deg, rgba(134, 214, 255, 0.06), transparent 42%),
      linear-gradient(305deg, rgba(245, 182, 111, 0.08), transparent 38%);
  }

  .app-root__grid {
    background-image:
      linear-gradient(rgba(134, 214, 255, 0.05) 1px, transparent 1px),
      linear-gradient(90deg, rgba(134, 214, 255, 0.05) 1px, transparent 1px);
    background-size: 4rem 4rem;
    mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.6), transparent 92%);
  }

  .app-shell {
    position: relative;
    z-index: 1;
    width: min(72rem, calc(100vw - 2.5rem));
    margin: 0 auto;
    padding: 2rem 0 3rem;
  }

  .app-header {
    display: flex;
    justify-content: space-between;
    gap: 1.5rem;
    align-items: flex-start;
    margin-bottom: 2rem;
  }

  .app-header__brand {
    display: inline-block;
    font-family: var(--font-mono);
    font-size: 0.88rem;
    letter-spacing: 0.28em;
    text-transform: uppercase;
    color: var(--color-primary);
  }

  .app-header__subhead {
    margin: 0.55rem 0 0;
    color: var(--color-muted);
    max-width: 28rem;
    line-height: 1.5;
  }

  .app-main {
    position: relative;
  }

  /* Scope summary — used by layouts/app.html.heex for authenticated users. */
  .scope-summary {
    min-width: 15rem;
    padding: 0.95rem 1rem;
    border: 1px solid var(--color-line);
    border-radius: 1rem;
    background: rgba(9, 17, 27, 0.68);
    backdrop-filter: blur(18px);
    text-align: right;
  }

  .scope-summary__label {
    display: block;
    margin-bottom: 0.4rem;
    color: var(--color-accent);
    font-size: 0.72rem;
    letter-spacing: 0.18em;
    text-transform: uppercase;
  }

  .scope-summary strong,
  .scope-summary span {
    display: block;
  }

  .scope-summary span {
    margin-top: 0.2rem;
    color: var(--color-muted);
    font-size: 0.92rem;
  }

  /* Panels — used by /setup, /operator, /invitations. */
  .panel {
    position: relative;
    overflow: hidden;
    border: 1px solid var(--color-line);
    border-radius: 1.5rem;
    padding: 2rem;
    background: linear-gradient(180deg, var(--color-panel-strong) 0%, var(--color-panel) 100%);
    box-shadow: 0 28px 90px rgba(0, 0, 0, 0.42);
  }

  .panel::before {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    border: 1px solid rgba(255, 255, 255, 0.04);
    pointer-events: none;
  }

  .panel--hero {
    display: grid;
    gap: 1.5rem;
  }

  .panel__error {
    margin: 0;
    padding: 0.95rem 1rem;
    border: 1px solid rgba(255, 142, 133, 0.26);
    border-radius: 1rem;
    background: rgba(77, 18, 22, 0.58);
    color: #ffd0cc;
  }

  .eyebrow {
    font-family: var(--font-mono);
    font-size: 0.78rem;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--color-accent);
  }

  .hero-title {
    margin: 0;
    max-width: 42rem;
    font-size: clamp(2.2rem, 4vw, 4rem);
    line-height: 0.94;
    letter-spacing: -0.04em;
  }

  .hero-copy {
    margin: 0;
    max-width: 42rem;
    color: var(--color-muted);
    font-size: 1.05rem;
    line-height: 1.7;
  }

  .sign-in-form,
  .summary-grid {
    display: grid;
    gap: 1rem;
  }

  .summary-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .sign-in-form__actions {
    display: flex;
    gap: 1rem;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
  }

  .sign-in-form__note,
  .status-card__body {
    margin: 0;
    color: var(--color-muted);
    line-height: 1.6;
  }

  /* Form fields — used by CoreComponents.input. */
  .field {
    display: grid;
    gap: 0.55rem;
  }

  .field__label {
    font-family: var(--font-mono);
    font-size: 0.76rem;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted);
  }

  .field__input {
    width: 100%;
    border: 1px solid var(--color-line);
    border-radius: 1rem;
    padding: 0.95rem 1rem;
    background: rgba(5, 11, 18, 0.86);
    color: var(--color-base-content);
    font: inherit;
    transition:
      border-color 160ms ease,
      box-shadow 160ms ease,
      transform 160ms ease;
  }

  .field__input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 0.2rem rgba(134, 214, 255, 0.12);
    transform: translateY(-1px);
  }

  .field__input::placeholder {
    color: rgba(156, 175, 197, 0.56);
  }

  /* Buttons. */
  .button {
    border: 0;
    border-radius: 999px;
    padding: 0.85rem 1.25rem;
    font: inherit;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    cursor: pointer;
    transition:
      transform 160ms ease,
      box-shadow 160ms ease,
      opacity 160ms ease;
  }

  .button:hover {
    transform: translateY(-1px);
  }

  .button--primary {
    background: linear-gradient(135deg, var(--color-primary) 0%, #c9ecff 100%);
    color: var(--color-primary-content);
    box-shadow: 0 14px 34px rgba(134, 214, 255, 0.22);
  }

  .button--secondary {
    background: rgba(9, 17, 27, 0.72);
    color: var(--color-base-content);
    border: 1px solid var(--color-line-strong);
  }

  /* Status cards — used by /setup. */
  .status-card {
    padding: 1.15rem;
    border: 1px solid var(--color-line);
    border-radius: 1.2rem;
    background: rgba(5, 11, 18, 0.6);
  }

  .status-card--disabled {
    border-style: dashed;
  }

  .status-card__label {
    margin: 0 0 0.5rem;
    color: var(--color-accent);
    font-family: var(--font-mono);
    font-size: 0.74rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }

  .status-card__title {
    margin: 0 0 0.35rem;
    font-size: 1.05rem;
    line-height: 1.35;
  }

  /* Flash stack — used by layouts/app.html.heex. */
  .flash-stack {
    position: fixed;
    top: 1.25rem;
    right: 1.25rem;
    z-index: 3;
    display: grid;
    gap: 0.75rem;
  }

  .flash {
    margin: 0;
    min-width: 16rem;
    max-width: min(24rem, calc(100vw - 2rem));
    padding: 0.9rem 1rem;
    border: 1px solid var(--color-line);
    border-radius: 1rem;
    background: rgba(6, 12, 19, 0.92);
    box-shadow: 0 28px 90px rgba(0, 0, 0, 0.42);
  }

  .flash--info {
    border-color: rgba(147, 242, 200, 0.24);
  }

  .flash--error {
    border-color: rgba(255, 142, 133, 0.32);
  }

  @media (max-width: 840px) {
    .app-shell {
      width: min(100vw - 1.5rem, 72rem);
      padding-top: 1.5rem;
    }

    .app-header {
      flex-direction: column;
    }

    .scope-summary {
      width: 100%;
      text-align: left;
    }

    .summary-grid {
      grid-template-columns: 1fr;
    }

    .panel {
      padding: 1.35rem;
      border-radius: 1.2rem;
    }

    .flash-stack {
      left: 0.75rem;
      right: 0.75rem;
      top: auto;
      bottom: 0.75rem;
    }

    .flash {
      min-width: 0;
    }
  }
}
```

- [ ] **Step 2: Rebuild assets**

Run: `mix assets.build`
Expected: successfully rebuilds `priv/static/assets/app.css` with the compat shim baked in.

- [ ] **Step 3: Commit**

```bash
git add apps/cadence_web/assets/css/app.css
git commit -m "$(cat <<'EOF'
feat(cadence_web): add legacy compat shim for pre-Tailwind class names

Preserves the hand-rolled class names (panel--hero, status-card,
app-root, field__input, flash, etc.) as rules inside a @layer
legacy-compat block so /setup, /operator, /invitations, and the current
layouts/app.html.heex template keep rendering while subsequent slices
port each page to the primitive component set. The shim is intentionally
temporary — it shrinks as each consuming page is ported.

EOF
)"
```

### Task B6: Wire LiveView socket into `CadenceWeb.Endpoint`

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/endpoint.ex`

- [ ] **Step 1: Extract session options and add the LiveView socket**

Edit `apps/cadence_web/lib/cadence_web/endpoint.ex`. Replace the entire module body with:

```elixir
defmodule CadenceWeb.Endpoint do
  use CadenceWeb, :endpoint

  @session_options [
    store: :cookie,
    key: "_cadence_web_key",
    signing_salt: "browser-auth",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Static,
    at: "/",
    from: :cadence_web,
    gzip: false,
    only: CadenceWeb.static_paths()

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.Session, @session_options
  plug Plug.MethodOverride
  plug Plug.Head
  plug CadenceWeb.Router
end
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: clean. The `socket/3` macro comes from `Phoenix.Endpoint` via the `use CadenceWeb, :endpoint` expansion.

- [ ] **Step 3: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/endpoint.ex
git commit -m "$(cat <<'EOF'
feat(cadence_web): add LiveView websocket to endpoint

Exposes /live with the same session options used by Plug.Session so
LiveViews see the same browser session as controllers.

EOF
)"
```

### Task B7: Add `live_view/0` helper and `CadenceWeb.UI` import to `CadenceWeb`

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web.ex`
- Create (stub): `apps/cadence_web/lib/cadence_web/components/ui.ex`

- [ ] **Step 1: Create an empty `CadenceWeb.UI` module so the import resolves**

Create `apps/cadence_web/lib/cadence_web/components/ui.ex` with:

```elixir
defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component
end
```

- [ ] **Step 2: Add `live_view/0` helper and `CadenceWeb.UI` import**

Edit `apps/cadence_web/lib/cadence_web.ex`. Replace the module with:

```elixir
defmodule CadenceWeb do
  @moduledoc false

  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: [html: CadenceWeb.Layouts]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {CadenceWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def endpoint do
    quote do
      use Phoenix.Endpoint, otp_app: :cadence_web
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import CadenceWeb.CoreComponents
      import CadenceWeb.UI

      alias CadenceWeb.Layouts

      unquote(verified_routes())
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: CadenceWeb.Endpoint,
        router: CadenceWeb.Router,
        statics: CadenceWeb.static_paths()
    end
  end
end
```

- [ ] **Step 3: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: clean. All existing controllers and templates should still compile; the new `import CadenceWeb.UI` resolves to the empty `Phoenix.Component` module and contributes nothing yet.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/lib/cadence_web.ex apps/cadence_web/lib/cadence_web/components/ui.ex
git commit -m "$(cat <<'EOF'
feat(cadence_web): add live_view helper and empty CadenceWeb.UI module

Adds the standard Phoenix 1.8 live_view/0 helper with the existing
Layouts.app as the default live layout, imports Phoenix.LiveView.Router
in the router helper, and stubs CadenceWeb.UI as an empty Phoenix.Component
module ready to receive primitives. Imports CadenceWeb.UI alongside
CadenceWeb.CoreComponents in html_helpers so pages can use either.

EOF
)"
```

### Task B8: Add the app.js script tag to the root layout

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/root.html.heex`

- [ ] **Step 1: Add the script tag**

Edit `apps/cadence_web/lib/cadence_web/components/layouts/root.html.heex`. Replace the entire file with:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <title>Cadence</title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
    </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

- [ ] **Step 2: Verify compile**

Run: `mix compile --warnings-as-errors`
Expected: clean. The `~p"/assets/app.js"` verified route resolves because the file now exists at the expected static path after `mix assets.build`.

- [ ] **Step 3: Run the test suite**

Run: `mix test`
Expected: all tests pass. Pages still render, compat shim keeps `/setup`, `/operator`, `/invitations/:token`, and the existing layout looking right. The new script tag is included but no LiveView pages exist yet, so it has nothing to connect to — that's fine.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/root.html.heex
git commit -m "$(cat <<'EOF'
feat(cadence_web): load /assets/app.js from root layout

Enables LiveView's WebSocket-based client on every page. Controllers
that don't render LiveViews are unaffected; the script is a no-op
until a LiveView route is reached.

EOF
)"
```

### Task B9: Milestone B verification

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: all tests pass. All legacy pages render correctly via the compat shim.

- [ ] **Step 2: Run credo strict on touched files**

Run: `mix credo --strict apps/cadence_web/lib`
Expected: no new violations.

- [ ] **Step 3: Confirm Milestone B commit chain**

Run: `git log --oneline -12`
Expected: Tasks B1–B8 are the top eight commits above Tasks A1–A4.

---

## Milestone C — `sign_in/2`, UI primitives, LiveView, controller refactor, tests

Goal: add `Cadence.Accounts.sign_in/2` with the credential-kind dispatch, add the UI primitives the sign-in LiveView needs, replace the controller-rendered `/sign-in` with `CadenceWeb.UserSessionLive`, collapse `UserSessionController.create/2`, and update tests. After Milestone C, `/sign-in` is a single-form LiveView that dispatches to the right credential kind invisibly and all tests pass.

### Task C1: Write `Accounts.sign_in/2` tests (red)

**Files:**
- Create: `apps/cadence/test/cadence/accounts_test.exs`

- [ ] **Step 1: Create the test file with the full dispatch matrix**

Create `apps/cadence/test/cadence/accounts_test.exs` with:

```elixir
defmodule Cadence.AccountsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts
  alias Cadence.Accounts.{Password, User}
  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.{UserLocalCredentialRow, UserRow}
  alias Cadence.Repo

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  describe "sign_in/2" do
    setup do
      previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])
      on_exit(fn ->
        Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
      end)

      :ok
    end

    test "durable user with only a password credential can sign in" do
      password = "durable-password-123"
      persist_durable_user!(email: "ops@example.com", password: password)

      assert {:ok, session} = Accounts.sign_in("ops@example.com", password)
      assert session.temporary_setup_access? == false
      assert is_binary(session.session_token)
    end

    test "durable user with wrong password fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "correct")

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "wrong")
    end

    test "unconfirmed durable user fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "pw-123", confirmed_at: nil)

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "inactive durable user fails with :invalid_credentials" do
      persist_durable_user!(
        email: "ops@example.com",
        password: "pw-123",
        lifecycle_state: :disabled
      )

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "bootstrap admin with enabled config and pending setup can sign in" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      assert {:ok, session} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)

      assert session.temporary_setup_access? == true
      assert is_binary(session.session_token)
    end

    test "bootstrap admin with wrong password fails with :invalid_credentials" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, "wrong")
    end

    test "bootstrap admin with bootstrap_admin_enabled? false fails with :invalid_credentials" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      Application.put_env(:cadence, :bootstrap_admin, enabled: false)

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)
    end

    test "bootstrap admin after setup complete fails with :invalid_credentials" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()
      persist_completed_setup!()

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)
    end

    test "user with both credentials dispatches to durable path when durable password is correct" do
      enable_bootstrap_admin!()
      assert {:ok, _bootstrap_user} = Cadence.ensure_bootstrap_admin()

      # Attach a password credential to the bootstrap admin user so it has both.
      durable_password = "durable-password-123"
      attach_password_credential!(@bootstrap_admin_email, durable_password)

      assert {:ok, session} = Accounts.sign_in(@bootstrap_admin_email, durable_password)
      assert session.temporary_setup_access? == false
    end

    test "user with both credentials does not fall back to bootstrap when durable password is wrong" do
      enable_bootstrap_admin!()
      assert {:ok, _bootstrap_user} = Cadence.ensure_bootstrap_admin()

      durable_password = "durable-password-123"
      attach_password_credential!(@bootstrap_admin_email, durable_password)

      # Submitting the bootstrap password, which would succeed against the bootstrap
      # credential, must NOT succeed via sign_in/2 because durable is present and wins.
      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)
    end

    test "email not found fails with :invalid_credentials" do
      assert {:error, :invalid_credentials} =
               Accounts.sign_in("nobody@example.com", "anything")
    end
  end

  ## Fixtures

  defp enable_bootstrap_admin! do
    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )
  end

  defp persist_durable_user!(opts) when is_list(opts) do
    password = Keyword.fetch!(opts, :password)
    email = Keyword.fetch!(opts, :email)
    confirmed_at = Keyword.get(opts, :confirmed_at, DateTime.utc_now())
    lifecycle_state = Keyword.get(opts, :lifecycle_state, :active)

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: Keyword.get(opts, :display_name, "Durable User"),
        capabilities: Keyword.get(opts, :capabilities, []),
        confirmed_at: confirmed_at,
        lifecycle_state: lifecycle_state,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  defp attach_password_credential!(email, password) do
    normalized_email = User.normalize_email(email)
    %UserRow{} = user_row = Repo.get_by!(UserRow, email: normalized_email)

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user_row.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    # Ensure the bootstrap admin user is confirmed for the durable path.
    Repo.update!(
      UserRow.update_changeset(user_row, %{confirmed_at: DateTime.utc_now()})
    )
  end

  defp persist_completed_setup! do
    organization =
      Organization.new(%{
        organization_id: "org-cadence",
        slug: "cadence-inc",
        display_name: "Cadence Inc."
      })

    assert {:ok, persisted_organization} = Cadence.persist_organization(organization)

    assert {:ok, _workflow} =
             Cadence.complete_initial_setup(persisted_organization.organization_id)
  end
end
```

- [ ] **Step 2: Run the test file to verify all tests fail with the expected "function not exported" error**

Run: `mix cmd --app cadence mix test test/cadence/accounts_test.exs`
Expected: all 11 tests fail with `UndefinedFunctionError` on `Cadence.Accounts.sign_in/2`.

- [ ] **Step 3: Don't commit yet** — this is red-green-refactor; the green state is the commit boundary.

### Task C2: Implement `Accounts.sign_in/2` (green)

**Files:**
- Modify: `apps/cadence/lib/cadence/accounts.ex`

- [ ] **Step 1: Add the public `sign_in/2` function and its private helpers**

Edit `apps/cadence/lib/cadence/accounts.ex`. Locate the existing `login_user/2` function (around line 129) and insert `sign_in/2` directly above it:

```elixir
  @spec sign_in(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    with {:ok, user} <- fetch_active_user_by_email(email),
         {:ok, credential_kind} <- resolve_credential_kind(user) do
      case credential_kind do
        :durable -> login_user(email, password)
        :bootstrap_admin -> login_bootstrap_admin(email, password)
      end
    end
  end
```

Then, at the end of the module's private helpers (near `active_password_credential?/1` if present, or just before `defp upsert_user/2`), add the supporting helpers:

```elixir
  defp fetch_active_user_by_email(email) when is_binary(email) do
    normalized_email = User.normalize_email(email)

    case Repo.get_by(UserRow,
           email: normalized_email,
           lifecycle_state: Atom.to_string(:active)
         ) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :invalid_credentials}
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

  defp active_credential?(user_id, provider_key)
       when is_binary(user_id) and is_binary(provider_key) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: provider_key,
      lifecycle_state: Atom.to_string(:active)
    ) != nil
  end

  defp setup_pending? do
    case Cadence.Setup.fetch_initial_workflow() do
      {:ok, workflow} -> Cadence.Setup.active?(workflow)
      {:error, _reason} -> true
    end
  end
```

**Note on the existing `active_password_credential?/1`:** search the file for `active_password_credential?`. If that private helper already exists, you can replace it with `active_credential?/2` — all call sites pass `@password_provider_key` as the second argument. If it does not exist, just add `active_credential?/2` as shown above. Either way there must be exactly one helper that checks "is there an active credential of this kind for this user," not two.

- [ ] **Step 2: Run the accounts tests**

Run: `mix cmd --app cadence mix test test/cadence/accounts_test.exs`
Expected: all 11 tests pass.

- [ ] **Step 3: Run the full cadence suite to confirm no regressions**

Run: `mix cmd --app cadence mix test`
Expected: all tests pass.

- [ ] **Step 4: Run credo strict on accounts.ex**

Run: `mix credo --strict apps/cadence/lib/cadence/accounts.ex`
Expected: no new violations.

- [ ] **Step 5: Commit**

```bash
git add apps/cadence/lib/cadence/accounts.ex apps/cadence/test/cadence/accounts_test.exs
git commit -m "$(cat <<'EOF'
feat(accounts): add sign_in/2 with credential-kind dispatch

Looks up the user's active credentials and dispatches to either
login_user/2 (durable) or login_bootstrap_admin/2 (bootstrap) based on
what's present. Durable always wins when present; bootstrap is usable
only during first-run setup with bootstrap_admin_enabled. Tightens the
bootstrap gate vs. login_bootstrap_admin/2 alone, which only checks the
config flag. Existing login_user/2 and login_bootstrap_admin/2 are
unchanged and still used by the API and simulator callers.

EOF
)"
```

### Task C3: Add `Auth.sign_in/2` and `Cadence.sign_in/2` delegators

**Files:**
- Modify: `apps/cadence/lib/cadence/auth.ex`
- Modify: `apps/cadence/lib/cadence.ex`

- [ ] **Step 1: Add `Auth.sign_in/2`**

Edit `apps/cadence/lib/cadence/auth.ex`. Locate the existing `login_user/2` function (around line 128) and insert above it:

```elixir
  @spec sign_in(binary(), binary()) :: {:ok, Accounts.issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    Accounts.sign_in(email, password)
  end
```

- [ ] **Step 2: Add `Cadence.sign_in/2`**

Edit `apps/cadence/lib/cadence.ex`. Locate the existing `login_user/2` function (around line 133) and insert above it:

```elixir
  @spec sign_in(binary(), binary()) ::
          {:ok, Accounts.issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    Auth.sign_in(email, password)
  end
```

If `Accounts` is not already aliased in `cadence.ex`, add `alias Cadence.Accounts` (or spell the type out as `Cadence.Accounts.issued_user_session()`).

- [ ] **Step 3: Compile and run tests**

Run: `mix compile --warnings-as-errors`
Run: `mix cmd --app cadence mix test`
Expected: clean compile, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence/lib/cadence/auth.ex apps/cadence/lib/cadence.ex
git commit -m "$(cat <<'EOF'
feat(cadence): expose sign_in/2 on Auth and Cadence facades

Thin delegators that let cadence_web call Cadence.sign_in/2 without
reaching into Accounts directly. Matches the existing delegation chain
for login_user/2 and login_bootstrap_admin/2.

EOF
)"
```

### Task C4: Implement `CadenceWeb.UI` primitives

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/ui.ex`

The seven primitives are tightly coupled — they're a design system, not separate features — so they land in one task. Each uses Tailwind v4 utilities against the `@theme` tokens defined in Task B4.

- [ ] **Step 1: Write the primitives**

Replace `apps/cadence_web/lib/cadence_web/components/ui.ex` with:

```elixir
defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  @doc """
  Hero panel container.

  A dark glass-lit panel with a subtle border and inner hairline.
  Use `variant={:hero}` for the oversized first-screen panel and
  `variant={:compact}` for tighter secondary panels.
  """
  attr :variant, :atom, values: [:hero, :compact], default: :hero
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={[
      "relative overflow-hidden border border-line rounded-[1.5rem] bg-gradient-to-b from-panel-strong to-panel shadow-[0_28px_90px_rgba(0,0,0,0.42)] before:absolute before:inset-0 before:rounded-inherit before:border before:border-white/5 before:pointer-events-none",
      panel_variant_class(@variant),
      @class
    ]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp panel_variant_class(:hero), do: "p-8 grid gap-6"
  defp panel_variant_class(:compact), do: "p-5"

  @doc """
  Eyebrow — small uppercase mono label that sits above a hero title.
  """
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <p class="font-mono text-[0.78rem] tracking-[0.18em] uppercase text-accent m-0">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Oversized hero headline.
  """
  slot :inner_block, required: true

  def hero_title(assigns) do
    ~H"""
    <h1 class="m-0 max-w-[42rem] text-[clamp(2.2rem,4vw,4rem)] leading-[0.94] tracking-[-0.04em] text-base-content">
      {render_slot(@inner_block)}
    </h1>
    """
  end

  @doc """
  Supporting hero prose paragraph.
  """
  slot :inner_block, required: true

  def hero_copy(assigns) do
    ~H"""
    <p class="m-0 max-w-[42rem] text-muted text-[1.05rem] leading-[1.7]">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Labeled text field wrapping a Phoenix form field.
  """
  attr :field, FormField, required: true
  attr :type, :string, default: "text", values: ~w(text email password)
  attr :label, :string, required: true
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :autocomplete, :string, default: nil
  attr :autofocus, :boolean, default: false

  def text_field(assigns) do
    assigns =
      assign(assigns, :value, if(assigns.type == "password", do: nil, else: assigns.field.value))

    ~H"""
    <div class="grid gap-[0.55rem]">
      <label
        for={@field.id}
        class="font-mono text-[0.76rem] tracking-[0.16em] uppercase text-muted"
      >
        {@label}
      </label>
      <input
        id={@field.id}
        name={@field.name}
        type={@type}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        autocomplete={@autocomplete}
        autofocus={@autofocus}
        class="w-full border border-line rounded-[1rem] px-4 py-[0.95rem] bg-[rgba(5,11,18,0.86)] text-base-content font-sans transition-[border-color,box-shadow,transform] duration-150 focus:outline-none focus:border-primary focus:shadow-[0_0_0_0.2rem_rgba(134,214,255,0.12)] focus:-translate-y-px placeholder:text-[rgba(156,175,197,0.56)]"
      />
    </div>
    """
  end

  @doc """
  Primary/secondary/ghost button.
  """
  attr :variant, :atom, values: [:primary, :secondary, :ghost], default: :primary
  attr :kind, :atom, values: [:button, :submit], default: :submit
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={Atom.to_string(@kind)}
      class={[
        "border-0 rounded-full px-5 py-[0.85rem] font-mono text-[0.8rem] tracking-[0.12em] uppercase cursor-pointer transition-[transform,box-shadow,opacity] duration-150 hover:-translate-y-px",
        button_variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_variant_class(:primary) do
    "bg-gradient-to-br from-primary to-[#c9ecff] text-primary-content shadow-[0_14px_34px_rgba(134,214,255,0.22)]"
  end

  defp button_variant_class(:secondary) do
    "bg-[rgba(9,17,27,0.72)] text-base-content border border-line-strong"
  end

  defp button_variant_class(:ghost) do
    "bg-transparent text-base-content border border-line"
  end

  @doc """
  Inline form-level error panel. Renders nothing if `message` is nil or blank.
  """
  attr :message, :string, default: nil

  def form_error(assigns) do
    ~H"""
    <p
      :if={@message not in [nil, ""]}
      class="m-0 px-4 py-[0.95rem] border border-[rgba(255,142,133,0.26)] rounded-[1rem] bg-[rgba(77,18,22,0.58)] text-[#ffd0cc]"
    >
      {@message}
    </p>
    """
  end
end
```

**Note on the Tailwind theme extension:** the `panel`, `line`, `line-strong`, `panel-strong`, `muted` tokens aren't part of Tailwind's default color palette — they're defined in the `@theme` block in Task B4 as `--color-panel`, `--color-line`, etc. Tailwind v4 auto-generates utilities from those tokens, so `border-line`, `from-panel-strong`, `text-muted` all resolve.

- [ ] **Step 2: Rebuild assets so Tailwind picks up the new class references**

Run: `mix assets.build`
Expected: successful build, no "unknown utility class" errors. If Tailwind complains about an unknown utility like `text-muted` or `border-line`, cross-reference the `@theme` block in `app.css` — every token used as a Tailwind utility must be declared there.

- [ ] **Step 3: Compile and run tests**

Run: `mix compile --warnings-as-errors`
Run: `mix test`
Expected: clean compile, all tests pass. The new primitives aren't referenced from any page yet, so nothing consumes them.

- [ ] **Step 4: Run credo strict**

Run: `mix credo --strict apps/cadence_web/lib/cadence_web/components/ui.ex`
Expected: no violations.

- [ ] **Step 5: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/ui.ex
git commit -m "$(cat <<'EOF'
feat(cadence_web): add CadenceWeb.UI primitive component set

Seven HEEx primitives using Tailwind v4 utilities against the Cadence
theme tokens: panel, eyebrow, hero_title, hero_copy, text_field, button,
form_error. Driven by what /sign-in needs — the set is intentionally
small and will grow only as concrete pages demand more.

EOF
)"
```

### Task C5: Write `UserSessionLive` tests (red)

**Files:**
- Create: `apps/cadence_web/test/cadence_web/live/user_session_live_test.exs`

- [ ] **Step 1: Write the LiveView test file**

Create `apps/cadence_web/test/cadence_web/live/user_session_live_test.exs` with:

```elixir
defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "GET /sign-in" do
    test "renders the single sign-in form with hero header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Cadence Access"
      assert html =~ "Sign In"
      assert html =~ "email"
      assert html =~ "password"
      # One <form> tag, not two.
      assert html |> String.split("<form") |> length() == 2
    end

    test "renders no setup-access-specific UI", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      refute html =~ "setup-access-sign-in-form"
      refute html =~ "Temporary Access"
      refute html =~ "Setup Password"
    end

    test "form posts to the controller action at ~p\"/sign-in\"", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ ~s(action="/sign-in")
    end

    test "phx-change updates the form assigns without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      updated =
        view
        |> form("#sign-in-form", user: %{email: "ops@example.com", password: "in-progress"})
        |> render_change()

      assert updated =~ ~s(value="ops@example.com")
    end
  end
end

# Flash rendering on redirect from the controller is covered by
# browser_shell_test.exs — the POST → redirect → LiveView mount path
# exercises it end-to-end.
```

- [ ] **Step 2: Run the test file to verify it fails**

Run: `mix test apps/cadence_web/test/cadence_web/live/user_session_live_test.exs`
Expected: all 4 tests fail — either with a routing error (no `live "/sign-in"` route) or a module-not-found error for `CadenceWeb.UserSessionLive`.

- [ ] **Step 3: Don't commit yet** — green state comes in Task C6.

### Task C6: Implement `CadenceWeb.UserSessionLive`

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/user_session_live.ex`

- [ ] **Step 1: Create the LiveView**

Create `apps/cadence_web/lib/cadence_web/live/user_session_live.ex` with:

```elixir
defmodule CadenceWeb.UserSessionLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"email" => "", "password" => ""}, as: :user))
     |> assign(:page_title, "Sign in")}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.panel variant={:hero}>
      <.eyebrow>Cadence Access</.eyebrow>
      <.hero_title>Sign in to Cadence.</.hero_title>
      <.hero_copy>
        Enter the credentials for your Cadence operator account. During first-run setup,
        the same form accepts the temporary setup-access credentials configured for this
        deployment.
      </.hero_copy>

      <.form_error message={Phoenix.Flash.get(@flash, :error)} />

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/sign-in"}
        phx-change="validate"
        phx-trigger-action={false}
        class="grid gap-4"
      >
        <.text_field
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="operator@example.com"
          required
          autocomplete="email"
          autofocus
        />
        <.text_field
          field={@form[:password]}
          type="password"
          label="Password"
          placeholder="Enter your password"
          required
          autocomplete="current-password"
        />

        <div class="flex items-center justify-between gap-4 flex-wrap">
          <.button variant={:primary} kind={:submit}>Sign In</.button>
          <p class="m-0 text-muted leading-[1.6] text-sm">
            Invitation acceptance creates the durable account. Public self-signup remains closed.
          </p>
        </div>
      </.form>
    </.panel>
    """
  end
end
```

- [ ] **Step 2: Swap `fetch_flash` for `fetch_live_flash` and add the live route**

Edit `apps/cadence_web/lib/cadence_web/router.ex`. Two changes in this file.

First, in the `:browser` pipeline (around lines 4–12), change:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_flash
  plug :put_root_layout, html: {CadenceWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug CadenceWeb.Plugs.FetchBrowserCurrentScope
end
```

to:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {CadenceWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug CadenceWeb.Plugs.FetchBrowserCurrentScope
end
```

`fetch_live_flash/2` comes from `Phoenix.LiveView.Router`, which is already imported by the `router/0` helper in `cadence_web.ex` (Task B7). It works the same as `fetch_flash/2` for controller-only pages and additionally merges LiveView-emitted flashes, so swapping is safe for the pages that are still controller-only.

Second, in the `redirect_if_authenticated_scope` scope (around lines 31–36), change:

```elixir
scope "/", CadenceWeb do
  pipe_through [:browser, :redirect_if_authenticated_scope]

  get "/sign-in", UserSessionController, :new
  post "/sign-in", UserSessionController, :create
end
```

to:

```elixir
scope "/", CadenceWeb do
  pipe_through [:browser, :redirect_if_authenticated_scope]

  live "/sign-in", UserSessionLive, :new
  post "/sign-in", UserSessionController, :create
end
```

- [ ] **Step 3: Compile**

Run: `mix compile --warnings-as-errors`
Expected: a warning or error about `UserSessionController.new/2` being unused is possible — address in Task C7 by deleting the function.

- [ ] **Step 4: Don't run the LiveView tests yet** — the controller still renders the old template in its error paths; we'll unify both in Task C7.

### Task C7: Refactor `UserSessionController` to use `Cadence.sign_in/2`

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex`
- Delete: `apps/cadence_web/lib/cadence_web/controllers/user_session_html.ex`
- Delete: `apps/cadence_web/lib/cadence_web/controllers/user_session_html/new.html.heex`

- [ ] **Step 1: Rewrite the controller**

Replace the entire contents of `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex` with:

```elixir
defmodule CadenceWeb.UserSessionController do
  use CadenceWeb, :controller

  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def create(conn, %{"user" => credentials}) when is_map(credentials) do
    with {:ok, {email, password}} <- ControlPlaneParams.durable_session(credentials),
         {:ok, issued_session} <- Cadence.sign_in(email, password) do
      finalize_sign_in(conn, issued_session)
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, human_message(reason))
        |> redirect(to: ~p"/sign-in")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Submit a valid sign-in form.")
    |> redirect(to: ~p"/sign-in")
  end

  def delete(conn, _params) do
    revoke_session_token(conn)

    conn
    |> renew_browser_session()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: ~p"/sign-in")
  end

  defp finalize_sign_in(conn, issued_session) do
    conn
    |> renew_browser_session()
    |> put_session(:user_session_token, issued_session.session_token)
    |> maybe_put_current_organization(issued_session.current_organization_id)
    |> put_flash(:info, "Signed in.")
    |> redirect(to: redirect_target(conn, issued_session))
  end

  defp redirect_target(conn, issued_session) do
    current_scope =
      case Cadence.authenticate_api_token(issued_session.session_token,
             current_organization_id: issued_session.current_organization_id
           ) do
        {:ok, %Scope{} = scope} -> scope
        {:error, _reason} -> issued_session.user
      end

    conn
    |> get_session(:user_return_to)
    |> AuthenticatedEntry.redirect_path(current_scope)
  end

  defp maybe_put_current_organization(conn, organization_id) when is_binary(organization_id) do
    put_session(conn, :current_organization_id, organization_id)
  end

  defp maybe_put_current_organization(conn, _other) do
    delete_session(conn, :current_organization_id)
  end

  defp revoke_session_token(conn) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        Cadence.revoke_user_session(session_token)

      _other ->
        :ok
    end
  end

  defp renew_browser_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp human_message(:invalid_credentials), do: "The supplied email or password was rejected."

  defp human_message({:invalid_param, _field, :required}),
    do: "Enter both email and password."

  defp human_message(_reason), do: "Cadence could not establish a browser session."
end
```

- [ ] **Step 2: Delete the old HTML view and template**

Run:
```bash
git rm apps/cadence_web/lib/cadence_web/controllers/user_session_html.ex
git rm apps/cadence_web/lib/cadence_web/controllers/user_session_html/new.html.heex
rmdir apps/cadence_web/lib/cadence_web/controllers/user_session_html 2>/dev/null || true
```
Expected: files removed from the index and disk.

- [ ] **Step 3: Compile**

Run: `mix compile --warnings-as-errors`
Expected: clean compile. If there's a warning about an unused alias in the controller, clean it up.

- [ ] **Step 4: Run the LiveView tests — they should now pass**

Run: `mix test apps/cadence_web/test/cadence_web/live/user_session_live_test.exs`
Expected: all 4 tests pass.

- [ ] **Step 5: Don't commit yet** — `browser_shell_test.exs` still has the old assertions. That's Task C8.

### Task C8: Rewrite `browser_shell_test.exs` for the new flow

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`

This test file has several tests that use the old `%{"durable_session" => %{...}}` and `%{"setup_access_session" => %{...}}` param shapes, old error-rendering assumptions (`html_response(conn, 422)`), and assertions about the dual-form UI. They need to migrate to the new unified shape and flash-based error handling.

- [ ] **Step 1: Update the "sign-in page renders forms" test**

Find the test starting with `test "sign-in page shows durable and setup access forms while setup is pending"` (around line 43). Replace it with:

```elixir
  test "sign-in page renders a single unified sign-in form", %{conn: conn} do
    response = conn |> get("/sign-in") |> html_response(200)

    assert response =~ "Cadence Access"
    assert response =~ "Sign in to Cadence"
    assert response =~ ~s(id="sign-in-form")
    refute response =~ "setup-access-sign-in-form"
    refute response =~ "durable-sign-in-form"
  end
```

- [ ] **Step 2: Update the "setup access establishes session" test**

Find the test starting with `test "setup access can establish a browser session and reach setup home"` (around line 50). Replace it with:

```elixir
  test "bootstrap credentials on /sign-in during setup establish a session and reach setup home",
       %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/setup"

    response =
      conn
      |> recycle()
      |> get("/setup")
      |> html_response(200)

    assert response =~ "setup-home"
    assert response =~ "first-tenant-form"
    assert response =~ "Bootstrap Admin"
    assert response =~ @bootstrap_admin_email
  end
```

- [ ] **Step 3: Update the "durable sign-in reaches operator home" test**

Find the assertion block inside `test "setup handoff grants an existing durable user directly and durable sign-in reaches operator home"` (around line 121). Replace the `durable_conn` block:

```elixir
    durable_conn =
      build_conn()
      |> post("/sign-in", %{
        "durable_session" => %{
          "email" => "ops-lead@example.com",
          "password" => durable_password
        }
      })
```

with:

```elixir
    durable_conn =
      build_conn()
      |> post("/sign-in", %{
        "user" => %{
          "email" => "ops-lead@example.com",
          "password" => durable_password
        }
      })
```

- [ ] **Step 4: Update the "invalid bootstrap credentials" test**

Find the test starting with `test "invalid bootstrap credentials keep the user on the sign-in page"` (around line 209). Replace it with:

```elixir
  test "invalid credentials redirect back to /sign-in with a flash error", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => "definitely-wrong"
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"
  end
```

- [ ] **Step 5: Update the "completed setup" test to use the tightened bootstrap gate**

Find the test starting with `test "completed setup hides the temporary setup sign-in form and keeps durable sign-in available"` (around line 243). Replace it with:

```elixir
  test "completed setup rejects bootstrap credentials via the tightened sign_in/2 gate",
       %{conn: conn} do
    persist_completed_setup!()

    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"

    response = build_conn() |> get("/sign-in") |> html_response(200)
    assert response =~ ~s(id="sign-in-form")
    refute response =~ "setup-access-sign-in-form"
  end
```

- [ ] **Step 6: Run the full browser_shell_test.exs**

Run: `mix test apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`
Expected: all tests pass.

- [ ] **Step 7: Run the full test suite**

Run: `mix test`
Expected: all tests pass across the umbrella.

- [ ] **Step 8: Run credo strict across touched files**

Run:
```bash
mix credo --strict apps/cadence/lib/cadence/accounts.ex apps/cadence/lib/cadence/auth.ex apps/cadence/lib/cadence.ex apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex apps/cadence_web/lib/cadence_web/live/user_session_live.ex apps/cadence_web/lib/cadence_web/components/ui.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/lib/cadence_web/endpoint.ex apps/cadence_web/lib/cadence_web.ex
```
Expected: no new violations.

- [ ] **Step 9: Commit**

```bash
git add \
  apps/cadence_web/lib/cadence_web/live/user_session_live.ex \
  apps/cadence_web/lib/cadence_web/router.ex \
  apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex \
  apps/cadence_web/lib/cadence_web/controllers/user_session_html.ex \
  apps/cadence_web/lib/cadence_web/controllers/user_session_html/new.html.heex \
  apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs \
  apps/cadence_web/test/cadence_web/live/user_session_live_test.exs
git commit -m "$(cat <<'EOF'
feat(cadence_web): rebuild /sign-in as single-form LiveView

Adds CadenceWeb.UserSessionLive, makes GET /sign-in a live route,
collapses UserSessionController.create/2 to a single Cadence.sign_in/2
call with flash-based error handling, deletes the old
user_session_html/new.html.heex parallel-forms template, and migrates
browser_shell_test.exs to use the unified %{"user" => %{...}} param
shape and redirect+flash assertions. The setup-access path is now
invisible to the UI — operators type one form and the server dispatches
to the right credential kind based on the email's active credentials.

EOF
)"
```

### Task C9: Milestone C verification

- [ ] **Step 1: Run the full test suite once more**

Run: `mix test`
Expected: all tests pass across `cadence` and `cadence_web`.

- [ ] **Step 2: Manual smoke test the page renders**

Run: `mix assets.build && mix phx.server`
In another terminal / browser, visit `http://localhost:4001/sign-in`. Expected: the single-form sign-in page renders with the hero panel, eyebrow, title, copy, email field, password field, and sign-in button using the Tailwind-built CSS. Ctrl+C to stop the server.

- [ ] **Step 3: Confirm the three-milestone commit chain**

Run: `git log --oneline -20`
Expected: Milestone C commits (Tasks C2, C3, C4, and the combined C5–C8 commit landed in Task C8 Step 9) stack on Milestone B commits on top of Milestone A commits on top of `7305cd1 some basic ui`. Milestone A is 4 commits (A1, A2, A3, A4), Milestone B is 8 commits (B1, B2, B3, B4, B5, B6, B7, B8), Milestone C is 4 commits (C2, C3, C4, C8). Total: 16 commits on top of the starting point. Verification tasks A5, B9, C9 do not produce commits.

- [ ] **Step 4: Done.**

The slice is complete. Next slice sketched in the spec: authenticated shell, platform admin landing, then platform admin CRUD surfaces.

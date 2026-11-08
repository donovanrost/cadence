# Apogee QA runbook — local backend for the console

Owner: qa (`w0R:p6`). This worktree's dev stack runs in qa's tab. Don't start a second
server, Vite or simulator from this worktree; ask qa to restart one if you need it (after a
config, dependency or `dev.exs` change; code changes hot-reload).

## What's running

| Thing | Where | Pane | Notes |
| --- | --- | --- | --- |
| **Phoenix (this worktree)** | **http://127.0.0.1:4011** | `w0R:p7` qa-server | node `cadence_apogee` |
| **Console Vite dev server** | http://127.0.0.1:5181/console/ | `w0R:p9` qa-console-vite | Phoenix fetches `index.html` from it in dev |
| **Earendil simulator (this worktree)** | http://127.0.0.1:4111 | `w0R:pA` qa-simulator | DETS under this worktree's `var/reflect_orbital/` |
| Postgres | localhost:5432, db **`cadence_apogee_dev`** | | this worktree only |
| Main checkout (not ours) | Phoenix :4001, simulator :4101, db `cadence_dev` | | `~/projects/cadence/cadence`. Don't touch. |
| User's ex-orbital-dynamics demo (not ours) | :4000, Vite :5180 | | why the console moved to 5181 |

The worktree is fully isolated from the main checkout: its own DB (so our migrations never alter
`cadence_dev`), its own simulator (so reservations don't collide), and its own ports.

## Login

- URL: http://127.0.0.1:4011/sign-in (prefer `127.0.0.1`: the endpoint binds IPv4 only,
  and `localhost` can resolve to `::1`; cookies don't carry across the two hostnames either)
- Email `admin@example.com`, password `change-me` (from `mise.toml`
  `CADENCE_ADMIN_EMAIL` / `CADENCE_ADMIN_PASSWORD`; the env administrator, created on server
  boot, enters admin mode)
- Console: http://127.0.0.1:4011/console

Demo data: **Reflect Orbital** (`org-reflect-orbital-demo`) → **Earendil**
(`mission-earendil-demo`): 500 spacecraft, 20 planes, 10 sites, 38 antennas. See
`docs/how-to/run-reflect-orbital-demo.md`.

### QA personas (non-admin users)

The env admin runs in platform admin mode, which can hide capability-gating bugs. For gated UI
and the two-person rule, use these Reflect Orbital users (password `apogee-qa-password`):

| Email | Role |
| --- | --- |
| `qa-operator@example.com` | `member` |
| `qa-second@example.com` | `member` (second operator / approver) |
| `qa-org-admin@example.com` | `organization_admin` (no platform admin) |

## Start everything from scratch

From the repo root of this worktree, each long-running command in its own pane:

```sh
# 1. Simulator (leave running)
cd apps/cadence_simulator
EARENDIL_SIMULATOR_PORT=4111 mise exec -- mix run --no-start --no-halt ../../dev/reflect_orbital_simulator.exs

# 2. Database (once)
cd apps/cadence_web
export CADENCE_DEV_DATABASE=cadence_apogee_dev
mise exec -- mix ecto.create -r Cadence.Repo
mise exec -- mix ecto.migrate -r Cadence.Repo

# 3. Phoenix (leave running; boot creates the env admin user)
CADENCE_DEV_DATABASE=cadence_apogee_dev PORT=4011 \
  mise exec -- iex --sname cadence_apogee --cookie cadence -S mix phx.server

# 4. Seed (once; both are rerunnable)
CADENCE_DEV_DATABASE=cadence_apogee_dev EARENDIL_PROVIDER_URL=http://127.0.0.1:4111 \
  mise exec -- mix run --no-start ../../dev/reflect_orbital_demo.exs
CADENCE_DEV_DATABASE=cadence_apogee_dev \
  mise exec -- mix run --no-start ../../dev/apogee_qa_personas.exs

# 5. Console Vite (leave running)
cd frontend && corepack pnpm --filter @cadence/console dev
```

Notes:

- **Every** `mix` command for this worktree needs `CADENCE_DEV_DATABASE=cadence_apogee_dev`;
  without it you hit the main checkout's `cadence_dev`.
- From `apps/cadence_web`, Ecto tasks need `-r Cadence.Repo` (otherwise they silently do nothing).
- Don't use `mise run cadence`: it hard-codes `--sname cadence`, which collides with the main
  checkout's node.
- `Waiting for lock on the build directory` means a teammate is compiling; it continues after.
- Use `System.halt()` in the qa-server iex to stop it.
- No global `node`: use `mise exec node@24 -- …`, or run `corepack pnpm …` from `frontend/`.

## Migrations

New migrations (from domain/api) only need: stop qa-server → `mix ecto.migrate -r Cadence.Repo`
with the env var → restart. Tell qa and I'll do it. `cadence_dev` is left alone (it is 8 upstream
migrations behind and belongs to the main checkout).

## Known limits

- **Live telemetry:** `mise run earendil-live` attaches to node `cadence@…` (the main checkout). Not
  wired to this worktree yet. QuestDB (history) isn't running, so history views may be empty.
- **Ingress ports:** the Earendil seed binds delivery transports on 127.0.0.1:42100–42109. If the
  main checkout realizes contacts at the same time, one side gets `eaddrinuse`.

## Playwright

- Playwright `1.62.1`, system Chrome (`channel: "chrome"`).
- Sign-in selectors: `#user_email`, `#user_password`, `#sign-in-form button[type="submit"]`.
- Console e2e suite: `docs/apogee/qa/e2e.md`.

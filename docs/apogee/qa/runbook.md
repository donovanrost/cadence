# Apogee QA runbook — local backend for the console

Owner: qa (`w0R:p6`). This worktree's dev stack runs in qa's tab. Don't start a second
server, Vite or simulator from this worktree; ask qa to restart one if you need it (after a
config, dependency or `dev.exs` change; code changes hot-reload).

## What's running

| Thing | Where | Pane | Notes |
| --- | --- | --- | --- |
| **Phoenix (this worktree)** | **http://127.0.0.1:4011** | `w0R:p7` qa-server | node `cadence_apogee` |
| **Console Vite dev server** | http://127.0.0.1:5181/console/ | `w0R:p9` qa-console-vite | Phoenix fetches `index.html` from it in dev |
| **LiveView Vite (sign-in etc.)** | http://127.0.0.1:5183 | started by Phoenix's watcher | needs `apps/cadence_web/node_modules` (`npm ci` there) |
| **Earendil simulator (this worktree)** | http://127.0.0.1:4111 | `w0R:pA` qa-simulator | DETS under this worktree's `var/reflect_orbital/` |
| Live telemetry feeds (**off by default**) | 10 spacecraft (EARENDIL-001…010) at 1 Hz | `w0R:pB` qa-live-feeds | run on request, short; see Known limits |
| **QuestDB (history)** | REST http://127.0.0.1:9200 · PG wire 8822 · ILP 9209 | docker `cadence-apogee-questdb` | volume `var/questdb-apogee/` (gitignored) |
| Postgres | localhost:5432, db **`cadence_apogee_dev`** | | this worktree only |
| Main checkout (not ours) | Phoenix :4001, simulator :4101, db `cadence_dev`, QuestDB :9000/:9009/:8812 (compose, `var/questdb`) | | `~/projects/cadence/cadence`. Don't touch. |
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

# 2. QuestDB (once; it keeps running across reboots of the shell, not of OrbStack)
docker run -d --name cadence-apogee-questdb \
  -p 127.0.0.1:9200:9000 -p 127.0.0.1:9209:9009 -p 127.0.0.1:8822:8812 -p 127.0.0.1:9203:9003 \
  -v "$PWD/var/questdb-apogee:/var/lib/questdb" questdb/questdb:9.4.3
# later: docker start cadence-apogee-questdb

# 3. Database + QuestDB schema (once)
cd apps/cadence_web
export CADENCE_DEV_DATABASE=cadence_apogee_dev CADENCE_QUESTDB_HTTP_ENDPOINT=http://127.0.0.1:9200 \
  CADENCE_QUESTDB_HOST=127.0.0.1 CADENCE_QUESTDB_PORT=8822
mise exec -- mix ecto.create -r Cadence.Repo
mise exec -- mix ecto.migrate -r Cadence.Repo
mise exec -- mix cadence.questdb.migrate

# 4. Phoenix (leave running; boot creates the env admin user). Same exports as step 3, plus
#    OTEL off (mise.toml points at a collector on :4318 that isn't running) and durable current
#    values (the default ETS store forgets every last_received_at on restart; qa #7), and its own
#    LiveView Vite (default 5173 is the main checkout's: our sign-in would run its JS).
#    First time: (cd apps/cadence_web && npm ci), or the watcher can't start and sign-in breaks.
CADENCE_LIVE_VUE_VITE_PORT=5183 CADENCE_TELEMETRY_CURRENT_VALUE_STORE=postgres OTEL_EXPORTER_OTLP_ENDPOINT= POOL_SIZE=30 DB_QUEUE_TARGET_MS=1000 PORT=4011 \
  mise exec -- iex --sname cadence_apogee --cookie cadence -S mix phx.server

# 5. Seed (once; both are rerunnable)
CADENCE_DEV_DATABASE=cadence_apogee_dev EARENDIL_PROVIDER_URL=http://127.0.0.1:4111 \
  mise exec -- mix run --no-start ../../dev/reflect_orbital_demo.exs
CADENCE_DEV_DATABASE=cadence_apogee_dev \
  mise exec -- mix run --no-start ../../dev/apogee_qa_personas.exs

# 6. Activate the fleet (once; rerunnable). From the repo root. --single-operator sets
#    Earendil's *configuration activation* policy to direct, in this DB only (not commanding).
EARENDIL_CADENCE_NODE=cadence_apogee \
  mise exec -- elixir --sname earendil_setup_apogee --cookie cadence dev/reflect_orbital_activate.exs --single-operator

# 7. Live feeds (on request only; keep them short, e.g. EARENDIL_DEMO_CONTACT_SECONDS=600)
cd apps/cadence_simulator
CADENCE_DEV_DATABASE=cadence_apogee_dev EARENDIL_CADENCE_NODE=cadence_apogee \
  mise exec -- elixir --hidden --sname earendil_tm_apogee --cookie cadence \
  -S mix run --no-start ../../dev/reflect_orbital_live.exs

# 8. Console Vite (leave running)
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

- **Live telemetry saturates the shared laptop.** On 2026-11-08, ten 1 Hz feeds plus team builds
  pushed load to ~50: ingest stalled after ~5 min (receivers timing out) and sign-in took 34 s.
  Run feeds briefly, then stop them (Ctrl-C, `a`): after short contacts end the script keeps
  reconnecting instead of exiting. Captured history: ~174k rows for EARENDIL-001…010,
  2026-11-08 22:26–22:31Z and 22:55–22:56Z; those 10 have durable current values (heard 22:55Z).
- **Live telemetry** covers EARENDIL-001…010 only; the other 490 stay `never_heard`. The feeds
  stop when their contacts end (2 h); rerun step 7. `dev/reflect_orbital_{live,activate}.exs`
  take `EARENDIL_CADENCE_NODE` (default `cadence`, i.e. the main checkout).
- **No limits configured** in the seed, so nothing goes critical/caution on its own. Specs use
  fixtures over the real `/fleet` read (`e2e/support/fleet.ts`).
- **Ingress ports:** the Earendil seed binds delivery transports on 127.0.0.1:42100–42109. If the
  main checkout realizes contacts at the same time, one side gets `eaddrinuse`.

## Playwright

- Playwright `1.62.1`, system Chrome (`channel: "chrome"`).
- Sign-in selectors: `#user_email`, `#user_password`, `#sign-in-form button[type="submit"]`.
- Console e2e suite: `docs/apogee/qa/e2e.md`.

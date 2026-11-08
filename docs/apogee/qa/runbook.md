# Apogee QA runbook — local backend for the console

Owner: qa (`w0R:p6`). The shared dev server for this worktree runs in herdr pane
**`w0R:p7` ("qa-server")**. Don't start a second server from this worktree; ask qa to
restart this one if you need it (e.g. after a config or dependency change — code changes
hot-reload).

## What's running

| Thing | Where | Notes |
| --- | --- | --- |
| **Apogee worktree Phoenix** | **http://127.0.0.1:4011** | node `cadence_apogee`, pane `w0R:p7` |
| Main-checkout Phoenix (not ours) | http://127.0.0.1:4001 | `~/projects/cadence/cadence` on `develop`. Don't touch it. |
| Postgres | localhost:5432, db `cadence_dev` | **Shared** with the main checkout (see Migrations) |
| Earendil simulator (not ours) | 127.0.0.1:4101 | started from the main checkout; serves both servers |

Port 4011 because 4001 is taken by the main checkout's long-lived server. `config/dev.exs`
reads `PORT`, and `check_origin` follows it, so websockets work on 4011.

## Login

- URL: http://127.0.0.1:4011/sign-in (prefer `127.0.0.1`: the endpoint binds IPv4 only,
  and `localhost` can resolve to `::1`; cookies don't carry across the two hostnames either)
- Email `admin@example.com`, password `change-me` (from `mise.toml`
  `CADENCE_ADMIN_EMAIL` / `CADENCE_ADMIN_PASSWORD`; the env administrator, enters admin mode)
- After sign-in it lands on `/admin`.

The admin is an org member of:

| Organization | org id | Mission | mission id |
| --- | --- | --- | --- |
| **Reflect Orbital** (use this) | `org-reflect-orbital-demo` | **Earendil** — 500 spacecraft, 10 ground sites | `mission-earendil-demo` |
| SRE Observability Demo | `org-sre-demo-1791500936` | SRE Telemetry Exercise | `mission-sre-demo-1791500936` |
| asd | `org_gn6u4yiwj4_20` | asd | `mission_gn6u4yiwj4_3E` |

Earendil is the realistic dataset (see `docs/how-to/run-reflect-orbital-demo.md`).

## Start / restart the server

```sh
cd apps/cadence_web
PORT=4011 mise exec -- iex --sname cadence_apogee --cookie cadence -S mix phx.server
```

- Don't use `mise run cadence`: it hard-codes `--sname cadence`, which collides with the
  main checkout's node.
- If boot stalls on `Waiting for lock on the build directory`, another teammate is compiling
  in this worktree; it continues when they finish.
- The dev endpoint also starts a Vite watcher (port 5173) for the LiveVue assets. That's
  unrelated to the console SPA's own dev server.

## Migrations (shared DB)

As of 2026-11-08 this branch has **no pending migrations** against `cadence_dev`
(`mix ecto.migrations` shows nothing `down`). The main checkout runs on the same base commit.

**If api adds a migration:** running it alters the DB the main checkout also uses. Prefer
additive, reversible migrations, and tell qa before migrating so we can decide whether to
move the console to its own database (`cadence_apogee_dev`) instead.

Both servers run background workers (provider event inbox, contact scheduler) against the
same DB. Rows are claimed with `FOR UPDATE SKIP LOCKED`, so this is safe, but either node
may be the one that processes a given event.

## Live telemetry (optional)

`mise run earendil-live` (from `apps/cadence_simulator`) drives ten 1 Hz feeds. It attaches
to node `cadence@…`, i.e. the **main checkout's** server, not ours. Live channel pushes therefore
won't reach the 4011 node until we run feeds against it; persisted values in Postgres are
visible to both. QuestDB (telemetry history) isn't running locally right now, so
history-backed views may be empty or error. qa will set this up when Now / Uplink are ready
to test.

## Node / Playwright

- No global `node`; use `mise exec node@24 -- node …` or `corepack pnpm …` from `frontend/`.
- Playwright `1.62.1` is in the frontend catalog and Chrome is installed. Existing
  browser scripts launch `chromium.launch({ channel: "chrome" })`.
- Sign-in selectors: `#user_email`, `#user_password`, `#sign-in-form button[type="submit"]`.

## Console e2e suite

See `docs/apogee/qa/e2e.md` (once the scaffold lands).

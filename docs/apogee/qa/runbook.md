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
| `qa-org-admin-2@example.com` | `organization_admin` (second admin: approves what the first authored) |

## Start everything from scratch

From the repo root of this worktree, each long-running command in its own pane:

```sh
# 1. Simulator (leave running)
cd apps/cadence_simulator
# --sname qa_sim makes it reachable over RPC (fault injection, e.g. UplinkSessions.arm/2, 9f09dd32).
#    Its store is DETS, so a restart keeps bookings. Output goes to var/qa-simulator.log (director:
#    crash evidence; an Orchestrator restart orphaned a COP-1 peer once, #38).
EARENDIL_SIMULATOR_PORT=4111 mise exec -- elixir --sname qa_sim --cookie cadence -S mix run --no-start --no-halt ../../dev/reflect_orbital_simulator.exs 2>&1 | tee -a ../../var/qa-simulator.log

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
#    OTEL off (mise.toml points at a collector on :4318 that isn't running) and its own LiveView
#    Vite (default 5173 is the main checkout's: our sign-in would run its JS). Keep the default
#    ETS current-value store: Postgres current values need the Postgres packet-record archive, and
#    since 4e755071 the server refuses the Postgres store + filesystem archive pair at boot. Durable
#    last-heard comes from the history merge (qa #7). Output is teed to var/qa-server.log.
#    First time: (cd apps/cadence_web && npm ci), or the watcher can't start and sign-in breaks.
#    The QuestDB/DB variables are inline on purpose: a restart from a fresh shell without the
#    step-3 exports silently points the server at the main checkout's QuestDB ports (9000/8812).
#    Ingress journal ON (director, 2026-11-12; qa #48): without it a TM frame that fails processing
#    is dropped and a contact still reads 'settled'. The journal lives in this worktree's var/
#    (gitignored), capped at 2 GB (default 8 GB) because the laptop disk runs ~90% full: check
#    `df -h .` first and keep ≥ 10 GB free. Check after boot: rpc
#    Application.get_env(:cadence, :ingress_journal)[:enabled?] == true on cadence_apogee.
CADENCE_DEV_DATABASE=cadence_apogee_dev CADENCE_QUESTDB_HTTP_ENDPOINT=http://127.0.0.1:9200 \
  CADENCE_QUESTDB_HOST=127.0.0.1 CADENCE_QUESTDB_PORT=8822 EARENDIL_PROVIDER_URL=http://127.0.0.1:4111 \
  CADENCE_INGRESS_JOURNAL_ENABLED=true CADENCE_INGRESS_JOURNAL_PATH="$PWD/../../var/ingress_journal" \
  CADENCE_INGRESS_JOURNAL_MAX_BYTES=2147483648 \
  CADENCE_LIVE_VUE_VITE_PORT=5183 OTEL_EXPORTER_OTLP_ENDPOINT= POOL_SIZE=30 DB_QUEUE_TARGET_MS=1000 PORT=4011 \
  mise exec -- iex --sname cadence_apogee --cookie cadence -S mix phx.server 2>&1 | tee -a ../../var/qa-server.log
#    After any restart also drop the log level to :info (director, 2026-11-11: at :debug the log hit
#    28 GB and filled the disk). Over RPC on cadence_apogee: Logger.configure(level: :info).
#    If var/qa-server.log grows past a few GB, truncate it in place: : > var/qa-server.log
#    Check after any restart (expect 9200/8822; nil means restart again with the line above):
#    rpc System.get_env("CADENCE_QUESTDB_HTTP_ENDPOINT") on cadence_apogee
#    Then (director, 2026-11-12) check the mission runtime was admitted, ~1 min after boot:
#      rpc Cadence.Runtime.MissionCoordinator.active_spec("mission-earendil-demo")
#        -> {:ok, spec} with spec.generation == the live config generation (GET …/config head)
#      grep -c "mission_runtime_reconciler.*terminating" in the new part of var/qa-server.log -> 0
#    Also :code.modified_modules() == [] (no half-rebuilt _build/dev), the journal enabled
#    (Cadence.Ingress journal config: enabled? true, 2 GB) and any armed group still queued_for_contact.
#    :code.modified_modules() == [] alone does NOT catch this: on 11-11 the 22:14Z restart came up clean,
#    but the reconciler crash-looped (binary_to_existing_atom "criteria", then a binding-set hash
#    mismatch for r9's v3), so every spacecraft's TM failed ingress with no_active_binding_set.

# 5. Seed (once; both are rerunnable)
CADENCE_DEV_DATABASE=cadence_apogee_dev EARENDIL_PROVIDER_URL=http://127.0.0.1:4111 \
  mise exec -- mix run --no-start ../../dev/reflect_orbital_demo.exs
CADENCE_DEV_DATABASE=cadence_apogee_dev \
  mise exec -- mix run --no-start ../../dev/apogee_qa_personas.exs
# Contact planning (active fleet planning policy + 5-min recurring downlink templates for
# EARENDIL-001..010; EARENDIL_PLANNING_SPACECRAFT=N to change). Rerunnable; the full Earendil
# seed now includes it.
CADENCE_DEV_DATABASE=cadence_apogee_dev \
  mise exec -- mix run --no-start ../../dev/reflect_orbital_planning.exs

# 6. Activate the fleet (once; rerunnable). From the repo root. --single-operator sets
#    Earendil's *configuration activation* policy to direct, in this DB only (not commanding).
EARENDIL_CADENCE_NODE=cadence_apogee \
  mise exec -- elixir --sname earendil_setup_apogee --cookie cadence dev/reflect_orbital_activate.exs --single-operator

# ARMED PASSES (director, 2026-11-10). When a command group waits for a real pass:
#  - No simulator run pause/resume and no :4011 or simulator restart within 1 h of its AOS.
#    Pausing adds the paused time to the run's paused_duration_seconds and the orchestrator plays
#    every pass that much late (effective_now = now - offset); a :4011 restart drops COP-1 state
#    (uplink session 'not qualified: :protocol_state_restore_required').
#  - At T-15 min re-check: run offset is 0
#      CadenceSimulator.Provider.Store.fetch(:run, "run-earendil-demo-v1") -> "paused_duration_seconds"
#    (on node qa_sim; if non-zero, Store.put the run back with 0), the group is queued, the booking is
#    confirmed with command_window, and any CLCW override is armed on the right contact ref.
#  - To hold bookings 'pending' for unconfirmed-state checks, don't pause the run; find another way
#    (ask domain), or pause only far from any armed pass and reset the offset afterwards.
#  - Keep the host awake from arming until after LOS + the post-pass checks (director, 2026-11-11):
#      caffeinate -dims -t <seconds>     # in a spare shell; touches neither lib nor the stack
#    and check `pmset -g assertions | grep caffeinate` at T-15. A sleeping Mac lets the provider
#    play the pass without Cadence: 037's 11-11 13:10:59Z contact expired unrealized and QuestDB got
#    no TM while the host was in clamshell sleep 03:12-17:09Z (dark wakes only), and the 11-11 12:15Z
#    010 retest (#38) ran on a sleeping host. Keep the lid open and on power.

# 7. Live feeds (on request only; keep them short, e.g. EARENDIL_DEMO_CONTACT_SECONDS=600)
cd apps/cadence_simulator
CADENCE_DEV_DATABASE=cadence_apogee_dev EARENDIL_CADENCE_NODE=cadence_apogee EARENDIL_SIMULATOR_PORT=4111 \
  CADENCE_QUESTDB_HTTP_ENDPOINT=http://127.0.0.1:9200 CADENCE_QUESTDB_HOST=127.0.0.1 CADENCE_QUESTDB_PORT=8822 \
  EARENDIL_DEMO_CONTACT_SECONDS=120 \
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

**No dev-env mix tasks in the shared tree while :4011 runs** (lead, 2026-11-13). `_build/dev` *is*
the live server's code. A dev `mix compile`, `credo` or `cadence.architecture.check` rebuilt it at
03:42–03:54Z on 11-13. The node's reloader then purged `Cadence.Repo` under its running processes, and
`Application cadence exited: shutdown` at 03:45:59Z took the API down until qa restarted at 04:11Z.
Every Elixir check runs as `MIX_ENV=test scripts/check-slot.sh mix …`; check-slot refuses mix
otherwise. The live node picks up lib saves through its own reloader.

New dev-DB migrations (domain, api, api-ops) come to qa. qa runs them through the live node, one
version at a time, so nothing compiles into `_build/dev`:

```
# on cadence_apogee (rpc / Code.eval_string); the .exs is compiled in-node, not into _build
path = Application.app_dir(:cadence, "priv/repo/migrations")   # or the source dir if not copied
Ecto.Migrator.run(Cadence.Repo, path, :up, to: 20261113040000, log: :info)
Ecto.Migrator.migrations(Cadence.Repo, path)   # status before and after
```

Or qa folds them into a planned restart. Then the schema save follows seconds later, and qa runs the
post-restart checks above. Never during the freeze. Big tables: CREATE INDEX CONCURRENTLY and a
`lock_timeout` on ALTERs of hot tables (`mission_spacecraft`, `provider_audit_entries`).
`cadence_dev` is left alone (it belongs to the main checkout).

## Known limits

- **Live telemetry saturates the shared laptop.** On 2026-11-08, ten 1 Hz feeds plus team builds
  pushed load to ~50: ingest stalled after ~5 min (receivers timing out) and sign-in took 34 s.
  Run feeds briefly, then stop them (Ctrl-C, `a`): after short contacts end the script keeps
  reconnecting instead of exiting. Captured history: ~174k rows for EARENDIL-001…010,
  2026-11-08 22:26–22:31Z and 22:55–22:56Z; those 10 have durable current values (heard 22:55Z).
- **Live telemetry** covers EARENDIL-001…010 only; the other 490 stay `never_heard`. The feeds
  stop when their contacts end (2 h); rerun step 7. `dev/reflect_orbital_{live,activate}.exs`
  take `EARENDIL_CADENCE_NODE` (default `cadence`, i.e. the main checkout).
- **Personas:** the env admin (`user_environment_admin`) has no Reflect Orbital membership; in
  admin mode the console selects the org from the URL (qa #15). e2e runs as `qa-org-admin`.
- **Planning drafts:** reseeding planning templates invalidates existing drafts (they disappear
  from `/contact-plans`; ux is speccing a 'superseded' state). Drafting runs a real fleet planning
  run against the simulator: do it under load 16.
- **No limits configured** in the seed, so nothing goes critical/caution on its own. Specs use
  fixtures over the real `/fleet` read (`e2e/support/fleet.ts`).
- **Ingress ports:** the Earendil seed binds delivery transports on 127.0.0.1:42100–42109. If the
  main checkout realizes contacts at the same time, one side gets `eaddrinuse`.

## Playwright

- Playwright `1.62.1`, system Chrome (`channel: "chrome"`).
- Sign-in selectors: `#user_email`, `#user_password`, `#sign-in-form button[type="submit"]`.
- Console e2e suite: `docs/apogee/qa/e2e.md`.

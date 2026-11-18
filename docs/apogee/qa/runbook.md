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

**Last landing on ui/apogee-spa (frozen 2026-11-18 20:30Z, director):** `5f32ed4c7`, the tip after qa's 20:01Z
P3 step 1 + U76 + #226(b) restart (picks `ccec675e4` → `7ec082785`, `b72284662` → `20f96dbb2`, `c8868cabe` → `79d25fefe`,
`451fbbb0f` → `5f32ed4c7`; migrations 20261117160000, 20261117213000, 20261118040000 run one at a time with the node
down; post-checks PASS). Nothing was picked or committed onto ui/apogee-spa after it. From the develop cut-over
(about 08:00Z 11-19) every set is a PR into develop from its author's own branch, with CI green and a different
agent's review in the PR; only lead or the director merges; qa picks only merged develop SHAs. qa's own docs and
runbook changes also go as PRs.

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
#    DISTRIBUTION IS LOCAL-ONLY (director 11-17): epmd and the distribution ports bind 127.0.0.1
#    (ERL_EPMD_ADDRESS + inet_dist_use_interface), and the cookie is a random per-machine value in
#    var/qa-erlang-cookie (git-ignored, mode 600; NEVER ~/.erlang.cookie; never in a committed file).
#    Create it once: (umask 077; head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40 > var/qa-erlang-cookie)
#    Check after any restart: lsof -nP -iTCP -sTCP:LISTEN | grep -E 'epmd|beam' shows 127.0.0.1 only.
cd apps/cadence_simulator
# --sname qa_sim makes it reachable over RPC (fault injection, e.g. UplinkSessions.arm/2, 9f09dd32).
#    Its store is DETS, so a restart keeps bookings. Output goes to var/qa-simulator.log (director:
#    crash evidence; an Orchestrator restart orphaned a COP-1 peer once, #38).
EARENDIL_SIMULATOR_PORT=4111 ERL_EPMD_ADDRESS=127.0.0.1 mise exec -- elixir --sname qa_sim --cookie "$(cat ../../var/qa-erlang-cookie)" --erl "-kernel inet_dist_use_interface {127,0,0,1}" -S mix run --no-start --no-halt ../../dev/reflect_orbital_simulator.exs 2>&1 | tee -a ../../var/qa-simulator.log

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
#    `df -h .` first and keep ≥ 10 GB free. The journal shares the HOST disk that filled on 11-14
#    (devops, 11-15; #95 makes it on by default everywhere): fine at 10 live craft, but it grows
#    during passes and reclaims only ~72 h after settle, so count var/ingress_journal in the disk
#    checks (`du -sh var/ingress_journal`) and keep the 2 GB cap here. Check after boot: rpc
#    Application.get_env(:cadence, :ingress_journal)[:enabled?] == true on cadence_apogee.
CADENCE_DEV_DATABASE=cadence_apogee_dev CADENCE_QUESTDB_HTTP_ENDPOINT=http://127.0.0.1:9200 \
  CADENCE_QUESTDB_HOST=127.0.0.1 CADENCE_QUESTDB_PORT=8822 EARENDIL_PROVIDER_URL=http://127.0.0.1:4111 \
  CADENCE_INGRESS_JOURNAL_ENABLED=true CADENCE_INGRESS_JOURNAL_PATH="$PWD/../../var/ingress_journal" \
  CADENCE_INGRESS_JOURNAL_MAX_BYTES=2147483648 \
  CADENCE_LIVE_VUE_VITE_PORT=5183 POOL_SIZE=30 DB_QUEUE_TARGET_MS=1000 PORT=4011 \
  ERL_EPMD_ADDRESS=127.0.0.1 mise exec -- env OTEL_EXPORTER_OTLP_ENDPOINT= ELIXIR_ERL_OPTIONS="-logger level info -kernel inet_dist_use_interface {127,0,0,1}" iex --sname cadence_apogee --cookie "$(cat ../../var/qa-erlang-cookie)" -S mix phx.server 2>&1 | tee -a ../../var/qa-server.log
#    OTEL_EXPORTER_OTLP_ENDPOINT is cleared AFTER mise (api-ops 11-14): set before `mise exec`, mise.toml's
#    [env] value (http://localhost:4318) wins, runtime.exs turns the OTLP exporter on, and with nothing on
#    4318 the log gets 'client error exporting … econnrefused' ~12×/min.
#    The node STARTS at :info (director, 11-16): ELIXIR_ERL_OPTIONS="-logger level info" sets the :logger
#    app's level at boot (dev config sets none, so it isn't overridden; checked: plain elixir reports
#    :debug without it, :info with it). At :debug the log hit 28 GB on 11-11 and 2.3 GB on 11-16 (07:52Z
#    to 17:00Z, a skipped manual step). The post-boot check (var/qa-scripts/postboot-comb.exs) reports
#    log_level_info?: it must be true; if it isn't, Over RPC on cadence_apogee: Logger.configure(level: :info)
#    (var/qa-scripts/loglevel-info.exs) and find out why before going on.
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
#    Cherry-pick gate (11-14): after a change adds or removes a struct field in apps/cadence, run
#    MIX_ENV=test mix compile --force in apps/cadence_web once per worktree; an incremental build
#    can keep a stale inferred type and report a false incompatibility (64387fb7e's RawEvidence
#    field gave "incompatible types given to Control.Ingress.process_and_persist/1").
#    Also fetch deps after a lock change: mix deps.get in each of apps/cadence, cadence_web,
#    cadence_simulator (each app keeps its own deps/; a root-only deps.get leaves them stale).

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

# 6. Activate the fleet: IN THE CONSOLE ONLY (director 11-18). dev/reflect_orbital_activate.exs is never run on
#    this stack, in any mode: Earendil's first activation is a four-eyes console activation (stager and
#    approver different agents, each recorded), done in the slot before Earendil's first pass. See
#    var/qa-dev-reset-plan-draft.md, step 6 'Activation' (11-21 dev reset).

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
#  - RULE (director, 11-14): pausing or resuming the shared sim run is a qa-owned action, like a restart.
#    Nobody else pauses or resumes it. qa checks paused_duration_seconds is 0 before every pass it
#    cares about. (A late pass start isn't always a pause: 11-14's 12:10:57Z 30 s was issue 62's
#    window bug, with offset 0.)
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
  mise exec -- elixir --hidden --sname earendil_tm_apogee --cookie "$(cat ../../var/qa-erlang-cookie)" \
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

Or qa folds them into a planned restart.

**Before any planned :4011 or simulator restart** (11-14 01:36Z: the (B) restart cut a live 008 pass and its
settlement replay then looped on an archive identity conflict, issues.md #60), check all three, read-only:
no command group armed within 1 h; NO realized contact in `active` and no scheduled contact starting
before the node is back (allow ~10 min); a graceful stop (`:init.stop` over RPC), never a kill.
`select count(*) from realized_contacts where lifecycle_state = 'active'` and
`select count(*) from scheduled_contacts where starts_at between now() and now() + interval '15 minutes'`.

**When a save breaks the compile** (11-13 09:59-10:03Z: an uncommitted controller edit with an
undefined function made `CadenceWeb.Router` "not available", so every request 500'd), the dev
reloader doesn't retry after the fix is saved. Once the file compiles (`MIX_ENV=test
scripts/check-slot.sh mix compile` passes), trigger it in-node:
`:rpc.call(:"cadence_apogee@<host>", Phoenix.CodeReloader, :reload, [CadenceWeb.Endpoint])`
(scratchpad `reload-now.exs`), then sign-in 200, `active_spec`, `modified_modules` = [] and armed
groups still queued. The same applies when a save just doesn't look live (06:14Z router save,
11-13). Then the schema save follows seconds later, and qa runs the
post-restart checks above. Never during the freeze. Big tables: CREATE INDEX CONCURRENTLY and a
`lock_timeout` on ALTERs of hot tables (`mission_spacecraft`, `provider_audit_entries`).
`cadence_dev` is left alone (it belongs to the main checkout).

**Test partitions go stale** (lead, 2026-11-13). Each `MIX_TEST_PARTITION=N` has its own database,
`cadence_testN`, and `mix test` doesn't migrate it. A partition last used before a migration landed
fails with `Postgrex.Error ERROR 42703 (undefined_column)` (or `42P01 undefined_table`). That is a
stale database, not a real failure: on 11-13 `OpsLandingPageTest` on partition 11 died on
`command_requests.command_group_id`, with 53 migrations missing. Check every partition against the
tree (missing = migrations the database hasn't run):

```
ls apps/cadence/priv/repo/migrations/*.exs | xargs -n1 basename | sed 's/_.*//' | sort > /tmp/mig.txt
for db in $(psql -h localhost -U postgres -Atc "select datname from pg_database where datname ~ '^cadence_test(1?[0-9])?$'"); do
  echo "$db missing=$(psql -h localhost -U postgres -d $db -Atc 'select version from schema_migrations' | sort | comm -23 /tmp/mig.txt - | wc -l)"
done
```

A test database isn't :4011's, so qa doesn't schedule it. Migrate it through check-slot:
`cd apps/cadence && MIX_ENV=test MIX_TEST_PARTITION=N ../../scripts/check-slot.sh mix ecto.migrate`
(empty N = `cadence_test`). On 11-13, partitions 2, 3, 4, 5, 7, 10, 11 and 19 were brought up to
20261113150000.

**Port worktrees use partitions 20–29** (lead, 2026-11-13). Partitions empty–19 belong to the team
tree and carry `ui/apogee-spa`'s schema. A port worktree (`develop-*`, `main-*`, `fix/*`) running
tests there gets misleading evidence. Our columns can break an older branch's inserts (NOT NULL
without a default), or its tests pass against tables that branch doesn't have. So:

- develop ports use 20–24, main ports 25–29 (fix/* takes the free number in its target's range);
  the port's evidence names its partition.
- Before every evidence run, rebuild the partition from **that worktree's own** migrations: check
  nobody's connected (`select count(*) from pg_stat_activity where datname = 'cadence_testN'` → 0),
  then from the port worktree's `apps/cadence`:

  ```
  export MIX_ENV=test MIX_TEST_PARTITION=21
  CS=~/.herdr/worktrees/cadence/ui-apogee-spa/scripts/check-slot.sh   # older branches lack it
  $CS mix ecto.drop && $CS mix ecto.create && $CS mix ecto.migrate
  ```

  and run that worktree's tests with the same `MIX_TEST_PARTITION`. Drop-and-recreate (not just
  migrate) is what removes another branch's extra tables and columns.
- Never point a team-tree run at 20–29, or a port run at empty–19.

**Partition register** (lead, 2026-11-14). **Claim a partition here before using it, and never
drop, recreate or migrate a partition you don't own.** Release a claim by deleting your row.
(11-14 02:50Z: the `57P01 admin_shutdown` on `cadence_test3` during api-ops' L4 suite was the suite's own
`frontend_release_publisher_controller_test` / publication janitor test, which call `pg_terminate_backend`
on purpose. Nobody dropped it, but it's why a partition must not be shared between concurrent runs.)

| Partition | Owner | Purpose |
|---|---|---|
| empty (`cadence_test`) | team | shared-tree runs through check-slot (no `MIX_TEST_PARTITION`): no claim needed; never drop it |
| 2, 4, 5, 6, 7, 8, 10, 11, 14–17, 19 | unclaimed | worktree runs: claim before use |
| 3 | api-ops | provenance B (#171) side worktree `api-ops-provenance-b` (DB dropped for disk 11-18 ~09:5xZ; recreated fresh before its evidence run) |
| 9 | api | api's side worktree for slot work (`…/cadence/api-held`) |
| 12 | domain | domain's evidence runs (archive fix, #83) |
| 13 | fe-setup | L10/L12/L13 worktree (`fe-setup-l10-13`; re-labelled 11-14 from the L8b worktree, lead) |
| 18 | fe-ops | L8 worktree |
| 21 | domain | domain's develop ports (verifier fix, gate, contact start, archive fix) |
| 20, 22–23 | unclaimed | develop ports: claim before use |
| 24 | devops | devops' develop evidence |
| 26 | domain | domain's main ports |
| 25, 27–29 | unclaimed | main ports: claim before use |
| 31 | qa | restart dry assemblies (`scratchpad/dry-b-wt`; (B) 11-14 01:23–01:35Z, the L8 + L4 bundle next) |

## Trial picks the evening before

(Director, 11-17, ruling 6.) The evening before a slot, qa trial-picks every set queued for it onto the current
shared head. This is read-only and runs in a side worktree, never the shared tree: `git cherry-pick -x` in order.

- Record the pick rc and each commit's `git patch-id --stable` against the source in the checklist.
- When a set deletes or renames a module, `git grep` the head for its remaining users. A clean pick does not prove
  that nothing else depends on it.
- A conflict, or a remaining user, goes to the set's owner and lead that same evening, so the re-cut is ready before
  the slot.
- Re-run the trial for any set whose base moves after the evening check.
- The trial is not the dry. The slot still needs its dry on the exact tree.

Why: on 11-17 the step 4 drift-fix set, reviewed 11-15 on an older base, failed its pick at slot time. 67e87cdfd
deleted `Platform.ReadMemo`, which U61 (8cc9f07c8, landed 11-16) had started using in `Reads.Attention` and
`Reads.PlanCoverageAttention`. Purging it on the live node would have broken every Now attention load.

**Restart chain order is fixed** (director via lead, 11-17). A chain runs in its agreed order, each step after the
previous one's post-checks. A later step never moves ahead to keep its time. When an earlier step slips, everything
after it slides; what no longer fits the day moves to the next day in the same order, never compressed. Protected
windows (for example, around an armed run) stay closed whatever slips.

**Chain rules** (director 11-17):

1. The chain owner checks each step's expected END as well as its start, and pings within 15 min of either being
   missed.
2. Every approval step in a chain names a backup approver, a different agent from the stager. If the named approver
   hasn't acted within 15 min of the hand-off, the owner switches to the backup; an approval never sits waiting on one
   session.
3. Every heavy-job hold has an end time when it is set. If the step it protects hasn't started by then, the hold
   lapses and the owner re-sets it explicitly. qa's slot lock note carries the same end time.

Why: on 11-17 step 4 part 2 (the r10 apply) stalled from 09:17Z to 12:4xZ. The approver's session dropped on a
connection error right after qa's hand-off. qa held the slot lock and waited for the approver's ping, and nobody
checked the step's expected end. The hold and lock had no end time, so the whole chain waited about three hours.

**Configuration changes: four-eyes** (director 11-16, 11-17). Outside QA test data, the approver is a different agent
from the stager, and reads the preview themselves through `qa-org-admin-2`. The checklist names the agent behind
each account. From 11-18, once Earendil and the QA mission are on the independent policy (a console action by an
admin, first item that day), the flow is: **stage, submit, then a second agent approves and applies**. Until then an
admin's approve-and-apply writes the submission but no row in `mission_config_reviews`; record it as found.

**New missions vs change sets** (domain, 11-18 item 3): a new mission starts running through each spacecraft's
configuration (Review, then Activate). A change set changes a mission that's already running; on a mission with
nothing running, it saves the changes but starts nothing.

**Command groups:** Group members are approved only through the group's GO/NO-GO (enforced by the product since
11-18 02:15Z, P0 #106).

**NO REAL SPACECRAFT-CONFIGURATION APPROVALS (director 11-18):** nobody approves a real spacecraft-configuration
activation request on Earendil (or any non-QA mission) until #235 (Activations shows what a spacecraft configuration
request changes, with the telemetry-off warning) is LIVE and qa-checked. QA-mission test requests only. END CONDITION:
qa's post-check of #235 passes and lead announces the end to all panes.

**Director GO conditions** (director, 11-18, after batch 1's step 4 + gate re-check ran late): every condition in a
director GO is copied VERBATIM into the slot's plan as a checklist; the chain owner (lead) confirms the checklist is in
the plan BEFORE the slot starts; a slot can't start with a GO condition missing from its plan. qa sends lead each slot's
GO-condition checklist ahead of the slot.

**Struct fields under a stored hash** (director, DECISIONS #108, 11-17). A commit that adds a field to a struct
reachable from a stored, recomputed hash (binding set, runtime basis, spacecraft-configuration inputs, activation
review token, authored-override fingerprint) must carry a golden-hash test showing the stored hash unchanged. At
hand-off qa runs `var/qa-scripts/struct-hash-check.sh <base> <tip>`, which looks under `packages/` as well as
`apps/` and checks domain's struct list (`var/struct-hash-checklist.md`). Every dry runs it too. On a hit, qa holds
the set until the same commit carries the hash kept stable plus a legacy-value test, or a director-approved plan.

**Every restart's post-checks** (director, 11-17) include, for EVERY active mission: the desired generation equals
the applied one, `MissionCoordinator.active_spec` answers at that generation, the reconciler's `last_error` is nil,
and the stored binding-set hash equals the recomputed one. Run `var/qa-scripts/admission-check.exs`; it must print
`ADMISSION OK`. It's needed alongside the boot checks because an admission failure retries silently: nothing is
logged at info. This matters because the restart dry can't catch it: it runs on a fresh
test database, which has no binding set stored before the change.

Why: on 11-17 the calibration restart added two default-valued keys to `%FieldDefinition{}`. The binding-set hash,
taken over the whole struct, no longer matched the stored one, and Earendil's runtime wasn't admitted. Nothing was
logged at info. It was rolled back 7 minutes later, between passes.

## Daily dev retention slot

**It is a chain item EVERY night** (lead 11-18, after the 11-18 03:00Z run was missed): the 03:00Z retention goes into each
night's chain with its own times and its own done-line in the checklist; if a night has no gap for it, the next no-pass gap.

Once a day, in a qa slot outside passes (no active contact; not within 1 h of an armed pass), on `cadence_apogee_dev`
and this stack's QuestDB only. devops samples disk before and after (qa pastes their lines into the checklist).

1. **QuestDB: keep today + 2 full days** (director). Drop older day partitions with a WALL-CLOCK `WHERE` on the
   partition day, never QuestDB's TTL: TTL counts from `MAX(observed_at)`, the spacecraft clock, so one far-future
   frame would drop every current day. Export anything an open check still needs first (`var/questdb-export-*`).
2. **identity_states: 96 h prune** (director, from 11-17; the first rows qualify ~11-18 00:05Z, because the oldest
   `first_seen_at` on dev is 11-14 00:04Z). `var/qa-scripts/identity-states-prune.sh` with its default cutoff
   (now − 96 h): `dry` (a full scan of a ~9 GB table, so slot work), then `delete`, then `vacuum` (plain VACUUM:
   it makes the space reusable and pauses growth but returns nothing to disk; no VACUUM FULL without the
   director). Run with `BATCH=1000` and `PGAPPNAME=qa-cleanup-<date>` so a deadline can `pg_cancel_backend` it;
   stop the deletes below 20.5 GiB free. The 11-16 wrapper `var/qa-scripts/cleanup-window.sh` shows the pattern
   (start-by and cancel-at per step, disk guard), but its times are hard-coded for 11-16.

Growth this slot can't stop: identity_states adds ~3.6 GB/day until domain's change (a) stops writing a state for a
first-seen canonical observation (#99).

## Tripped partition (#99 replay-safe ids)

domain's text (11-17, with #99's hand-off), as given:

#99 replay-safe ids: a TRIPPED partition. Signs: an error log line MM_REPLAY_ID_CONFLICT <kind> <id>: a different effect already holds this id (stored ..., new ...), repeating. For alarm effects, the ingress persistence projector's batch fails and is retried (cadence.telemetry.ingress.persistence_failed warnings repeat, the journal isn't acknowledged, the partition's backlog grows). For a managed action request, the partition's runtime-record write fails on every batch. It is a bug (two different effects mapped to one id, or a non-deterministic replay), never noise. qa: STOP and call domain with the log line, the mission and partition id, and the time. Do NOT delete or edit rows (alarm_episodes, alarm_episode_events, managed_action_requests, partition_stream_keys), and don't restart the partition repeatedly: the retry hits it again. Also watch for MM_REPLAY_ID_INDEX_OVERFLOW (warning; counter [:cadence, :replay_id, :index_overflow]): an input had more than 32,768 effects of one kind, so the rest got non-replay-safe ids. Not an outage; report it to domain the same day.

## Known limits

- **Live telemetry saturates the shared laptop.** On 2026-11-08, ten 1 Hz feeds plus team builds
  pushed load to ~50: ingest stalled after ~5 min (receivers timing out) and sign-in took 34 s.
  Run feeds briefly, then stop them (Ctrl-C, `a`): after short contacts end the script keeps
  reconnecting instead of exiting. Captured history: ~174k rows for EARENDIL-001…010,
  2026-11-08 22:26–22:31Z and 22:55–22:56Z; those 10 have durable current values (heard 22:55Z).
- **Live telemetry** covers EARENDIL-001…010 only; the other 490 stay `never_heard`. The feeds
  stop when their contacts end (2 h); rerun step 7. `dev/reflect_orbital_{live,activate}.exs`
  take `EARENDIL_CADENCE_NODE` (default `cadence`, i.e. the main checkout).
- **Postgres has 100 connections, and the two dev nodes hold 60.** :4011 (`cadence_apogee_dev`) and the main
  checkout (`cadence_dev`) keep 30 each. A full suite takes ~16 more, so two concurrent full suites filled it on 11-14
  05:47Z (partitions 7 and 12), during an armed window. Before a full suite, check headroom
  (`select count(*) from pg_stat_activity where backend_type='client backend'`). Start it only below ~70, and never
  inside an armed window. At the limit, a :4011 pool reconnect and qa's guard queries both fail.
- **Personas:** the env admin (`user_environment_admin`) has no Reflect Orbital membership; in
  admin mode the console selects the org from the URL (qa #15). e2e runs as `qa-org-admin`.
- **Planning drafts:** reseeding planning templates invalidates existing drafts (they disappear
  from `/contact-plans`; ux is speccing a 'superseded' state). Drafting runs a real fleet planning
  run against the simulator: do it under load 16.
- **No limits configured** in the seed, so nothing goes critical/caution on its own. Specs use
  fixtures over the real `/fleet` read (`e2e/support/fleet.ts`).
- **Ingress ports:** the Earendil seed binds delivery transports on 127.0.0.1:42100–42109. If the
  main checkout realizes contacts at the same time, one side gets `eaddrinuse`.
- **No replay of pre-identity-v2 telemetry without a decision.** Any replay_run over a range ingested before
  identity v2 shipped needs a lead or director decision first. This includes 11-14 00:38:36–00:40:40Z (001 and 009,
  collapsed 8:1 identities). A replay run always gets its own identities (realm + replay_run_id), so it never fixes or
  duplicates the live rows; it only adds its own. See `docs/apogee/plans/ingress-time-tags.md`.
- **RULE (lead, 11-14): a side worktree's `frontend/node_modules` is its OWN directory, never a symlink to the
  shared tree's.** With a symlink, vue-tsc, lint and tests resolve workspace packages (plugin-sdk, the route
  catalog) from the shared tree and test the wrong code: batch 3 showed host vue-tsc 0 errors with 10 real ones.
  Check: `test -L frontend/node_modules && echo SYMLINK`.
- **Never symlink the shared tree's `node_modules` into a throwaway worktree.** Page tests that shell out to
  `vp test` start a `pnpm install`, which tries to remove the linked modules directory. On 11-14 07:52Z pnpm refused
  (`ERR_PNPM_UNSAFE_MODULES_DIR`) and nothing changed, but don't rely on that. In a throwaway, page tests fail with
  `ERR_MODULE_NOT_FOUND` (environmental). Run them in the shared tree through check-slot once the commits are in.
- **Archive ranges written before c3680ddd9 re-archive their packets once under new ids if replayed** (dev/test data
  only). c3680ddd9 (domain, #71 (d)) makes a journaled packet's id stable across re-batching. It lands with #73's
  restart, restart 2 on 11-14.
- **A rollback target must be approved; approve it before you need it** (director, 11-15). Once the
  mission-model approval gate is live, a move can only land on an approved, qualified revision,
  and that includes moving BACK. **Post-move checklist: before closing a rollout, approve the
  previous revision as the rollback target** (a recorded approval with its comparison report, by an
  org admin who didn't import it; QA Org Admin 2 when the importer is QA Org Admin).
- **Rollback below aa7c64264 (semantic empty-start seed, domain 11-15):** once a partition has a `'seed'` commit
  (input `{:seed_monitoring, …}`), OLD code can't replay it ("unsupported input"). That only bites if that partition's
  checkpoint is also lost. Before rolling back past it, check the partition checkpoints are intact (api-ops note C).
- **Provenance B: roll FORWARD, not back** (director, 11-17, option A; DECISIONS #103). After B lands, a code
  rollback past B is a last resort. If one ever happens, there are no Data operations writes until B is rolled
  forward again: no legacy `/ops/data-operations` requests, no backfill, no late-data accept. **Before that rollback
  restart, qa checks that no such job is queued or running.** Why this is enough: dev only, no production; rows
  keep their provenance in the B columns. The one harmful path is a write-back by pre-B code (the parked legacy
  page): pre-B code reads only the residual JSON (null for packet rows), so it would re-persist such a row without
  its promoted provenance keys, losing them for good (lead's wording).
- **Replay.Diff after aa7c64264 shows timer outputs with no live counterpart over downtime:** a live clock now skips
  to now after downtime (one late tick), a replay clock keeps every tick. Expected, not divergence (api-ops note B).
- **Deploy identity v2 with a graceful stop (journal sealed), not a kill.** A crash with a persisted-but-unacked batch
  in flight re-persists it at boot under the new digest: one duplicate canonical identity per batch, once.

## Playwright

- Playwright `1.62.1`, system Chrome (`channel: "chrome"`).
- Sign-in selectors: `#user_email`, `#user_password`, `#sign-in-form button[type="submit"]`.
- Console e2e suite: `docs/apogee/qa/e2e.md`.

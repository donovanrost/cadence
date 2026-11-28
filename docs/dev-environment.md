# Per-worktree development environment

Each worktree owns a stable slot, database, QuestDB container and data directory, simulator,
Phoenix server, and console Vite server. All HTTP and database ports bind to `127.0.0.1`.
The slot registry is under `${XDG_STATE_HOME:-$HOME/.cache}/cadence/dev-slots` and is
keyed by the worktree's absolute path. Slots 1–40 are available. Port and database settings,
plus random administrator, QA persona, provider, and Erlang cookie credentials, live in the
gitignored, mode-600 `mise.local.toml` at the worktree root. No command prints the credentials.

Prerequisites: local PostgreSQL, Docker, mise,
Elixir dependencies (`mise exec -- mix workspace.run -t deps.get`), and frontend dependencies
(`cd frontend && corepack pnpm install`).

```sh
dev/stack up       # create and migrate both stores, start services, seed data
dev/stack up --no-seed     # start services without any data seeds
dev/stack seed-rest        # rerun the REST Earendil and QA seeds against a running stack
dev/stack status   # show this slot's names, ports, and process state
dev/stack down     # stop this worktree's processes and QuestDB container
dev/stack reset    # drop this worktree's DB and QuestDB data, then rebuild
dev/stack reset --no-seed  # rebuild empty stores and start services for the REST harness
dev/stack env      # create/refresh mise.local.toml and show non-secret settings
```

`mise run stack up` and the other subcommands are equivalent. Default `up` is safe to rerun.
It starts the simulator, Phoenix and the Console dev server, then runs the standalone REST
seeds in order: Earendil, QA people, planning and two QA missions. `reset` deletes only this
slot's dev data. The scripts in `dev/seed/` use HTTP sessions and the simulator's HTTP API;
they never call Cadence domain modules.

If a worktree database predates the #718 migration baseline, run `dev/stack reset`. The old
migration ledger and schema cannot be upgraded in place; the baseline reports that instruction
before applying any DDL. Recreate your own test partition after dropping its old database too.

For a fresh REST harness, use `dev/stack reset --no-seed` then `dev/stack seed-rest`.
The environment admin in `mise.local.toml` is the bootstrap credential; the client signs in
through the console. Set `EARENDIL_SPACECRAFT_COUNT` to 500 (default) or 1,000 and
`EARENDIL_SITE_COUNT` to 2–15 (default 10). Each phase prints wall time.

The Earendil seed imports and independently approves its command and telemetry catalog,
starts the simulator, provisions and syncs its provider, and probes the QuestDB dashboard
source. A second administrator accepts an invitation through the dev mailbox and approves
the fleet, its routes, and one bulk configuration review. The seed stages a profile pinned
to the catalog composition, station bindings, provider transports, spacecraft sources,
Telemetry Decom installations, configuration drafts, and orbit element sets. It imports
the six dashboards through REST with `identity: "keep"`. The QA seed accepts four people
through invitations, approves the planning policy, creates recurring templates and two
QA missions, and approves their fleets, sources, Telemetry Decom installations, and direct
route. Rerunning `seed-rest` reuses existing records. Its dynamic Earendil IDs are written
to the gitignored `var/stack/seed.ids` and `mise.local.toml` for console e2e.
Configuration approval uses groups of 250 spacecraft while #1020 removes the backend's
per-craft queries from a single 1,000-craft approval transaction.

Fresh `reset --no-seed` plus `seed-rest` measurements on the Platform worktree
(2026-11-28; totals exclude stack startup and vary with machine load):

| Spacecraft | Sites | Earendil | QA |
| ---: | ---: | ---: | ---: |
| 500 | 10 | 277.23 s | 9.43 s |
| 1,000 | 15 | 560.06 s | 13.17 s |

The 500-spacecraft run preceded concurrent per-spacecraft configuration requests and grouped
reviews. A repeat of the same fleet took 139.75 s for Earendil and 1.81 s for QA.

`mise run earendil-live` imports the shared dashboard documents and playlist through REST. Its
contact setup still uses the fixture and live contact scripts required by the scale harness.

Use `mise exec --` from anywhere under the worktree to load `mise.local.toml`, including when
running `mise run cadence`, `mise run earendil-live`, Mix tasks, and console e2e tests. The
`cadence` and `earendil-live` named nodes use the slot's private cookie and loopback Erlang
distribution interface. The simulator HTTP listener also binds loopback.

The URLs are printed by `dev/stack status`. For the console, open the Phoenix URL followed by
`/console`; Vite is an asset server. `BASE_URL` for Playwright points at that Phoenix URL.
Logs and PID files are under `var/stack/`; QuestDB data is under `var/questdb/`, and the
simulator store under `var/reflect_orbital/`. All are gitignored.

The QA personas share a random password within this worktree, loaded from
`E2E_PERSONA_PASSWORD`; the environment admin uses `CADENCE_ADMIN_PASSWORD`. Both are in
`mise.local.toml`. To rotate the personas, replace that local value and run `dev/stack reset`.
Never commit or paste values from `mise.local.toml`.

See [console e2e](apogee/qa/e2e.md) for test commands and shared-state rules. For the
simulator's provider workflow, see [Reflect Orbital demo](how-to/run-reflect-orbital-demo.md).

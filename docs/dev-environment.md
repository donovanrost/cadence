# Per-worktree development environment

Each worktree owns a stable slot, database, QuestDB container and data directory, simulator,
Phoenix server, and console Vite server. All HTTP and database ports bind to `127.0.0.1`.
The slot registry is under `${XDG_STATE_HOME:-$HOME/.cache}/cadence/dev-slots` and is
keyed by the worktree's absolute path. Slots 1–40 are available. Port and database settings,
plus random administrator, QA persona, provider, and Erlang cookie credentials, live in the
gitignored, mode-600 `mise.local.toml` at the worktree root. No command prints the credentials.

Prerequisites: PostgreSQL running locally with the repository's dev credentials, Docker, mise,
Elixir dependencies (`mise exec -- mix workspace.run -t deps.get`), and frontend dependencies
(`cd frontend && corepack pnpm install`).

```sh
dev/stack up       # create and migrate both stores, start services, seed data
dev/stack up --no-seed     # start services without any data seeds
dev/stack seed-rest        # run the REST Earendil harness against a running unseeded stack
dev/stack status   # show this slot's names, ports, and process state
dev/stack down     # stop this worktree's processes and QuestDB container
dev/stack reset    # drop this worktree's DB and QuestDB data, then rebuild
dev/stack reset --no-seed  # rebuild empty stores and start services for the REST harness
dev/stack env      # create/refresh mise.local.toml and show non-secret settings
```

`mise run stack up` and the other subcommands are equivalent. Default `up` is safe to rerun and
keeps the four existing seeds in order: Reflect Orbital demo, QA personas, Reflect Orbital
planning, QA mission. They build the complete local demo until the REST path reaches parity.
The simulator starts before those seeds, and Phoenix starts before its environment admin and
seeds. `reset` deletes only this slot's dev data.

For the REST harness, use `dev/stack reset --no-seed` then `dev/stack seed-rest`. This starts the
simulator, Phoenix, and console before the standalone REST client. The environment admin in
`mise.local.toml` is the only bootstrap credential; the client signs in through the console and
uses its session. Set `EARENDIL_SPACECRAFT_COUNT` to 500 (default) or 1000 and
`EARENDIL_SITE_COUNT` to 2–15 (default 10). It prints wall time for each phase. The client imports
the Earendil command and telemetry YAML catalog through the console upload route, starts the
simulator run over its HTTP admin API, and creates the provider account, mission grant, and mission
provider through the console API. It validates and syncs the provider, then stages the selected
ground stations, a catalog-backed spacecraft profile, and spacecraft pinned to that profile in one
change set. That change set enters independent review. Invitation delivery and a second person's
session wait on #745. Per-spacecraft configuration drafts need an applied fleet; the bulk review
path waits on #734. Orbit elements wait on #732; dashboards need an applied fleet and #745. Do not run
`seed-rest` on a database seeded by default `up`. Use `reset` when switching between the full demo
and REST harness.

Fresh `reset --no-seed` + `seed-rest` measurements on the Platform worktree (2026-11-26;
100 spacecraft per REST batch; selected phase timings; totals exclude stack startup):

| Spacecraft | Sites | Catalog import | Provider setup | Sites + profile | Fleet preview + stage | Submit for review | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 10 | 1.34 s | 0.50 s | 0.61 s | 8.78 s | 5.20 s | 19.00 s |
| 1,000 | 15 | 1.32 s | 0.50 s | 1.39 s | 18.44 s | 11.48 s | 35.81 s |

Both runs reached `in_review`; the mission's default independent approval policy prevents the
spacecraft from becoming active until #745 supplies a second person.

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
`mise.local.toml`. To rotate an existing worktree's QA password, replace that local value and
run `E2E_RESET_PERSONA_PASSWORDS=1 mise exec -- mix run --no-start
../../dev/apogee_qa_personas.exs` from `apps/cadence_web`; all their sessions are revoked.
Never commit or paste values from `mise.local.toml`.

See [console e2e](apogee/qa/e2e.md) for test commands and shared-state rules. For the
simulator's provider workflow, see [Reflect Orbital demo](how-to/run-reflect-orbital-demo.md).

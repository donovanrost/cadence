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
dev/stack status   # show this slot's names, ports, and process state
dev/stack down     # stop this worktree's processes and QuestDB container
dev/stack reset    # drop this worktree's DB and QuestDB data, then rebuild
dev/stack env      # create/refresh mise.local.toml and show non-secret settings
```

`mise run stack up` and the other subcommands are equivalent. `up` is safe to rerun. Seeds run
in this order: Reflect Orbital demo, QA personas, Reflect Orbital planning, QA mission. The
simulator starts before seeds; Phoenix starts before its environment admin and seeds. The seed
does not activate a configuration or write approvals. `reset` deletes only this slot's dev data.

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

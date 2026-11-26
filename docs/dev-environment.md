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

`mise run stack up` and the other subcommands are equivalent. `up` is safe to rerun. The
simulator and Phoenix start before the standalone REST seed client. The environment admin in
`mise.local.toml` is the only bootstrap credential; the client signs in through the console and
uses its session. Set `EARENDIL_SPACECRAFT_COUNT` to 500 (default) or 1000 and
`EARENDIL_SITE_COUNT` to 1–10. The seed prints wall time for each phase. Fleet changes enter
review; they await a second person's session and invitation delivery (#745). Site/provider and
profile configuration, orbit elements, and dashboard import await #734, #732, and #746. `reset`
deletes only this slot's dev data.

Fresh reset measurements on the Platform worktree (2026-11-25; 100 spacecraft per REST batch):

| Spacecraft | Sign-in | Org + mission | Fleet read | Preview + stage | Submit for review | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 0.16 s | 0.12 s | 0.20 s | 4.18 s | 2.94 s | 7.68 s |
| 1,000 | 0.26 s | 0.11 s | 0.15 s | 19.59 s | 5.45 s | 25.60 s |

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

The environment admin uses `CADENCE_ADMIN_EMAIL` and `CADENCE_ADMIN_PASSWORD` from
`mise.local.toml`. Never commit or paste values from that file.

See [console e2e](apogee/qa/e2e.md) for test commands and shared-state rules. For the
simulator's provider workflow, see [Reflect Orbital demo](how-to/run-reflect-orbital-demo.md).

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
dev/stack seed-rest        # run the REST Earendil and QA harness against a running unseeded stack
dev/stack status   # show this slot's names, ports, and process state
dev/stack down     # stop this worktree's processes and QuestDB container
dev/stack reset    # drop this worktree's DB and QuestDB data, then rebuild
dev/stack reset --no-seed  # rebuild empty stores and start services for the REST harness
dev/stack env      # create/refresh mise.local.toml and show non-secret settings
```

`mise run stack up` and the other subcommands are equivalent. Default `up` is safe to rerun and
keeps the four existing seeds in order: Reflect Orbital demo, QA personas, Reflect Orbital
planning, QA mission. They build the complete local demo until the REST path reaches parity.
The simulator, Phoenix and the Console dev server start before the seeds. `reset` deletes only
this slot's dev data.

The default Earendil and QA mission seeds submit their extra routes through the Console API.
Earendil includes the station bindings for its existing downlink transports in the same change
set. The QA change set includes a local test station and the direct TCP transport on it.
On missions with independent approval, the existing seeded second admin approves the route
change set through the same domain function as the Console. The seed saves the Earendil
spacecraft configurations after the routes apply. The standalone REST seed will use
a second admin's REST session for both route approvals once #745 and #752 supply that path.

After the #718 migration baseline lands, run `dev/stack reset` once in each existing worktree.
The old migration ledger and schema cannot be upgraded in place; the baseline reports that reset
instruction before applying any DDL. Recreate your own test partition after dropping its old
database as well.

For the REST harness, use `dev/stack reset --no-seed` then `dev/stack seed-rest`. This starts the
simulator, Phoenix, and console before the standalone REST client. The environment admin in
`mise.local.toml` is the only bootstrap credential; the client signs in through the console and
uses its session. Set `EARENDIL_SPACECRAFT_COUNT` to 500 (default) or 1000 and
`EARENDIL_SITE_COUNT` to 2–15 (default 10). It prints wall time for each phase. The client imports
the Earendil command and telemetry YAML catalog through the console upload route, starts the
simulator run over its HTTP admin API, and creates the provider account, mission grant, and mission
provider through the console API. It validates and syncs the provider, probes the managed QuestDB
dashboard source through the console API, then stages the selected ground stations, a catalog-backed
spacecraft profile, and spacecraft pinned to that profile in one change set. The spacecraft use the
stable IDs referenced by the six documents in `dev/seed/earendil_dashboards.exs`. That change set
enters independent review. Once the first ten
spacecraft are applied, the client imports those dashboards through `POST /dashboards` with
`identity: "keep"`; an identical rerun reuses them. Until then, it reports the #745 approval wait.
The next REST step invites the four QA personas, saves the Earendil planning policy as a draft,
and creates recurring templates for any already applied spacecraft. It creates both QA missions,
imports their candidate catalogs, and submits their profile and spacecraft change sets for review.
The first QA mission also gets its simulator provider account, grant, and mission provider.
Rerunning these steps reuses existing records and pending change sets. The missing mailbox JSON
endpoint (#745) prevents the client from accepting the invitations and using a second person's
session to approve those change sets. Source endpoints, Telemetry Decom installations, and the
QA direct route follow the approvals.
Per-spacecraft configuration
drafts need an applied fleet; the bulk review path waits on #734. Orbit elements wait on #732.
Do not run `seed-rest` on a database seeded by default `up`. Use `reset` when switching between
the full demo and REST harness.

Fresh `reset --no-seed` + `seed-rest` measurements on the Platform worktree (2026-11-26;
100 spacecraft per REST batch; totals exclude stack startup and vary with machine load):

| Spacecraft | Sites | QuestDB source probe | Dashboard phase | Total |
| ---: | ---: | ---: | ---: | ---: |
| 500 | 10 | 3.04 s | 0.04 s | 44.99 s |
| 1,000 | 15 | 0.10 s | 0.05 s | 17.67 s |

Both runs reached `in_review` and the dashboard phase reported the #745 wait. The mission's default
independent approval policy prevents the spacecraft from becoming active until #745 supplies a
second person.

Default `up` retains these direct seeds until the REST harness reaches parity:

| Direct seed step | Remaining REST work |
| --- | --- |
| `reflect_orbital_demo.exs` | Independent fleet and model approval need a second person (#745); orbital elements need #732; bulk spacecraft configuration review needs #734. |
| `apogee_qa_personas.exs` | Accept the four pending invitations and sign in the QA people through the dev mailbox (#745). |
| `reflect_orbital_planning.exs` | Create templates after the fleet applies; the policy's second-person approval needs #745. |
| `apogee_qa_mission.exs` | Approve profile and spacecraft changes, then install source endpoints and Telemetry Decom; apply the QA direct route with a second person's session (#745). |

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

Simulator downlinks use plaintext and the source allowlist by default. A local seed can enroll
an existing provider-managed binding using `Cadence.Dev.Seed.DeliveryTLS.enroll!/5` from
`dev/seed/delivery_tls.exs`, with the mission admin scope and the simulator run ID. Pass the
returned reference as `egress.delivery_credential_ref` when provisioning a downlink profile with
`delivery_auth: "mtls"`. Version the transport to pin that profile before booking. The helper uses
the operator enrollment action and stores the provider key and certificate in the private
`provider/<run id>/` directory under `CADENCE_DEV_DELIVERY_TLS_DIRECTORY`.

The QA personas share a random password within this worktree, loaded from
`E2E_PERSONA_PASSWORD`; the environment admin uses `CADENCE_ADMIN_PASSWORD`. Both are in
`mise.local.toml`. To rotate an existing worktree's QA password, replace that local value and
run `E2E_RESET_PERSONA_PASSWORDS=1 mise exec -- mix run --no-start
../../dev/apogee_qa_personas.exs` from `apps/cadence_web`; all their sessions are revoked.
Never commit or paste values from `mise.local.toml`.

See [console e2e](apogee/qa/e2e.md) for test commands and shared-state rules. For the
simulator's provider workflow, see [Reflect Orbital demo](how-to/run-reflect-orbital-demo.md).

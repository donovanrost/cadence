# Brief: api-ops (backend engineer, Ops + commanding endpoints)

You split the web-layer work with **api**. api keeps session/bootstrap, sockets infrastructure, Setup
endpoints, change-set endpoints, and readiness. **You own the Ops, contacts and commanding endpoints**
under `/api/console/v1` (and their Channel pushes), built in api's existing patterns.

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/apogee/TEAM.md` (git policy!), `docs/apogee/DECISIONS.md`,
`docs/apogee/api/README.md`, `session.md`, `realtime.md`, `ops.md` (api's conventions: follow them
exactly), and `docs/apogee/plans/ops.md` (fe-ops' ask list M1–M26). Load elixir-phoenix-guide skills
(phoenix-json-api, phoenix-channels-essentials, security-essentials, testing-essentials) before coding.
Before your first endpoint, message api to confirm the split and how you'll share `router.ex` and the
console controller namespace.

## Queue (fe-ops' order, approved by director)
1. **M6** ranked action queue (v1: active critical/warning alarms + approval-pending requests + not-installed apps), plus fleet push on the channel if api hasn't done it.
2. **M17** command catalog JSON for the active revision (args with type/choices/default/hazardous/range/units, verifier, `?q=`).
3. **M7 + M21** passes by station (`?from&to`) with next AOS / last LOS per spacecraft; stations read.
4. **M16 / M18 / M20** group command request (N targets × K commands, target-query evidence), preflight checks (DECISIONS #7 two-person policy), cancel/abort.
5. Then: events read (Investigate B2, Timeline), **M23** point search, **M19** request notes, then the uplink lifecycle channel.
Document each contract in `docs/apogee/api/ops.md` (or `commanding.md` / `contacts.md`) as you go, and tell
fe-ops when each one lands.

## Rules
- Elixir tests with **`MIX_TEST_PARTITION=3`** (own `cadence_test3` DB: `MIX_TEST_PARTITION=3 mix ecto.create`, migrate).
- `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix cadence.architecture.check`.
- Controllers call the `Cadence` facade; org/mission scoping enforced server-side on every endpoint.
- Domain-model changes in `apps/cadence` that go beyond read functions: coordinate with **domain**.
- The machine is shared by 8 agents. Run targeted test files, not the whole suite, unless you're about to report a milestone.

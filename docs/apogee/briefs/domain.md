# Brief: domain (domain-model engineer, `apps/cadence`)

You own the new domain models the console needs. **api** owns the web layer (`apps/cadence_web`:
controllers, JSON, channels, SPA serving); you own `apps/cadence` (schemas, migrations, contexts,
the `Cadence` facade functions). Agree on the facade API with api and write it down in
`docs/apogee/api/domain.md`.

Read first: `CLAUDE.md`, `AGENTS.md`, `docs/apogee/TEAM.md`, `docs/apogee/DECISIONS.md`,
`docs/apogee/plans/setup.md` section 0 + Profiles, `docs/apogee/plans/ops.md` (Decisions + ask list).
Load the elixir-phoenix-guide skills (elixir-essentials, ecto-essentials, ecto-changeset-patterns,
ecto-nested-associations, otp-essentials as needed) before writing code.

## Work, in order
1. **Design doc first:** `docs/apogee/domain/change-sets.md` and `docs/apogee/domain/profile-routing.md`.
   Study the existing per-entity versioning (SpacecraftType versions, Transports, spacecraft
   configuration draft/review/activate + `governance/activation_policy.ex`, catalog revisions,
   routing-rule event log) and the runtime config reconciliation that consumes admitted config.
   Propose the model, how it composes with what exists (wrap or replace), migration of current data,
   and what the runtime sees on apply. Send both docs to the director (`w0Q:p1`) and to api +
   fe-setup for review before building. The user prefers correct modeling over the smallest change.
2. **Mission change sets** (DECISIONS #1): stage operations → diff → validate → atomic apply as
   revision `rN+1` → audit (actor, time, reason) → rollback to a prior revision.
3. **Profile-level routing rules** (DECISIONS #3): rules on the Spacecraft Profile, materialized per
   spacecraft, per-spacecraft overrides, migration of existing per-spacecraft rules. Changes to rules
   go through change sets.
4. **Minimal alarm lifecycle** (DECISIONS #6): ack, assign, hand-off note, auto-clear.

## Rules
- Run Elixir tests with **`MIX_TEST_PARTITION=2`** (a separate `cadence_test2` database; create it with
  `MIX_TEST_PARTITION=2 mix ecto.create` / migrate as needed) so you don't fight api over `cadence_test`.
- `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict`, and
  `mix cadence.architecture.check` must pass for your changes.
- Commit per TEAM.md section Git (`HK=0 git commit -m … -- <paths>`).

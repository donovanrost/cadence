# Domain facade: mission change sets and configuration revisions

Owner: **domain**. Status: **P1 shipped** (commits `6dab1a9f`, `1a6f52a6`). Consumer: **api**.
Design: `docs/apogee/domain/change-sets.md`. api review folded in: `docs/apogee/api/domain-review.md`.

Module: **`Cadence.Control.Configuration`**. Every function takes `(scope, mission_id, ...)` and
authorizes against the mission itself, so the web layer only needs the scope.

## Conventions

- Times are `DateTime`, revision numbers are integers (api renders `rN`), and actors are
  `%{kind, id, name}`.
- Errors are tagged. Anything with details carries a map or list you can pass through as
  `error.details`.
- Mutations publish `ScopedReadUpdates` `:configuration_changed` (org, mission) after commit.
  After an apply that touched spacecraft or profiles, it also publishes
  `:spacecraft_configuration_changed`, so the existing pages refresh.

## Permissions

`permissions(scope, mission_id) :: {:ok, [String.t()]}`. The strings map to today's policy
actions until Cedar replaces them (DECISIONS #2):

| Capability | Policy action | Who today |
| --- | --- | --- |
| `config.stage` | `operate_mission` | active members |
| `config.apply` | `request_activation` | active members (services: `manage_mission`) |
| `config.review` | `approve_activation` | active human members (never services) |
| `config.rollback` | `request_activation` | (P2) |
| `config.discard_any` | `manage_mission` | organization admins |

Reads (`current`, `preview`, revisions) need `operate_mission`. Failures return
`{:error, :forbidden}`. An unknown mission returns `{:error, :mission_not_found}`.

## Reads

```elixir
current(scope, mission_id) ::
  {:ok, %{head: revision_summary, change_set: change_set | nil}}
# The staged bar plus "CONFIG r5 · 2 STAGED".

change_set(scope, mission_id, change_set_id) :: {:ok, change_set} | {:error, :change_set_not_found}

list_revisions(scope, mission_id, limit: 25, before: n) :: {:ok, [revision_summary]}   # newest first
get_revision(scope, mission_id, n) :: {:ok, revision_summary + %{entries: [entry]}} | {:error, :revision_not_found}
compare(scope, mission_id, from, to) :: {:ok, [%{kind, entity_id, revisions: [n], op, fields: [field]}]}
                                     | {:error, :invalid_range | :revision_not_found}
entity_history(scope, mission_id, kind, entity_id) :: {:ok, [entry]}                  # newest first
```

Shapes:

```elixir
revision_summary = %{revision, kind: :baseline | :change_set | :rollback | :legacy_activation,
  live: boolean, applied_at, applied_by: actor,   # whoever ran the apply: the reviewer on a reviewed set (#117)
  reason, summary, entry_count, change_set_id,
  rolls_back_to, approvals: [%{actor, comment, decided_at}], activation_id, generation}

change_set = %{id, version, state: :open | :in_review | :applied | :discarded, base_revision,
  opened_at, opened_by, staged_count, changes: [change], withdrawn: [change], authors: [actor],
  submitted_by, submitted_at, reason, approval_required: boolean | nil,
  reviews: [%{decision: :approved | :sent_back, actor, comment, decided_at}],
  failure: map | nil,           # why a reviewed set came back to :open (e.g. checks)
  applied_revision}

change = %{id, summary, author: actor, staged_at, source: map, state,
  ops: [%{id, kind, entity_id, action: :create | :update | :delete, paths: [path], payload}]}

entry = %{revision, kind, entity_id, op, paths, fields: [field], before: doc | nil, after: doc | nil}
field = %{path, before, after}
```

`r1` (`kind: :baseline`) is created the first time a mission's ledger is touched.

## Staging

```elixir
stage(scope, mission_id, %{summary: String.t(), source: map()}, [op]) ::
  {:ok, %{change_set_id, change_id, version, staged_count, base_revision, entity_ids: [id]}}

op = %{kind: "ground_station" | "transport" | "spacecraft" | "spacecraft_profile",
       action: :create | :update | :delete,
       entity_id: id,                         # required for update/delete; optional for create
       document: map(),                       # create: the full document
       changes: [%{path: "a.b", value: term}], # update: field changes
       options: map()}                        # optional; spacecraft_profile update: %{rollout: "all" | "none" | %{spacecraft: [id]}}
```

Errors (each one distinct, so fe-setup can map them to their own UI states):
- `{:error, :frozen_in_review}`: the shared set is in review (DECISIONS #13).
- `{:error, {:path_already_staged, %{change_id, author, kind, entity_id, path, value}}}`
- `{:error, {:invalid_op, index, [%{path, message}]}}`: field-level validation, or an unknown
  kind/action, or the entity no longer exists. Index 0 also covers a missing `summary`.
- `{:error, :forbidden}`

Re-staging a path you already staged replaces your earlier value. The superseded change shows
under `withdrawn`.

```elixir
withdraw(scope, mission_id, change_id) :: {:ok, %{change_set_id, version, state}}
discard(scope, mission_id, change_set_id, expected_version) ::
  {:ok, %{change_set_id, version, state, discarded, remaining}}   # set closes when remaining == 0
rebase(scope, mission_id, op_id, :keep_mine | :take_live) :: {:ok, %{change_set_id, version, state}}
```

Errors: `:change_set_not_found`, `:change_not_found`, `:op_not_found`, `:change_set_changed`,
`:frozen_in_review`, `:entity_gone`, `:forbidden`. Withdraw and discard act on your own changes,
or on anyone's with `config.discard_any`.

## Preview (dry run, nothing written)

```elixir
preview(scope, mission_id, change_set_id | {:ops, [op]}) :: {:ok, preview} | {:error, term}

preview = %{verdict: :go | :hold | :no_go,
  checks: [%{key: "validation" | "conflicts", verdict, items: [item]}],
  effects: [%{op_id, changes: n, keeps: [%{spacecraft: %{id, name}, reason}]}],
  diffs: [%{op_id, change_id, kind, entity_id, action, fields: [field]}]}

# conflicts item:
%{op_id, change_id, kind, entity_id, reason: :value_changed | :entity_gone | :entity_exists,
  paths: [%{path, base, live, staged, changed_in: n | :outside}]}
# validation item:
%{op_id, change_id, kind, entity_id, errors: [%{path, message}]}
```

`changed_in: :outside` means the live value changed outside any change set (for example on a
legacy page). The UI says "changed outside a change set". `{:ops, ops}` previews unstaged edits,
which is the Profile P4 aside ("changes N · keeps M"). P1 checks are validation and conflicts.
Readiness-after, in-flight and compatibility checks arrive in P2.

## Submit and review

```elixir
submit(scope, mission_id, change_set_id, %{reason: String.t(),        # 10..2000 bytes
                                           expected_version: integer,
                                           acknowledged_holds: boolean})
review(scope, mission_id, change_set_id, :approve | :send_back,
       %{comment: String.t(), expected_version: integer})

# results
{:ok, %{state: :applied, change_set_id, revision: n, staged_count, activation_id: nil | id,
        generation: nil | n, runtime: :not_applicable | :converging | :applied | :degraded,
        degraded_partitions: []}}
{:ok, %{state: :in_review, change_set_id, version}}     # independent approval required
{:ok, %{state: :open, change_set_id, version}}          # sent back
```

Errors:
- `:reason_required`, `:comment_required`, `:change_set_changed`, `:change_set_not_found`,
  `:frozen_in_review`, `:not_in_review`, `:nothing_staged`
- `{:checks_failed, preview}`: NO-GO. Nothing changed. A reviewed set goes back to `:open` with
  `failure` set.
- `{:holds_not_acknowledged, preview}`
- `:reviewer_is_author`: the reviewer is the submitter or authored any change (DECISIONS #14).
- `:activation_policy_changed`: the approval policy changed since submit. The set reopens.
- `:forbidden`

The approval requirement is the mission's ADR-004 policy (`direct` → submit applies at once;
`independent` → `:in_review`). In P1 no kind changes the runtime generation, so `runtime` is
`:not_applicable` and `activation_id` / `generation` are nil.

## Live topics (Phoenix.PubSub `Cadence.PubSub`)

| Topic | Message | When |
| --- | --- | --- |
| `Control.Configuration.progress_topic(set_id)` = `"change-sets:<id>"` | `{:change_set_progress, set_id, %{key, label, state: :running \| :done \| :failed, at}}` | apply steps `validate`, `write_config`, `notify_runtime`, `verify` |
| `Control.Configuration.runtime_topic(org, mission)` = `"config:<org>:<mission>"` | `{:config_runtime, %{revision, activation_id, generation, runtime, degraded_partitions}}` | after an apply (and again when the runtime settles, once generations are produced in P2) |
| `read-updates:configuration_changed:<org>:<mission>` | `{:configuration_changed, org, mission}` | after every mutation |

P1 applies run synchronously, so a client that reconnects after an apply can read the final state
from `current/2` (the set is closed and the head moved). Persisted step history is not kept.

## P2 additions: profile routing and overrides (commits `5360c974`, `d400294d`)

**Kinds and documents**
- `ground_station`: adds `"code"`, 2–8 capitals or digits (`SVB`), unique per mission.
  Existing stations were backfilled from their names.
- `transport`: adds `"ground_station_id"`, the station the transport reaches. It was
  backfilled from metadata.
- `spacecraft_profile`: adds `"catalog_revision_id"` and `"routing_rules"`. Each rule is
  `%{"id", "label", "name_template", "enabled", "stations" => [%{"ground_station_id",
  "transport_id" | nil}], "legs" => [%{"direction" => "downlink" | "uplink", "role"}]}`. The
  name-template tokens are `{station}` (code), `{station_name}`, `{spacecraft}`, `{scid}` and
  `{direction}`. Edit rules as one change at path `"routing_rules"` (the whole list). Rollout
  works as for other profile edits.
- **new** `spacecraft_override` (entity = spacecraft, `update` only). Change paths are override
  paths with `.` written as `/`: `"frame_parameters/frame_size"`,
  `"routing/<rule_id>/excluded_stations"` (list of station ids), `"routing/<rule_id>/enabled"`.
  The value `%{"value" => term, "reason" => text}` sets an override; `nil` resets it to the
  profile.
- **derived** `spacecraft_routes`: never staged. After every apply (and in previews), affected
  spacecraft's routes are re-materialized. They show up as revision entries and diffs with
  `kind: "spacecraft_routes"` (`%{"routes" => [%{"id", "name", "rule", "station", "leg",
  "transport", "role"}]}`). If a rule can't be materialized (unknown station, no or ambiguous
  transport, wrong direction), the run is a NO-GO with a validation item of kind
  `"spacecraft_routes"`.

**Reads (`Cadence.Reads.ProfileRouting`, callers authorize first)**
```elixir
rules(org_id, mission_id, %SpacecraftType{}) :: [%{id, label, name_template, enabled,
  stations: [%{id, code, name, transport_id}], legs: [%{direction, role}],
  route_count, samples: [String.t()]}]          # counts/samples: spacecraft on the current version
overrides(org_id, mission_id, %SpacecraftType{}) :: [%{spacecraft: %{id, name}, section,
  path, profile_value, spacecraft_value, reason, since_revision | nil, set_at, actor, redundant}]
```
These fill the `rules` / `overrides` placeholders in `Cadence.Reads.ProfileDetail`. When
present, `routing_model` becomes `:profile`.

Not yet: lifting legacy per-spacecraft rules into profile rules (a reviewable change set), and
profile framing feeding ingress (the next P2 steps).

## Framing generations (DECISIONS #33/#35/#36, commit `fbbeba63`, flag default off)

- **Flag:** `Cadence.Platform.ConfigurationSettings.profile_framing_generations?(org, mission)` /
  `put_profile_framing_generations(org, mission, boolean, %{id, name})` (scoped settings
  section `cadence.configuration`). Keep it off until fe-setup shows the HOLD and qa verifies one
  framing change end to end on the simulator.
- **With the flag on**, an apply that changes a configured spacecraft's effective profile
  framing (by re-pinning it, editing the profile with rollout, or a framing override):
  - produces generation N+1 in the same transaction. A rejection means nothing was applied.
  - returns `activation_id`, `generation` and `runtime: :applied | :degraded`, and broadcasts
    them on the runtime topic. `:converging` is the transient state while the apply runs.
- **Preview:** `checks[key: "compatibility"]` has `verdict: :hold` with items
  `%{op_id: nil, kind: "spacecraft_profile", entity_id: profile_id, reason: :framing_mismatch,
  spacecraft_count, profile_value: %{path, value}, transport_value: %{transport: %{id, name},
  path, value}, sentence}`. `submit` needs `acknowledged_holds: true` when the verdict is `:hold`.
- **Catalog** (#65, `domain/catalog-generations.md`): a `catalog_revision_id` change (profile or
  override) produces a generation like framing: the apply derives each moved spacecraft's
  configuration with the new catalog, rebuilds the binding set and cancels commands not yet
  released on them. All of a set's ops apply as ONE generation, with one compatibility check
  covering every touched spacecraft. Preview items: `catalog_change` (`from`, `to`, spacecraft,
  sentence with `rev N`), `catalog_cancels_commands`, and blocking `catalog_command_in_flight`
  and `catalog_configuration_pending`. A profile op moves only the spacecraft its `rollout`
  moves (`"all"` = those pinned to the current version); a spacecraft whose override sets its
  own `catalog_revision_id` keeps it.
- **Decode:** only entries marked `framing_authority: "profile"` decode with profile framing;
  every other source keeps the transport's ingress metadata.

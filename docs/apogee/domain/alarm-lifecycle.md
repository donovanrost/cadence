# Minimal alarm lifecycle (DECISIONS #6)

Owner: **domain**. Status: **draft 2, decided** (2026-11-08; DECISIONS #17: both sources labeled, escalation clears ack, assign any mission member; live ground-limit evaluation later). **Built** (commit `b2ba4d8c`; facade contract `docs/apogee/api/alarms.md`). Placement as built: episodes/sources/hooks/lifecycle in `L/alarms/` (telemetry, data plane; organization filled by DB trigger), operator facade `Cadence.Control.Alarms` (control plane), console read `Cadence.Reads.AlarmEpisodes`. `semantic_alarm_acknowledgements` not dropped yet (still unused). Reviewers: director, api, fe-ops.
Screens: Investigate (J2: Acknowledge / Assign), Mobile (J6: Acknowledge / Hand off), Now action
queue. Scope: ack, assign, hand-off note, auto-clear when back in limits. Not in scope: shelving,
suppression, escalation timers, paging. `L` = `apps/cadence/lib/cadence`.

## 0. Summary

- A new **alarm episode** is one excursion of one subject out of limits, from the first crossing
  until it returns to normal. Ack, assignee and notes attach to the episode, not to a sample or a
  point.
- Episodes open, escalate and **auto-clear inside the same transaction that records the
  transition**, so they can't drift from the state they describe.
- **Two sources feed episodes, and today's code has both:**
  1. **Catalog monitoring** (XTCE alarms → `MonitoringPlan`). This is evaluated **live in the
     runtime partitions** and persisted with real transitions
     (`semantic_alarm_transitions`, `semantic_latest_alarm_states`). It even has an
     acknowledgement table that nothing calls.
  2. **Ground limits** (the Limits & Alarming app, `governed_limit_definitions` →
     `telemetry_latest_limit_states`; **retiring with #452**: no reader of Fleet, the point
     conditions, the alarm list or the dashboards limits source reads it any more, #451 T3).
     This is **batch-only** today: the state is written by
     evaluation/refresh jobs (`telemetry_limit_evaluation`, `telemetry_latest_limit_state_refresh`),
     not per sample. It is also what `Reads.Alarms` and the Ops alarm page show.
- **Decision needed (director/fe-ops):** the Now/Investigate "alarm" should be an episode from
  either source, labeled by source. I recommend both. Ground-limit episodes are only as timely as
  their evaluation jobs until ground limits are evaluated live, and the UI must not imply otherwise.

## 1. Model

```
alarm_episodes
  episode_id PK, org, mission, spacecraft_id NULL (mission-scope subjects),
  source        catalog_monitoring | ground_limit
  subject_key   catalog: "<parameter_id>/<policy_id>"   ground: "<point_id>"
  parameter_ref (parameter_id or point_id, point_name)
  severity      current normalized: caution | critical     (+ source_state raw, e.g. "distress", "red_high")
  peak_severity
  state         active | cleared
  opened_at, opened_by_ref (transition_id | limit_event_id), first_value
  cleared_at NULL, cleared_by_ref NULL, cleared_unacknowledged boolean
  acknowledged_at NULL, acknowledged_by (actor doc) NULL
  assignee_user_id NULL, assigned_at NULL
  last_value, last_evaluated_at
  partial unique (mission_id, spacecraft_scope_id, source, subject_key) WHERE state = 'active'

alarm_episode_events          (append-only audit, the Investigate event log)
  event_id PK, episode_id FK, org, mission, kind, actor (doc) NULL, at, payload
  kind: raised | escalated | deescalated | acknowledged | assigned | unassigned | note | handed_off | cleared | rule_changed
```

**Severity mapping**, kept as the source value plus a normalized value:
- catalog `watch | warning` → `caution`; `distress | critical | severe` → `critical`
- ground `yellow_*` → `caution`; `red_*` → `critical`
- `unknown`, `disabled`, ground `blue` → no episode change. Staleness is not an alarm; ops shows
  it separately.

**Derived operator status** (what the UI tags):
- `active + unacknowledged` → **New**
- `active + acknowledged` → **Acknowledged** (with assignee if set)
- `cleared` → **Cleared**, with "cleared before anyone acknowledged" when `cleared_unacknowledged`

Per DECISIONS #6, auto-clear does not wait for an ack. Clearing is recorded, and the unacked fact
is kept for the shift report.

## 2. Transitions (hooks)

All of this lives in `Cadence.Alarms.Episodes.record/2`, a pure-ish function that takes the
previous and next subject state and returns Multi steps.

| Previous → next | Effect |
| --- | --- |
| normal (or none) → alarm | open an episode (`raised`, first value, opened_at = sample generation time or receipt time) |
| alarm → higher severity | `escalated`, update severity/peak. **Escalation clears the ack** (an acknowledged caution that turns critical is New again) |
| alarm → lower non-normal severity | `deescalated`; the ack is kept |
| the rules in force on the parameter change while the episode is open (#451) | `rule_changed`, once per (episode, rule ids, digest pair); the episode is untouched |
| alarm → normal | `cleared`, state = cleared (auto-clear) |
| the rule is turned off for the spacecraft (a disabled override, #451) | `cleared` with cause `rule_disabled`, when the policy's state becomes `disabled` |
| a generation drops the rule that raised it (#451) | `cleared` with cause `rule_retired`, once per episode when the generation is applied; its latest alarm state is removed |
| alarm → alarm, same severity | update last_value / last_evaluated_at only (no event) |

**Hook points (same transaction as the source write):**
- **Catalog monitoring:** `SemanticObservations.persist_many` → `add_transition`
  (`L/semantic_observations.ex:157-186`). The transition row already carries `from_state` and
  `to_state`, so the episode steps are appended to the same Multi. Cost: writes happen only on
  transitions, not per sample.
- **Ground limits:**
  - `Limits.Store.persist_latest_state` (`L/limits/store.ex:180-198`), comparing `existing.violation`
    and state with the new event. It is inside the evaluation run's Multi.
  - `Store.replace_latest_states` (projection rebuild/refresh, `L/limits/store.ex:138-157`) deletes
    and reinserts with no transition semantics. It gets a reconcile step: open episodes for
    violating subjects that have none, and clear active episodes whose subject is now normal or
    gone (`cleared_by_ref: :reconcile`).
- After commit: `Alarms.Facts.publish` (`{:cadence, :alarms, :facts}`) and
  `ScopedReadUpdates.publish(:alarms_changed, …)`. api relays these on the console channel.

**Back-dated samples:** if a sample older than `opened_at` or `last_evaluated_at` arrives, the
episode ignores it. The latest-state upsert already only moves forward
(`L/semantic_observations.ex:201-223`).

## 3. Commands

| Function | Rules |
| --- | --- |
| `acknowledge(scope, episode_id, note \\ nil)` | `active` only; idempotent (a second ack returns the existing one). Event `acknowledged` (+ `note` if given). |
| `assign(scope, episode_id, user_id \| nil, note \\ nil)` | `active` only. Assignee must be an active member of the org with access to the mission (identity check). `nil` unassigns. Assigning does **not** imply ack. |
| `hand_off(scope, episode_id, %{to: user_id \| nil, note})` | `note` required (1..2000). Assigns to `to` (or leaves it unassigned for "next shift") and writes a `handed_off` event with the note. This is Mobile's "Hand off". |
| `add_note(scope, episode_id, note)` | Any state, including cleared (post-mortem notes). |

Authorization: users only (no service identities), via the `operate_mission` policy action. They
are exposed as capabilities `alarm.acknowledge`, `alarm.assign` in the session bootstrap. All
commands run under `SELECT … FOR UPDATE` on the episode row, so they serialize with a concurrent
clear: a stale ack against a cleared episode returns `{:error, :episode_cleared}`, and the UI says
so.

The existing `semantic_alarm_acknowledgements` table (keyed by transition, never called) is
superseded. Episodes are the ack target. I'll drop it in the same migration if it is still empty
everywhere; it has no callers.

## 4. Reads (for api)

- `list_episodes(scope, %{state, severity, spacecraft_id, source, assignee, page})`: Now action
  queue (critical New first, then caution New, then Acknowledged by recency), Investigate list, M9
  (`?spacecraft_id=&state=active`).
- `get_episode(scope, id)`:
  - episode + events (B2 event log)
  - first crossed (`opened_at`, `first_value`)
  - limit/threshold context: definition for ground limits, policy for catalog
- `summary(scope)`: counts by severity × status for the rail and Now tiles.

**Episode row shape** (one fetch renders the list; fe-ops):
`%{id, source, status: new | acknowledged | cleared, cleared_unacknowledged, severity,
peak_severity, source_state, opened_at, cleared_at, last_value, last_evaluated_at,
spacecraft: %{id, name, scid} | nil, point: %{id, name, unit}, thresholds: %{red_low, yellow_low,
yellow_high, red_high} | catalog policy summary, acknowledged_by: actor | nil,
assignee: %{id, name} | nil}`. Ground-limit rows always carry `last_evaluated_at` (the UI says
"evaluated 3m ago" and never implies live). On escalation, the `escalated` event is written
**before** the ack is cleared, so the log shows why the episode is New again.

The legacy alarm pages and `Reads.LimitAlarmConditions` are deleted (#1075); the console reads
episodes.

## 5. Placement and migration

- `L/alarms/` (`Cadence.Alarms`, `Cadence.Alarms.Episodes`, rows), classified as **telemetry
  context, data plane** (new entries in `@context_paths` and `@domain_plane_paths`). The callers in
  `limits/` and `semantic_observations/` are in the same context and plane. The row-guard owner
  list gets `alarms/`.
- Reads in `L/reads/alarms/episodes.ex` (read_models).
- **Backfill:** a migration-time task opens episodes for subjects currently in alarm.
  - catalog: `semantic_latest_alarm_states` with a non-normal effective state, opened_at from the
    latest transition into that state;
  - ground: `telemetry_latest_limit_states` with `violation = true`.

  Nothing is marked acknowledged, so the first shift sees them as New. That is honest, because
  nobody has acknowledged them.

## 6. Open questions

- **director / fe-ops:** both sources (recommended), or only one? If only one, which one: catalog
  is live; ground limits are what today's Ops alarm page shows.
- **director:** "escalation clears the ack" is standard practice (ISA-18.2-style). OK?
- **fe-ops:** Does J2 need "assign to me" only, or any member? The model supports any member.
- **api:** channel payload = the episode read shape + event kind. OK?

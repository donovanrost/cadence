# Flight events: a source for the Now queue

Owner: **api-ops**. Reviewer: **domain** (model). Status: **v1 (form a) built** (a02c2cee hook,
1b3be7f7 queue items, e07969bb EventLog), approved by domain with the notes folded in below
(BACKLOG f20fcad0). How it was built: §3a.
The console wires the rows after (fe-ops). Ranking: ux U11. Queue contract: api/ops.md (action queue).

## 1. What a flight event is

Something the **spacecraft itself reports** as a discrete occurrence: "I entered SAFE mode", "the
star tracker lost lock", "the watchdog reset the OBC". This is different from an alarm on a numeric
value crossing a limit (VBAT below 24 V). U11 puts "a critical flight event (safe mode)" in P1, next
to critical alarms. U13 counts flight-event criticals even when ground limits aren't configured.

There are two forms in real missions:

- **(a) A state the spacecraft reports in telemetry.** An enumerated or boolean parameter
  (`MODE = SAFE`, `WDT_RESET = true`) that the catalog marks as alarming. XTCE models this as an
  `EnumerationAlarm` on the parameter's type.
- **(b) An onboard event message.** An EVS-style event packet: app, event id, type
  (`DEBUG | INFO | ERROR | CRITICAL`) and message text, for example a cFS EVS long event packet.

## 2. What exists today

- **(a) is already decoded and evaluated live, but filed as an alarm.**
  - The XTCE 1.3 importer turns `EnumerationAlarm` into `%{kind: :enumerated, values, severity}`
    rules (`Catalog.Importers.Xtce13.Translator.alarm_rules/1`).
  - `SemanticRuntime.MonitoringEvaluator` evaluates enumerated, boolean and string rules per sample
    in the runtime partitions.
  - A transition opens a `catalog_monitoring` alarm episode (`Alarms.Sources.catalog/3`, DECISIONS
    #17). With the catalog's alarm level, `distress | critical | severe` → `critical`.
  - So a catalog with `MODE: SAFE → critical` already puts the spacecraft in the Now queue today, as
    a P1 **`alarm`** row worded as a limit ("MODE · critical"). It isn't worded as an event, and the
    episode doesn't record which rule kind matched.
- **(b) doesn't exist.**
  - No importer reads an event packet definition, nothing decodes event messages, there's no store,
    and the simulator emits none.
  - The `flight_events` data binding (`DataSources.default_flight_events_binding/0`, dataset
    `mission_events`) is the ground mission-events timeline, not spacecraft events.
- **A misnomer to fix:** `Reads.EventLog` classifies every timeline entry in the `:health` category
  as `flight_event`.
  - Limit events are caught earlier and become `limit`, so what's left under `:health` is
    data-source and source-credential events. Those are ground housekeeping (`data`), not flight
    events.
  - Timeline and Investigate B2 therefore show ground events under "Flight event" today.
  - Proposal: map `:health` (non-limit) to `data`. That's a vocabulary change for fe-ops, so I'll
    send it to them first.

## 3. Proposal

**v1: form (a), from the episodes we already have. No new store.**

- **Classify.** A `catalog_monitoring` episode whose matched rule is `enumerated`, `boolean` or
  `string` is a flight event. One whose rule is `comparison` or `range` stays an alarm.
  - Domain change, small: at write time, `Alarms.Sources.catalog/3` records in the episode
    `context` the matched rule's `"rule_kind"` (a stable string: `enumerated | boolean | string |
    comparison | range`) and `"rule_id"`, so Investigate can show which rule fired. The evaluator
    already knows which rules matched.
  - Write time, not read time (domain): the monitoring plan changes under catalog generations
    (#65), so classifying against today's plan would misfile episodes opened under an older one.
  - Episodes opened before the change have no `rule_kind`. Fall back to the value's type: a
    non-numeric `last_value` → flight event. Known gap: an enumerated rule evaluated on raw codes
    (numeric `last_value`) is filed as an alarm. That's acceptable, because those episodes are
    short-lived.
  - Rule kind is a proxy and misfiles both ways: an enumerated ground-ish status reads as a flight
    event, and a numeric reset counter doesn't. Later: an explicit parameter-level override in the
    catalog (`flight_state: true | false`, e.g. from XTCE `AncillaryData`). v1 doesn't wait for it.
  - Ground limits are numeric by construction, so `ground_limit` episodes are always alarms.
- **Queue item.**
  - `kind: "flight_event"`, everything else as alarm items: same member shape, `episode_id`, ack
    state and assignee. So Acknowledge, Assign and the U21 "ACK <name>" work unchanged.
  - Title: `<SPACECRAFT> · <PARAM> <VALUE>` (`EARENDIL-001 · MODE SAFE`). Evidence: "Entered SAFE
    at 02:08:11Z". The time is the triggering sample's generation time (spacecraft time),
    recorded in the episode `context` (`"entered_at"`) next to `rule_kind`. It isn't `opened_at`,
    because with a backfill or a late pass `opened_at` can be hours after the spacecraft entered
    SAFE. Episodes from before the change fall back to `opened_at`.
  - Target: Investigate with `?alarm=<episode_id>`, as alarm rows.
- **Dedupe.** The episode already is the dedupe: one active episode per `(mission, spacecraft,
  source, parameter/policy)` (the partial unique index).
  - Repeats of the same state while active don't open new rows.
  - A different alarmed state on the same parameter escalates or de-escalates the same episode.
  - Grouping across spacecraft (U11 "identical causes"): `{severity, qualified parameter name,
    value}`, so "3 spacecraft · MODE SAFE" is one row with three members, like alarm groups. The key
    uses the qualified name, not the semantic id, because fleets on different catalog revisions
    (#65) have different ids for the same MODE.
  - Episodes are per spacecraft, so cross-spacecraft bleed (#38) can't happen here.
- **Resolution.**
  - The row clears when the episode clears: the parameter leaves the alarmed state for
    `minConsecutiveValuesToLeaveAlarm` samples. That's the auto-clear of the alarm lifecycle
    (DECISIONS #6).
  - Acknowledge keeps the row, sorted last in its priority (U21). Clearing removes it, with the
    usual fade-out.
  - Staleness doesn't clear it. A spacecraft that went quiet in SAFE stays in SAFE.
- **Ranking (U11).**
  - `critical` → **P1**; `caution` (catalog `watch | warning`) → **P2**.
  - Within a priority, flight events rank with alarms on the same keys: unacknowledged first, then
    `due_at` (null until D1/M7), then oldest `since`.
  - At otherwise equal keys, a flight event goes before a numeric alarm, as a pure tiebreak (domain
    OK). A mode change usually explains the limit alarms that follow it. True ties are rare, since
    `since` is a key. Putting all flight events ahead of alarms within the same priority and ack
    state would be a stronger rule, and that's ux's call. It isn't proposed here.
- **Counts.** Flight-event criticals count in `counts.spacecraft_p1` and in the Now Critical tile
  even when ground limits aren't configured (U13). They come from catalog monitoring, so they
  never had the ground-limits gap.
- **Wire.** Additive only: a new `kind` value, and on items an `event: {parameter, value,
  entered_at}`, `null` on other kinds. fe-ops gets the shape diff before anything ships.

### 3a. As built (domain-approved)

- **Where the rule is found.** Not on `MonitoringResult`: anything added to the Result changes
  every stored commit's `result_term` and breaks `verify_replay`, and it feeds the hashed
  evaluation document (docs/apogee/domain/semantic-runtime-replay.md). Not in
  `semantic_observations` either: fetching the plan there is a data → management plane call.
- **Instead,** the partition owner computes `SemanticRuntime.AlarmRules.for_result/2` from the
  producing generation's `runtime_plans` (monitoring only) for transitions into an alarm state, as
  `%{{policy_id, update_id} => %{kind, id, label}}`. The map travels beside
  `observation_context` on the prepared result, never in the Result, the commit or a hash, on all
  three paths: ingress, live timers, and re-projection on recovery
  (`Persistence.persist_semantic_timer_result`). Recovered commits are scoped by
  `runtime_basis_sha256`, so they get the plan they were evaluated under.
- `MonitoringEvaluator.matched_rule/3` is pure. The worst matching rule by severity; `nil` when
  the context is ambiguous (an unnamed context, or two contexts with the same name).
  - `rule_id` = `"rule:"` + the first 16 hex of the sha256 of the canonical rule (key order and
    atom/string keys don't change it).
  - `rule_label` = `"<context or default>#<index>"`.
- `Alarms.Sources.catalog/4` writes `rule_kind`, `rule_id` and `rule_label` into the episode
  `context`.
- `entered_at` is the episode's `opened_at`: that is already the triggering sample's generation
  time (spacecraft time), so no separate `"entered_at"` key is written.

**Later: form (b), onboard event messages.** It needs a model, so this is a separate review.

- **Catalog:** an event-packet definition (app, event id, type and text fields; cFS EVS layout as
  the first preset), plus a severity map (`CRITICAL` → critical, `ERROR` → caution, `INFO | DEBUG`
  → timeline only).
- **Store:** `flight_events`, append-only, one row per spacecraft event.
  - Idempotency key `(spacecraft, generation_time, app, event_id, packet sequence count)`, because
    the same packet arrives again through retransmission, a second station or a backfill. The
    sequence count is in the key so two events in the same tick don't collide (domain).
  - Rate dedupe for the queue: one row per `(spacecraft, app, event_id)` while unacknowledged, with
    `count` and `last_at`.
- **Resolution:** events don't clear. A row resolves on acknowledgement, or when an operator marks
  it handled; nothing ages out silently.
- **Correlation:** a SAFE-mode transition (a) and the `CRITICAL` event that announced it (b) are
  two rows in this design. Correlating them (same spacecraft, within N s) is a follow-up, once
  real event traffic shows what's useful.

## 4. Questions for domain (answered; domain's review)

Answers: (1) record at the hook, with `rule_id`; (2) rule kind is the v1 default, with a catalog
override later; (3) OK as a pure tiebreak; (4) (b) is later, and domain reviews its model when it
comes. Domain also agreed that `EventLog` `:health` → `data` fixes a misnomer.
The original questions:


1. **Classification:** is recording `rule_kind` in the episode `context` at the catalog hook OK, or
   would you rather classify from the monitoring plan at read time?
2. Is a `catalog_monitoring` episode on an enumerated, boolean or string rule the right definition
   of a v1 flight event, or should the catalog mark flight-state parameters explicitly (an
   annotation on the parameter)?
3. **Order:** OK to rank flight events before numeric alarms at equal keys?
4. **Scope:** is (b) a later roadmap item, or does a mission need it now? If now, which packet
   layout?

For director and fe-ops: the `EventLog` `:health` → `data` fix (§2), and whether `alarm` rows that
become `flight_event` rows need their own words (ux).

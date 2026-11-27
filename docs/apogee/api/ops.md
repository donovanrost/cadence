# Ops endpoints (Now, Investigate, Contacts, Command)

Owner: **api-ops** (from 2026-11-08, DECISIONS #21); api built the first four endpoints below.
Conventions: [README.md](README.md). Asks are tracked by their IDs in `docs/apogee/plans/ops.md`.

**Handover (api → api-ops):** M1–M3, M5, M9, M10 and M11 are implemented and tested. Still open from
the threads: point `unit`/`description` on M9 and M10 (ux, fe-ops, via the M23 catalog join); the
`fleet` channel push (shape in realtime.md, with fe-ops' seq/counts/full-row comments); and an
events read for Investigate B2 and Timeline. The `LimitTransitions` relay (`alarms` invalidations)
is yours too.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M1 M2 M3 M5 | `GET /missions/:mission_id/fleet` | **implemented** |
| M9 | `GET /missions/:mission_id/alarms` | **implemented** |
| M10 | `GET /missions/:mission_id/telemetry/points/:point_id/history` | **implemented** |
| M11 | `GET /missions/:mission_id/limits/points/:point_id/intervals` | **implemented** |
| M6 | `GET /missions/:mission_id/action-queue` | **implemented** (api-ops) |
| M8 | channel events: see [realtime.md](realtime.md) | `invalidate` and `fleet` push live |
| shell | `GET /missions/:mission_id/counts` (lead) | **implemented** |
| M17 | `GET /missions/:mission_id/commands[/:command_id]`: see [commanding.md](commanding.md) | **implemented** |

## `GET /api/v1/missions/:mission_id/fleet`

The fleet's operational state, one row per spacecraft, with the Now stat-strip counts.
Refetch on `invalidate` with `alarms`, `spacecraft` or `commanding` (and `telemetry` if you show
freshness to the second; at 1 Hz feeds, throttle that to about 10 s client-side).

```json
{
  "data": {
    "observed_at": "2026-11-08T02:41:17Z",
    "stale_after_s": 900,
    "telemetry": "ok",
    "last_received_at": "2026-11-08T02:41:15Z",
    "counts": {
      "total": 500, "critical": 3, "caution": 14, "stale": 12, "nominal": 471,
      "never_heard": 0, "fresh": 488,
      "in_contact": 4, "passes_next_2h": 31, "critical_delta_1h": null
    },
    "commands": {
      "queued": 23, "in_flight": 0, "failed": 0,
      "approval_pending": 2, "awaiting_viewer": 2
    },
    "limits": {"configured": true},
    "spacecraft": [
      {
        "id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312,
        "profile": {"id": "…", "name": "Reflector bus", "version": 1},
        "plane": 13, "slot": 12, "phase_deg": 167.04, "operational_phase": "routine",
        "state": "critical",
        "limit_state": "critical",
        "violating_points": 1,
        "worst_point": {
          "point_id": "…", "point_name": "VBAT", "value": 23.1,
          "limit_state": "critical", "raw_limit_state": "red_low",
          "received_at": "2026-11-08T02:41:15Z"
        },
        "last_received_at": "2026-11-08T02:41:15Z",
        "stale": false,
        "in_contact": false,
        "next_aos_at": "2026-11-08T03:12:00Z",
        "last_los_at": "2026-11-08T01:39:00Z"
      }
    ]
  }
}
```

### Semantics

- `telemetry`: `ok`, or `degraded` when the durable history store (QuestDB) didn't answer within
  3 s (`config :cadence, :fleet_durable_receipts_timeout_ms`). The read still answers, with
  freshness taken from live values and limit states only, so a spacecraft not heard since the last
  restart can read `never_heard`. Say "Telemetry history unavailable: freshness may be incomplete".
  The same timeout protects `GET /spacecraft` and the spacecraft detail, which read the same
  receipts.

- `state`: `critical | caution | stale | nominal | never_heard`. It is the spacecraft's worst
  condition, in precedence order critical > caution > stale > nominal. `never_heard` means
  nothing was ever received. The five `counts` of these partition `total`.
- `limit_state`: `critical | caution | nominal | no_data`, from the latest limit evaluation of
  each point (`red` = critical, `yellow` = caution, `green`/`blue` = nominal). A critical
  spacecraft stays critical even when its data is stale, because the last known condition was
  critical. `stale` is still `true` on that row, so you can show both.
- `last_received_at`: the newest receipt time across the spacecraft's current telemetry values,
  limit evaluations and the **durable history store** (U15). Once heard, a spacecraft stays
  heard across restarts; it can only be fresh or stale. `stale` = `now − last_received_at > stale_after_s` (server-decided, U9).
- `counts.fresh`: spacecraft heard within `stale_after_s` (the "TLM FRESH 488/500" meta).
- `worst_point`: the most severe violating point, newest first among equals. It is `null` when
  nothing violates.
- `plane`, `slot`, `phase_deg` (from `metadata.orbit.mean_anomaly_deg`) and `operational_phase`
  come from spacecraft metadata until domain makes them first-class. Any of them may be `null`;
  apply U8 for the matrix shape.
- `profile` is `null` when the spacecraft has no profile. `profile.name` may be `null` if the
  profile was deleted.
- `commands.queued` counts queued plus release-pending requests. `commands.in_flight` counts
  released requests awaiting verification. `commands.failed` counts failed or indeterminate
  requests. `commands.approval_pending` and `awaiting_viewer` count **decisions**: a standalone
  approval-pending request is one, and a command group waiting for its second GO is one however
  many members it has. `awaiting_viewer` is the viewer's share ("await your GO", U11): requests
  they didn't make, and groups where they're an eligible approver (not the requester, and the
  named approver if one was picked).
- `limits.configured`: `false` when the mission has no limit definitions. Show the P3 "Limits &
  Alarming not configured" item and treat `limit_state` as `no_data`.
- **Contact facts** (M7) come from **booked provider reservations** (see contacts.md), judged at
  `observed_at`:
  - row `in_contact`: a reservation for it is `active`, or its `pass_phase` is `pass`, and now is
    inside its window. `next_aos_at`: start of its next `confirmed`/`active` reservation.
    `last_los_at`: the planned end of its most recent booked reservation that has ended. They are
    planned times (there are no actual AOS/LOS records yet, S9).
  - `counts.in_contact`: rows in contact. `counts.passes_next_2h`: booked passes starting within 2 h.
  - When the mission has **no reservations at all**, all of these are `null` ("not tracked").
    Contacts that weren't booked through Cadence (for example a direct simulator link) aren't
    seen.
  - Refetch on `invalidate` with `contacts`. AOS and LOS happen without an event, so a static
    page drifts; the fleet push's 10 s tick picks them up.
- `counts.critical_delta_1h` is always `null` (no limit-transition history yet). Show `—` and
  "not tracked yet" (U10).
- Rows are sorted by `plane`, `slot`, `scid`, `name`, with nulls last.

Errors: `404 mission_not_found`.

Size: about 600 bytes per row, roughly 300 KB for 500 spacecraft before gzip. It is unpaginated
by design (the matrix needs every row). The planned `fleet` channel delta sends only changed rows.

## `GET /api/v1/missions/:mission_id/alarms`

Limit alarms from the latest limit-state projection, one row per (spacecraft, point, limit set).
Refetch on `invalidate` with `alarms` (limit-state *transitions* only) or `limits` (definition
changes).

Query: `state` = `active` (default) | `nominal` | `all`; `severity` = `critical` | `caution`;
`spacecraft_id`; `q` (substring of point id/name/subsystem/limit set). Unknown `state`/`severity`
values get `422 invalid_params` with `details`.

**Paged** (#794): `limit` (1 to 200, default 100) and `cursor` (a previous page's
`meta.next_cursor`; a cursor that isn't one is `422 details.cursor`). Rows come in the list's
order (severity, newest first, spacecraft, point); the cursor is the last row's place in it, so
alarms that clear or appear between pages never repeat or skip a row that stays (a new alarm that
sorts before the cursor is in a page already read: refetch from the first page on `invalidate`).
**Every row of every page is enriched.** `data.total` counts the rows matching the filters.

**Sister alarms, server-side** (replacing the client-side filter): `point_id` (exactly that point),
`plane` (the spacecraft whose metadata has that orbital plane; none: no rows) and
`exclude_spacecraft_id`. "N sisters in P07 out of limits" is
`?state=active&point_id=…&plane=7&exclude_spacecraft_id=…&limit=1` and `data.total`; B4's rows
are the same query's first page.

```json
{
  "meta": {"next_cursor": "g2gEYQBiAAABWm0AAAAGc2MtMDAzbQAAAAVIS…" },
  "data": {
    "observed_at": "2026-11-08T02:41:17Z",
    "summary": {"active": 4, "critical": 3, "caution": 1, "latest_transition_at": "2026-11-08T02:35:02Z"},
    "total": 4,
    "alarms": [
      {
        "id": "limit_event_…",
        "spacecraft_id": "spacecraft-earendil-312",
        "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": "EPS", "unit": "V", "description": null},
        "severity": "critical",
        "active": true,
        "condition": "red_low",
        "value": 23.1,
        "limit_set_name": "DEFAULT",
        "thresholds": {"red_low": 24.0, "yellow_low": 25.0, "yellow_high": 33.0, "red_high": 34.0},
        "first_crossed_at": "2026-11-08T02:35:02Z",
        "generation_time": "2026-11-08T02:41:14Z",
        "received_at": "2026-11-08T02:41:15Z"
      }
    ]
  }
}
```

- `severity`: `critical | caution | nominal`, the same vocabulary as the fleet `limit_state`
  (`red` = critical, `yellow` = caution, `green`/`blue` = nominal).
- `condition`: the raw limit state (`red_low`, `yellow_high`, …). It tells you which side was crossed.
- `summary` counts **all** active alarms in the mission, ignoring the filters.
- `thresholds`: the bands of the limit definition version that produced this state. A missing band
  is `null`. The whole object is `null` if the definition can't be found.
- `first_crossed_at`: when the point entered its current state. It is the oldest evaluation in the
  current unbroken run of that state, by generation time (falling back to receipt time). The
  server looks back up to 200 evaluations, so for a state held longer than that it is the oldest
  one in the window. Every page is enriched (a page is at most 200 rows, which bounds those
  reads).
- `value`: the evaluated engineering value, as a number, string or boolean.
- Sorting: severity (critical first), then newest received first.
- `point.unit`: the engineering unit of the decoded packet field in the mission's **active** binding
  set, falling back to the active revision's catalog declarations (parameter → parameter type →
  unit, which is where XTCE import puts it). `null` when the catalog declares no unit or nothing is
  active. `point.description` is
  always `null` for now: catalog import doesn't carry parameter descriptions through to the binding
  set yet (api-ops backlog, with M23).
- **Not yet:** the D6 alarm lifecycle (ack/assign/hand-off).

## `GET /api/v1/missions/:mission_id/counts`

Small counts for the shell (Ops rail, mobile on-call tabs, the top bar's posture), so the shell
doesn't load `GET /fleet` (~300 KB) for numbers. Refetch on `invalidate` with `alarms`,
`commanding`, `spacecraft`, `attention` or `limits`, throttled, and on `telemetry` throttled to
about 10 s (`posture.stale` changes with time).

```json
{"data": {
  "observed_at": "2026-11-08T02:41:17Z",
  "alarms": {"active": 4, "critical": 3, "caution": 1, "unacknowledged": 2, "limits_configured": true},
  "commands": {"open": 25, "awaiting_viewer": 2},
  "fleet": {"total": 500},
  "contacts": {"in_contact": 4},
  "attention": {"open": 2, "acknowledged": 1},
  "runtime": {
    "state": "not_applied", "since": "2026-11-11T22:14:31Z", "reason": "spec_mismatch",
    "failure_message": "…", "desired_generation": 8, "applied_generation": null,
    "applied_at": null, "activated_at": "2026-11-11T21:58:02Z", "change_set_id": "…"
  },
  "posture": {
    "critical": 2, "caution": 1, "stale": 3, "nominal": 488, "never_heard": 6, "total": 500,
    "limits_configured": true, "telemetry": "ok", "observed_at": "2026-11-08T02:41:17Z"
  }
}}
```

- `alarms`: from **alarm episodes** (both sources, DECISIONS #17); `unacknowledged` = active
  episodes with status `new`. `limits_configured` is the same as `GET /fleet` `limits.configured`.
  Per U13, show a real `0` only when something can raise alarms (ground limits configured, or
  catalog monitoring). The whole object is `null` if episodes can't be read.
- `commands.open`: queued + release pending + in flight + approval pending. `awaiting_viewer`:
  approval-pending requests the viewer didn't request (the same number as `GET /fleet`).
- `contacts.in_contact`: spacecraft in a booked contact now (same rule as `GET /fleet`). `contacts` is
  `null` when the mission has no reservations (not tracked).
- A `null` count means "can't compute": omit it in the UI, never show `0`.

- `attention` (DECISIONS #54, U31): `{open, acknowledged}`, counting the mission's
  open "needs acknowledgment" items (pass-resolution conflicts for now). It feeds Now's queue header
  and the mobile Now badge, not a rail count. Refetch on `invalidate` with `attention`.
- `runtime` (ux U38, the mission-wide banner): whether the mission's runtime has applied its active
  generation, from `Cadence.Reads.MissionRuntimeStatus` (the same record as the `mission_runtime`
  attention item; a recorded lookup, never a call into the runtime).
  - `null`: nothing to say (no active generation yet, or the server just started). No banner.
  - `state: "applied"`: running the active generation. `since` is `null`; `applied_at` is when it
    last applied. No banner.
  - `state: "not_applied"`: applying `desired_generation` has failed for 60 s or more (a normal
    apply never shows). `since` is the first failure, `applied_generation` what the runtime
    last applied (`null` if nothing since the server started). Show the banner.
  - `reason`: `spec_mismatch | reconcile_crashed | runtime_not_running | apply_failed` (any other
    failure reads `apply_failed`), `null` when applied. `failure_message`: short diagnostic text,
    for a details line, not for the headline.
  - `activated_at`, `change_set_id`: the desired generation's activation and the change set that
    made it, when known; `null` otherwise.
  - Times are ISO-8601 UTC; generations are integers. A flip between `applied` and `not_applied`
    publishes `attention`, so refetch on `invalidate` with `attention` (no new topic). Since 11-17
    (U91) that includes the moment the 60 s debounce makes `not_applied` visible, even though
    nothing else changed then.
  - The `mission_runtime` attention item carries these fields plus two (11-17, ux U91; not on
    `runtime` here): `reason_detail` (`null` | string; for `spec_mismatch`, the field that failed
    to verify, e.g. `binding_set_content_sha256`; Technical details only) and `next_pass`
    (`null` | `{contact_id, spacecraft_id | null, spacecraft_name | null, station: {name, code |
    null} | null, starts_at, ends_at | null, in_progress, started}`: the pass in progress, else
    the next one starting within 2 h; `started` is true only when its contact actually started).

- `posture` (the top bar's fleet posture; dashboards, fe-ops 11-16): spacecraft counted by their
  worst condition, **the same numbers as `GET /fleet` `counts`** (`critical`, `caution`, `stale`,
  `nominal`, `never_heard`, `total`), from the same code (`FleetStatus.posture/3`): the same rule,
  `stale_after_s` and durable receipts, without building rows.
  - `limits_configured` = `GET /fleet` `limits.configured` (= `alarms.limits_configured`).
  - `telemetry`: `"ok" | "degraded"`, as on `GET /fleet` (degraded: the history store didn't
    answer, so a spacecraft not heard since a restart reads `never_heard`, not `stale`).
  - `observed_at`: the read's time (the top-level `observed_at`, repeated so the object stands
    alone). The counts are never `null`.
  - Cost: `/counts` now also reads the latest values, the limit states and the durable receipts
    (bounded at 3 s), the inputs of `GET /fleet` minus profiles and contacts.

Errors: `404 mission_not_found`.

## `GET /api/v1/missions/:mission_id/action-queue`

The viewer's ranked action queue (Now A2), ranked by ux U11. Refetch on `invalidate` with `alarms`,
`commanding`, `spacecraft`, `limits`, `catalog`, `data_sources`, `settings` or `attention`, plus `telemetry`
throttled to about 10 s (stale groups change with time).

```json
{"data": {
  "observed_at": "2026-11-08T02:41:17Z", "stale_after_s": 900, "failure_lookback_s": 86400,
  "alarms_truncated": false,
  "counts": {"p1": 2, "p2": 3, "p3": 1, "spacecraft_p1": 4},
  "items": [{
    "id": "alarm:critical:EPS.VBAT:red_low",
    "priority": 1, "kind": "alarm", "state": "critical",
    "since": "2026-11-08T02:35:02Z", "due_at": null, "count": 3,
    "spacecraft": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312, "plane": 13,
                    "stale": false, "last_received_at": "…", "violating_points": 1,
                    "value": 23.1, "first_crossed_at": "2026-11-08T02:35:02Z"}],
    "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": null, "unit": "V"}, "condition": "red_low",
    "source": "ground_limit", "acknowledged": 0,
    "plane": null, "command": null, "outcome": null, "command_requests": [], "finding": null
  }]
}}
```

Every item has every field; fields that don't apply to its `kind` are `null` (or `[]` for lists).

| kind | priority | state | grouped by | filled fields |
| --- | --- | --- | --- | --- |
| `alarm` | 1 critical, 2 caution | `critical` / `caution` | `{source, severity, point, condition}` of each spacecraft's **worst** active alarm episode (critical, then unacknowledged, then newest) | `source` (`catalog_monitoring` / `ground_limit`), `acknowledged` (members acknowledged), `point` (with `unit`), `condition` (the episode's `source_state`), `spacecraft` (with `value` = last value, `first_crossed_at` = episode opened, `episode_id`, `status` `new`/`acknowledged`, `assignee`) |
| `command_failed` | 1 | `critical` | `{command, outcome}`, failures within `failure_lookback_s` | `command {id, name}`, `outcome` (`failed` = release or verify failed, `indeterminate` = release uncertain), `command_requests`, `spacecraft` (resolved targets) |
| `approval` | 2 | `caution` | one item: decisions waiting on the viewer: standalone approval-pending requests they didn't make, plus **command groups** awaiting their GO (one each) | `command_requests` (standalone only), `command_groups [{id, title, member_count, target_count, requested_by, requested_at}]`, `spacecraft`; `count` = requests + groups |
| `stale` | 2 | `stale` | plane (`plane: null` = no plane metadata) | `plane`, `spacecraft` |
| `setup` | 3 | `off` | one per readiness finding with severity `blocker` or `not_set_up` | `finding` (the readiness finding: `id, area, severity, cause, title, body, affected_count, fix`) |
| `limits_not_configured` | 3 | `off` | — (omitted when the limits app itself isn't installed; that is a `setup` item) | none |
| `never_heard` | 3 | `off` | one item | `spacecraft` |
| `change_set_stale` (BACKLOG 8d) | 3 | `off` | at most one: the mission's active change set (open or in review) when its oldest staged change was staged more than 24 h ago (a set with nothing staged raises nothing) | `change_set {id, state: open \| in_review, staged_count, base_revision, opened_at, oldest_staged_at, submitted_at, authors [{kind, id, name}]}` (link: Setup's staged review); `count` = staged changes; `since` = `oldest_staged_at`. `change_set` is `null` on every other kind |
| `flight_event` (built, flight-events.md) | 1 critical, 2 caution | `critical` / `caution` | `{severity, point name, value}` of active `catalog_monitoring` episodes on a state rule (`enumerated`/`boolean`/`string`) | as `alarm` (`source` always `catalog_monitoring`; `spacecraft[].first_crossed_at` = the spacecraft-time `entered_at`), plus `event {value_json, entered_at}` (`entered_at` = earliest in the group) |

- `id` is stable across refetches (use it as the list key and for "seen" state).
- Order: `priority`, then alarm items whose episodes are **all acknowledged** after the rest of
  that priority, then `due_at` (soonest first), then `since` (oldest first, `null` last), then `id`.
  The server returns the order; don't re-sort.
- `since`: alarm = earliest `first_crossed_at` in the group; command = oldest failure / request time;
  stale = the oldest `last_received_at` (silent the longest); change_set_stale = the oldest staged
  change; setup / never-heard = `null`.
- `due_at` (time to consequence: next AOS, umbra entry, release time) is **always `null` for now**.
  It fills in with M7 (passes) and D1 (propagation).
- Groups can have one member. The server groups every identical cause; the UI may show small
  groups as individual rows.
- `spacecraft` members are ordered oldest-first by `since` for alarms, fleet order otherwise.
- `command_requests[]`: `{id, command_name, target: {id, name}, spacecraft_id, requested_by, requested_at, status, occurred_at}`.
  `requested_by` is a display label. `status` uses the command-status vocabulary (`failed`, `indeterminate`, `approval_pending`, …).
- `alarms_truncated`: the queue reads at most 200 active episodes (domain's page cap). `true` means
  more are active, so alarm items may be incomplete; show "Showing the first 200 alarms" and link to Alarms.
- Every item also has `source` and `acknowledged` (`null` for non-alarm kinds), and every
  `spacecraft` member has `episode_id`, `status`, `acknowledged_by` (`{kind, id, name}`) and
  `assignee` (`null` outside alarm items). Acknowledged rows show "ACK <name>" (ux U21).
- `counts.spacecraft_p1`: distinct spacecraft across P1 items (the "N spacecraft need you" headline).
- **Not derived:**
  - onboard event messages (EVS-style event packets): later, flight-events.md form (b). Critical
    flight-state telemetry (safe mode) **is** derived, as `flight_event` items (table above): a
    catalog alarm on a state such as `MODE = SAFE` is a `flight_event` row, not an `alarm` row. At
    otherwise equal keys a flight event sorts before an alarm. Field `event`, `null` on other kinds;
  - no-ACK retries: there's no automatic retry (DECISIONS #69).
  - Missed passes and stations are derived (below). Alarm items come from **alarm episodes** (both
    sources, DECISIONS #17).
- **`attention` items (DECISIONS #54, U31).** One item per open or acknowledged item from domain's
  attention read (`Cadence.Reads.Attention`), never grouped. The queue's `invalidate` list includes
  `attention`:
  - `id` `attention:<source>:<attention id>`; `kind` `attention`; `source` is the subkind
    (`pass_resolution` for now).
  - `priority` 1 (`state` `critical`) when the pass starts within 2 h or is in progress;
    otherwise 2 (`state` `caution`). Computed on every read, so a row moves from P2 to P1 at
    AOS−2h on the next refetch, without an invalidate. Acknowledged items sort last within their priority (U21),
    the same as fully acknowledged alarms.
  - `due_at` is the pass's `starts_at`, the consequence time that Now's meta shows as "AOS T−01:12".
    `since` is `raised_at`.
  - `spacecraft` has one member with the **resolved name** (title `EARENDIL-001 · …`, never the id),
    in the full member shape, filled as on `stale` items (the alarm fields `null`). A spacecraft
    that left the fleet still gets its name and `scid`.
  - A new field, `attention` (`null` on other kinds), holds `{id, source, conflict:
    cancel_failed | late_confirmation | contradicts_attestation, state: open | acknowledged,
    acknowledged_by: {kind, id, name} | null, contact_id, station {ref, id, code, name},
    provider {id, name}, starts_at, raised_at, provider_message, resolution: {action, actor {kind,
    id, name}, at, note, provider_reference} | null}`. `contact_id` is the `Review` target
    (`M/contacts/:contactId`).
  - The response gains `resolved: [{id (the row's item id, `attention:<source>:<id>`), resolved_by {kind: user | provider | system, id, name},
    action, resolved_at}]`: attention items resolved in the last 60 s, so the fade-out can show
    after a refetch. For a `user`, it reads "Resolved by Mira K.". Otherwise it says what closed it
    (ux), e.g. `provider` Northlight with `action` `confirmed` reads "Resolved: Northlight
    confirmed", never "by Cadence". A `system` closure reads its `action` alone, with no actor
    ("Resolved: cancel confirmed").
  - Refetch on `invalidate` with `attention`.
  - **`activation_apply`** (director C, ux U41): an approved activation whose apply failed or
    stalled. **P1** while `runtime_not_applied` is true (telemetry isn't processed until it
    applies), else P2; `due_at` null. `spacecraft` holds every member it names (fleet names).
    `attention` adds `{error_code, error, retryable, activation_request_id, summary, kind, app {key,
    name} | null, spacecraft_ids, spacecraft_count, runtime_not_applied, since, approved_by {id,
    name} | null, approved_at | null}` (pass fields `contact_id`, `station`, `provider`,
    `starts_at` are null). `Retry apply` is `POST …/activations/:id/resume` (activations.md), shown
    only when `retryable`. Resolved: `action` `applied` | `superseded`, `resolved_by.kind`
    `system`.
  - **`provider_change`** (§11 L14, contacts.md): **P2** for `approval_required`, due at
    `deadline_at`; **P3** for `acknowledgment_required` and `configuration_failure`. `attention`
    adds `provider_change {…}` and `deadline_at`.
  - **`ingress_backpressure`** (DECISIONS #83, ux U47; api-ops): one downlink transport of a
    running contact whose ingest is under pressure. Row id
    `attention:ingress_backpressure:<conflict>:<realized_contact_id>:<provider_binding_id>`;
    `attention.id` is the part after the source. `due_at` null. It also appears in its pass's
    `attentions[]` on `/passes` and `/passes/:id` (by `reservation_id`).
    - `conflict` `journal_near_full`: the contact's ingest buffer (its journal) is >= 80% full.
      **P1** at >= 95%, or while `rising` during the pass; else **P2**. It clears itself below 70%,
      or when the contact ends and drains (resolved `system` / `drained`). Not acknowledgeable
      (acknowledge answers `404 attention_item_not_found`).
    - `conflict` `frames_dropped`: a transport that can't push back dropped frames because its
      buffer was full (data loss; no such transport exists today, so this is the seam #83 pins).
      **P1** while the pass is live and a drop happened in the last 5 min; else **P2**. Any
      mission operator acknowledges it (`POST …/attention/ingress_backpressure/:id/acknowledge`;
      without the capability `403 forbidden` "Operators acknowledge lost telemetry."). It resolves
      once acknowledged and the contact has ended (`user` / `acknowledged`).
    - `attention` adds `{realized_contact_id, contact_label (null for now), ends_at, transport
      {provider_binding_id, kind: tcp | <adapter key> | null}, journal_usage {used_bytes,
      capacity_bytes, ratio, threshold (0.8), backlog_bytes, observed_at, rising} | null,
      drops {count, bytes, first_at, last_at, buffer: journal | executor} | null, diagnostics
      {stream_id, last_error}}`, with the shared `station`, `provider`, `starts_at`,
      `reservation_id`, `provider_message` (null) and `resolution` (null). `journal_usage` is null
      on `frames_dropped` and `drops` null on `journal_near_full`. Visible text says "buffer";
      `diagnostics` is for Technical details only (U47).
    - `conflict` `journal_disk` (ux U66): the DISK every journal shares is filling (each stream's
      own cap is `journal_near_full`; nothing caps their sum, and a full disk stops telemetry from
      every pass). One item, row id `attention:ingress_backpressure:journal_disk`, shown in every
      mission's queue. **P2** (caution) from 70%; **P1** (critical) from 90% or while `refusing`;
      it clears itself below 60% (`system` / `drained`; the resolved entry's `refused {from, to}`
      says when telemetry was refused, else null). Not acknowledgeable. `attention` adds
      `journal_disk {percent, used_bytes, size_bytes, rate_bytes_per_hour (signed; null until two
      readings), eta_full_s (only while growing, else null), holders [{realized_contact_id,
      contact_id, spacecraft_id, spacecraft {id, name, scid} | null, ground_station_ref,
      station {ref, id, code, name} (the shared station shape), provider_id, starts_at, ends_at,
      bytes, state: storing | kept, kept_until (kept only, else null)}] (this mission's contacts,
      largest first, at most 3), more_count, other_missions_bytes (never named), refusing,
      refused_since | null}`; the per-contact keys above are absent. `kept` = already all in the
      ingress archive and on disk only for the review window; above 80% those are removed early,
      oldest first (`JournalReclaim`, marked `reclaimed_early`). The only action is Open pass on a
      holder; the disk's size is deployment config. Read every minute from the OS (disksup);
      `refusing` is checked every 5 s from the journals' own append errors (`enospc`). The
      thresholds are deployment config under `:cadence, :ingress_journal` (ratios: `disk_caution`
      0.70, `disk_critical` 0.90, `disk_clear` 0.60, `early_reclaim_at` 0.80, `early_reclaim_to`
      0.70) plus `disk_emergency_free_bytes` (nil): with a floor set, critical and early reclaim
      also need free space below it. Dev (the host's shared disk): 0.95 / 0.97 / 0.93, reclaim
      0.97 -> 0.95, floor 10 GiB. The row always carries the shared keys (`contact_id`, `station`,
      `provider`, `starts_at`, `provider_message`, `acknowledged_by`), null here.
    - The state is in the node's memory (`Cadence.Runtime.IngressBackpressureMonitor`, sampled every
      5 s): a node restart clears it, along with the backlog itself. Opening and clearing
      publish `invalidate` with `attention`.
  - **`provider_ephemeris`** (#972, pass prediction #732): a provider that can't use some
    spacecraft's current orbit, grouped by cause. One item per group, never per spacecraft.
    - `attention.conflict` is the cause:
      - `norad_id_missing`: a lookup provider, whose current element set has no NORAD id. One
        group per provider.
      - `failed`: an upload provider, whose latest upload is failing and being retried. One
        group per provider and failure `reason` code.
      - `not_ready`: a routing rule binds the spacecraft to the provider, but no route to it is
        ready. One group per provider and refusal `reason` code.
      - The `reason` codes are closed lists in setup.md (provider ephemeris spacecraft). A
        provider's own text is never stored or shown.
    - `id`: `attention:provider_ephemeris:<provider_id>:norad_id_missing`,
      `attention:provider_ephemeris:<provider_id>:failed:<reason>` or
      `attention:provider_ephemeris:<provider_id>:not_ready:<reason>`.
    - **P2** (`caution`), `due_at` null, `count` 1.
    - `since` is when the group's earliest member **entered** this outcome. A re-check or retry
      that finds the same outcome keeps it, so a provider stuck for three days reads three days.
    - `spacecraft`: a sample of up to 10 members, by id.
    - `attention.provider` names the provider. `attention` adds:
      - `spacecraft_count`, the whole group;
      - `reason`, the closed code for `failed` and `not_ready`, else `null`;
      - `next_retry_at`, the earliest retry or re-check, `null` for `norad_id_missing`.
    - The whole list, with each spacecraft's code, fixed sentence and retry, is
      `GET /providers/:provider_id/ephemeris/spacecraft?cause=<conflict>[&reason=]` (setup.md).
    - Derived on every read, from the same recorded outcomes as the providers read's
      `ephemeris` buckets. There's nothing to acknowledge, and an item leaves when its group is
      empty, so it never appears in `resolved`. An archived provider raises none.
    - Refetch on `invalidate` with `attention`. An ephemeris upload run publishes it, with
      `providers`, when anything these items show changed (retries included). Archiving a
      provider publishes both too.
- **`missed_pass` and `station` items** (§8; U11 amended by U35).
  - `missed_pass`: one row per spacecraft with a pass result `missed` or `failed` (S9) whose
    planned AOS falls within `failure_lookback_s`.
    - `id` is `missed_pass:<spacecraft_id>`, `count` the number of missed passes, `since` the
      latest missed AOS, and `due_at` the AOS of the spacecraft's next booked pass (or `null`).
    - **P1** (`critical`) when the spacecraft has no booked contact within
      `missed_pass_horizon_s` (6 h, a named constant until a contact requirement's maximum gap
      replaces it), or the next contact is unknown. **P2** (`caution`) otherwise (U35).
    - The response carries `missed_pass_horizon_s` for the evidence line ("Next contact SVB-1 in
      1h 12m" / "No contact booked in the next 6 h").
    - `missed_passes: [{reservation_id, station {ref, id, code, name}, planned_aos, outcome:
      missed | failed, cause, owner}]`, newest first.
      - `cause` is a key: `no_acquisition`, `station_unavailable`, `provider_canceled`,
        `provider_rejected`, `not_ingested`, or the provider's own failure reason (free text).
        Word known keys, sentence-case anything else.
      - `owner`: `provider | us | weather | unknown`.
    - `next_contact: {reservation_id, station, aos} | null`.
    - fe-ops may group rows client-side (three or more with the same station and cause).
  - `station`: one row per ground station with an outage, maintenance or degraded window (S7)
    that overlaps booked passes in the next 24 h.
    - `id` is `station:<ground_station_id>`, `count` the affected passes, `since` the window
      start, `due_at` the first affected AOS.
    - **P1** (`critical`) when an affected pass starts within 2 h or is in progress (the U31/U33
      clock), else **P2** (`caution`).
    - `spacecraft` holds the affected spacecraft.
    - `station_issue: {station {ref, id, code, name}, window {id, kind: outage | maintenance |
      degraded, starts_at, ends_at, source}, affected: [{reservation_id, spacecraft_id, aos}]}`.
      `ends_at` is `null` for an open-ended window. The `Station` action routes to Re-plan with
      the station id; the window is there if Re-plan wants it.
  - `spacecraft` members on both kinds use the full member shape, alarm fields `null` (as for
    `attention`). `missed_passes`, `next_contact` and `station_issue` are `null` on other kinds.
  - Station identity on `missed_passes[]` is resolved by id, code or provider ref, as on `/passes`.
  - Refetch on `invalidate` `contacts`, `stations` and `pass_results`.
- `failure_lookback_s` is `config :cadence, :action_queue_failure_lookback_s` (default 24 h).
  Failures older than that drop off the queue; they stay on the commands pages.

Errors: `404 mission_not_found`.

## `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/passes` (Investigate Passes tab, owner: api): built

This endpoint covers P1 and the queued counts for P3 (ux Investigate.md 24a160b8; fe-ops agreed the
shape). The passes come from existing reads, so the row logic isn't copied:

- P2 Gantt and P3 Upcoming: `GET /passes?spacecraft_id=&from=now-24h&to=now+24h`. P3 is the rows
  with `ends_at > now`.
- P4 Recent: `GET /pass-review/rows?spacecraft_id=&from=now-7d&to=now`, grouped by day on the client.

```json
{"observed_at": "…",
 "coverage": {
   "last_contact": {"pass_id": "…", "station": {"ref", "id", "code", "name"}, "los_at": "…"} | null,
   "next_contact": {"pass_id": "…", "station": {…}, "aos_at": "…"} | null,
   "passes_next_24h": 9,
   "longest_gap": {"seconds": 19860, "from": "…", "to": "…"} | null,
   "none_within_6h": false,
   "contact_rule": {"state": "met" | "short" | "none", "have": 2, "need": 3,
                    "rules": [{"requirement_id": "…", "version": 1, "text": "3 downlink contacts",
                               "window": {"from": "…", "to": "…"}, "have": 2, "need": 3, "met": false}]}},
 "queued": {"<pass id>": 2}}
```

- **Booked** means `confirmed` or `active`, as in Now's queue. It's what `next_contact`,
  `passes_next_24h`, `longest_gap` and `none_within_6h` count. The upcoming list (from `/passes`)
  shows every live state.
- `last_contact` is the most recent pass that has ended and flew (`active` or `completed`), within
  7 days.
- `next_contact` looks 7 days ahead. The 24-hour figures (`passes_next_24h`, `longest_gap`,
  `none_within_6h`) don't, so a next contact two days out can sit beside `passes_next_24h: 0`.
- Pass rows' `source.synthetic` and `uplink_capable` are null when the provider didn't say. Read
  null as unknown, never as false.
- `longest_gap` is the longest stretch of `[now, now+24h]` with no booked pass, edges included. It
  is null only when booked passes cover the whole day.
- `none_within_6h` is U35's caution: no booked pass starts within 6 h.
- `contact_rule` covers the spacecraft's active contact requirements whose window overlaps today
  (UTC):
  - each window's `have` counts the booked or flown passes inside it, capped at its `need`;
  - `short` means at least one window is short of its `need`;
  - `none` means no requirement covers today, so the UI shows `—` with a link to Contact planning.
- `queued` maps each `/passes` row id to the queued, unfinished command groups bound to it. Only
  counts above 0 appear.
- `uplink_capable` null on a `/passes` row means the provider didn't say. Show it blank, not
  `Down only`.

Errors: `404 spacecraft_not_found`.

## `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/uplink` (Investigate Uplink tab): built

"Can I command this spacecraft now, and what's going up?" (Investigate.md, Tab · Uplink.)

```json
{"data": {
  "spacecraft": {"id": "…", "name": "EARENDIL-001", "scid": 1},
  "route": {"routing_rule_id": "…", "name": "BLOCK 1 · ALL STATIONS", "transport_id": "…", "transport_name": "S-band TC", "gateway_scid": 1},
  "now": {"in_contact": true, "pass": {"reservation_id": "…", "contact_id": "…", "station": {…}, "provider": {"id", "name"}, "starts_at": "…", "ends_at": "…"},
          "readiness": {"state": "ready", "reason": null, "since": "…", "command_groups_queued": null}},
  "next_passes": [{"reservation_id": "…", "contact_id": "…", "station": {…}, "provider": {…}, "starts_at": "…", "ends_at": "…", "uplink_evidence": "booked",
                   "uplink_confirmed": true, "attested_by": null}],
  "queue": [{"position": 1, "request_id": "…", "command_id": "…", "command_name": "SET_MODE", "arguments_json": "{\"mode\":3}",
             "group": {"id": "…", "title": "…"}, "not_before": null, "expires_at": "…", "queued_at": "…"}],
  "waits_for": {"pass": {…}, "readiness": {…} | null},
  "released": [{"request_id": "…", "command_name": "NOOP", "group": {"id", "title"} | null, "released_at": "…",
                "contact_id": "…", "status": "released", "verification_state": "verified"}]
}}
```

- **U1 `now`:**
  - `in_contact: true` when the spacecraft is inside a live commandable pass, which is then `pass`
    with its readiness (U33 words).
  - Otherwise `pass` is the next commandable pass, with readiness when its session is already up.
  - `now: null` means no commandable pass is booked.
  - `readiness` is the same object as a `/passes` row's `uplink_readiness` (`command_groups_queued`
    is known only when `blocked`), or `null` when the pass has no live uplink session yet.
- **U2 `next_passes`:** up to 3 commandable passes (with a command window) in the next 24 h after
  `now.pass`. `uplink_evidence` is `booked` (the provider confirmed the uplink leg) or `attested`
  (operator-attested, uplink unconfirmed, U32/#46); `uplink_confirmed` and `attested_by` are the
  `/passes` row's.
- **U3 `queue`:** this spacecraft's lane in release order (priority, then queue order), pending or
  releasing.
  - Release rule: `not_before` (null = at the next AOS); expiry: `expires_at`.
  - `waits_for` is the pass the lane's head will release on (the same for every entry; a lane
    releases in order), with its readiness for the U33 blocked line.
- **U4 `released`:** releases in the last 24 h, newest first. `status` is the command status
  (`released | in_flight | failed | indeterminate | release_pending`) and `verification_state`
  is the group member `stage` vocabulary (`radiating | executed | verified | no_verifier |
  verify_failed | release_failed | indeterminate`), so C3's words map one to one.
- **`route`:** the primary active uplink routing rule, or `null` (header meta). `name` is the
  rule's display name; `transport_name` is `null` if the transport is archived.
- Errors: `404 spacecraft_not_found`, `404 mission_not_found`. Refetch on `invalidate`
  `commanding`, `contacts` and `attention`.

## `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/configuration` (Investigate Configuration tab): built

"What is this spacecraft running, and what changed?" (Investigate.md, Tab · Configuration). Read-only.

```json
{"data": {
  "spacecraft": {"id": "…", "name": "EARENDIL-312", "scid": 312, "norad_id": null, "plane": 7, "slot": 12,
                 "archived": null},
  "profile": {"id": "…", "name": "Earendil Block 1 — Demo", "version": 6, "latest_version": 6},
  "catalog": {"running": {"id": "…", "revision_number": 14},
              "profile": {"id": "…", "revision_number": 15}},
  "overrides": [{"section": "Framing", "path": "frame_parameters.frame_size", "label": "TM frame length",
                 "unit": "bytes", "profile_value_json": "1115", "spacecraft_value_json": "892",
                 "reason": "…", "set_at": "…", "actor": {"kind": "user", "id": "…", "name": "Mira K."}}],
  "routing_rules": [{"id": "…", "name": "Primary downlink", "purpose": "TM", "direction": "inbound",
                     "role": "primary", "enabled": true, "active": true,
                     "transport": {"id": "…", "name": "Svalbard X-band", "version": 2},
                     "station": {"id": "…", "code": "SVB", "name": "Svalbard"} | null}],
  "pending": [{"change_set_id": "…", "state": "in_review", "base_revision": 8,
               "changes": [{<change, as /config/change-sets/:id>, "via": "spacecraft_override"}]}],
  "recent_revisions": [{<revision_summary + labelled entries, as /config/revisions/:n>,
                        "via": ["spacecraft_override"]}]
}}
```

- **G1:** `spacecraft` as `/spacecraft/:id` (identity, plane/slot null when unknown). `archived` is
  `{at, by: actor | null}` for an archived spacecraft, else `null`. `profile` as `/spacecraft/:id`
  (null when unbound), plus the pinned version's `lifecycle` (`active | deleted`),
  `uplink_protocol` (`tc | uslp`) and `packet_protocol` (`space_packet`), each null when the pinned
  version can't be read (§11c parity, the G1 fact line).
  - `catalog.running` is the catalog revision the spacecraft's active configuration uses;
    `catalog.profile` is the one its profile (with its overrides) sets. Either can be `null`. When
    both are set and differ, show the "Running rev 14; the profile is on rev 15" caution (the same
    rule as the Readiness catalog finding, DECISIONS #65).
  - `catalog.running.composition` and `catalog.profile.composition` (D2, #543): the composition
    behind this revision (shape in setup.md's 'Compositions' section), or null.
- **G2 `overrides`:** this spacecraft's overrides only, labelled from the profile schema (`label`,
  `unit` may be null). Values are JSON text; `null` means not set. `[]` → "Uses its profile as is."
  - `composition` (D2, #543): for a `catalog_revision_id` override, the composition behind the
    catalog revision it sets (shape in setup.md's 'Compositions' section); null for any other.
- **G3 `routing_rules`:** as `/spacecraft/:id`, plus the transport's `station` (null when the
  transport names none).
- **G4 `pending`:** the mission's open or in-review change set when it has changes touching this
  spacecraft. Each change is exactly `/config/change-sets/:id`'s (`id, summary, author, staged_at,
  source, state, ops`), plus `via`, so Setup's sentences apply. `via` is `spacecraft`, `spacecraft_override` or `spacecraft_profile` (an edit to its
  profile). `[]` → hide G4. A change set has no revision number until applied; `base_revision`
  is the head it was staged on.
- **G5 `recent_revisions`:** the last 5 applied revisions with an entry for this spacecraft
  (spacecraft, override or derived routes), newest first. Each is exactly `/config/revisions/:n`
  (revision_summary plus `entries`, labelled), with only this spacecraft's entries; `via` lists
  their kinds. `All revisions` → Changes.
- "Edit in Setup": show it from the session's capabilities (org admins), as Setup does.
- Errors: `404 spacecraft_not_found`, `404 mission_not_found`. Refetch on `invalidate`
  `spacecraft`, `catalog` and `configuration`.

## Time windows (shared by M10 and M11)

Query: `from` and `to` are ISO-8601 (default: the last hour ending now); `spacecraft_id` is
optional but you almost always want it; for M10, `max_points` is 1–2000 (default 500). History
windows are capped at 31 days; intervals are not. Bad values get `422 invalid_params` with
`details` keyed by parameter. URL-encode `point_id` (ids contain dots, and some may contain
slashes).

## `GET /api/v1/missions/:mission_id/telemetry/points/:point_id/history`

Decimated history by **generation time** (it falls back to receipt time for samples without one).
The data is fixed-width buckets on a UTC-day grid (multiples of `bucket_width_ms` from midnight UTC of
the window's first day, the same as QuestDB `ALIGN TO CALENDAR`); there are at most about
`max_points` buckets, and empty buckets are omitted.

```json
{"data": {
  "point_id": "EPS.VBAT", "unit": "V", "description": null, "spacecraft_id": "spacecraft-earendil-312",
  "from": "2026-11-08T01:41:17.000Z", "to": "2026-11-08T02:41:17.000Z",
  "bucket_width_ms": 7200, "truncated": false,
  "buckets": [{"t": "2026-11-08T01:41:17.000Z", "t_end": "2026-11-08T01:41:24.200Z",
               "min": 23.4, "max": 23.6, "mean": 23.5, "count": 7}]
}}
```

- `unit` / `description`: same source and caveats as the alarm `point.unit` / `point.description`.
- Only numeric values are bucketed (booleans count as 0/1). Enum and text points return no
  buckets for now; a state-timeline shape will come if a screen needs it.
- `truncated: true` means the raw-sample fallback (used on backends without native decimation)
  hit its 20,000-sample cap. Narrow the window if you see it.
- `503 history_unavailable`: the history store can't be reached (in this worktree's dev env,
  QuestDB isn't running; see the qa runbook). Show the chart's unavailable state.
- Refetch on `invalidate` with `telemetry`, throttled. For a live tail, prefer the planned
  `spacecraft:<id>` `points` push.

## `GET /api/v1/missions/:mission_id/limits/points/:point_id/intervals`

The limit-definition bands in effect over the window, for drawing bands behind the history chart.

```json
{"data": {
  "point_id": "EPS.VBAT", "spacecraft_id": null, "from": "…", "to": "…",
  "intervals": [{
    "from": "2026-10-19T00:00:00Z", "to": null,
    "limit_set_name": "DEFAULT", "limit_definition_id": "…", "limit_definition_version": 3,
    "scope": {"type": "mission", "ref": null},
    "thresholds": {"red_low": 24.0, "yellow_low": 25.0, "yellow_high": 33.0, "red_high": 34.0}
  }]
}}
```

- `to: null` means the definition is still active. Missing bands are `null`.
- Intervals come from governed limit-definition lifecycle events. A definition persisted without a
  lifecycle event (some fixtures) has no interval, but the alarm row's `thresholds` still shows
  its bands.
- Refetch on `invalidate` with `limits`.

## `GET /api/v1/missions/:mission_id/events` (owner: api, DECISIONS #26)

The event log for Investigate B2 and Timeline. It reads the canonical mission timeline (projected
mission events merged with operational events). Refetch on `invalidate` with `events` or `alarms`.

Query: `from`, `to` (ISO, default the last 24 h), `spacecraft_id`, `plane` (an integer: the
spacecraft in that orbital plane, from spacecraft metadata; an empty plane returns no events; with
`spacecraft_id`, only that spacecraft if it's in the plane; `422 invalid_params` `details.plane` if
it isn't an integer), `kind` (comma list of
`limit, flight_event, contact, command, config, operator, data`; `data` is data-plane housekeeping
such as source watermarks and source health and credential events, which you'll usually filter out; limit-definition lifecycle events are `config`), `limit` 1–500 (default 200), and
`cursor` (opaque, from `meta.next_cursor`). Newest first. A page holds up to `limit` events of the
requested kinds: the server reads further back until it has them (up to ten source pages per
request), so housekeeping rows don't starve a filtered page. Fewer than `limit` with a
`next_cursor` means keep paging.

```json
{"data": {"from": "…", "to": "…", "events": [{
  "id": "mission_event:…", "at": "2026-11-08T02:08:11Z",
  "kind": "limit", "raw_kind": "limit_violation", "severity": "critical",
  "text": "VBAT crossed red low", "detail": "…",
  "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312},
  "refs": {"alarm_id": null, "point_id": "EPS.VBAT", "command_request_id": null, "contact_id": null,
           "subject": {"kind": "data_source", "id": "…", "name": "Flight telemetry source"}}
}]}, "meta": {"next_cursor": "…"}}
```

- `text` is an operator sentence naming what the event is about, built on the server (ux review
  2026-11-09-timeline #1): "Flight telemetry source caught up to 10:23:54Z", "Contact with
  EARENDIL-004 completed, 10:22:54Z–10:23:52Z", "Dashboard Comms payload v1 published by Mira K.",
  "Catalog rev 2 (QA-E2E re-import) registered". A person is named ("by Mira K.") only while
  an active member of the mission's organization (#472, #146 C1). Otherwise the "by" clause is
  dropped, never an id or email (ux U25). Cadence's own act reads "by Cadence", and a service
  identity of the organization "by Nightly planner (a service identity)" (U70). One that can't be
  named reads "by a service identity", never its id (#488, ca-ux). Names come from the live
  rows (`Control.ActorRef`), never from a stored actor document. Unknown kinds fall back to the sentence-case key
  plus the spacecraft ("Limit violation on EARENDIL-004"), never Title Case. `detail` is `null`.
- Contact events (`scheduled_contact_*`, `realized_contact_*`) have kind `contact`. A realized
  contact that completed reads "ended (not verified)" until S9 verifies it. A provider-cancelled
  contact names its spacecraft, station and window. Ranges carry one Z ("10:22:54–10:23:52Z").
- The same fact can reach the timeline from two sources (a projected mission event and its
  operational event). Rows with the same raw kind, subject and second collapse into one, keeping
  the more severe.
- `activation` subjects have no console page yet; leave them unlinked (Setup's change history is
  the nearest place).
- Watermark events (ux U60, domain storage-growth.md part 2): the per-write
  `source_watermark_advanced` is being replaced by events on a change of state (old rows keep
  "… caught up to …" until they age out). All are category `data` (the Timeline's opt-in
  filter). `raw_kind` `source_watermark_settled`, once per contact at settle: "EARENDIL-008 · SVB
  03:10Z pass: telemetry stored through 03:19:40Z (LOS 03:19:57Z)", subject the contact (also
  for Contacts' selected-pass history). `source_watermark_caught_up`, after being ≥ 60 s behind:
  "Telemetry from EARENDIL-008 caught up at 03:22Z after falling 2 min behind", subject the
  data source. `source_watermark_retreated` with a spacecraft: "EARENDIL-008's stored telemetry
  moved back to 03:12Z" (+ " for a replay", `caution`); without one, as before.
- `refs.subject` is the link target `{kind: "data_source" | "contact" | "dashboard" |
  "catalog_revision" | "activation" | "config_revision" | "pass", id, name}`, or `null` when there is none.
- **`POST /telemetry/latest {point_ids, spacecraft_ids}`** (Compose B2 "Now", fe-ops) →
  `{values: [{spacecraft_id, point_id, value_json | null, received_at | null, stale}]}`: one entry
  per spacecraft × point, spacecraft first, in the asked order.
  - Limits: at most 10 points per call and **no ceiling on spacecraft**: a request is bounded by
    its response, 8 MB (about 50,000 values; `422 details.max_response_bytes`). The server reads
    only the asked points × spacecraft, in chunks of spacecraft, so a 1,000-craft fleet is one call.
    Every spacecraft must be the mission's (`422 details.spacecraft_ids` plus `unknown`).
  - `value_json` is the engineering value as JSON text (64-bit safe); null when there's no value
    yet.
  - `stale` uses the point's stale timeout, else the fleet's (`stale_after_s`); false when there's
    no value.
  - Refetch on `invalidate` with `telemetry` (throttle it).
- **Off-plan bookings** (L15, DECISIONS #78) are `contact` events: `raw_kind`
  `contact_booked_off_plan`, "EARENDIL-312 · SVA 11-15 03:10Z booked outside a plan by Mira K." (the
  pass's AOS, dated when it isn't on the booking's UTC day, else time only; "by an operator"
  without an actor; ux, Contacts.md), severity `info`, `at` = when it
  was booked, `detail` = "“<note>” Doesn't count toward contact rules." (without a note, just the
  second sentence), `spacecraft` its spacecraft,
  `refs.subject` `{kind: "pass", id: <reservation id>, name: null}` (`GET /passes/:id`).
- **Frames with another SCID** (ux U81 §2, DECISIONS #102) are `contact` events: `raw_kind`
  `contact_scid_mismatch`, one per contact when MORE than half of its integrity-checked TM frames
  carried another SCID (domain's `ScidMismatch.most?/1`, the same rule as the Now item). Text
  "EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID." (the station's code,
  else its name; without a station "the 03:10Z pass"; without a spacecraft name the
  "EARENDIL-312 · " part is dropped, never an id). Severity `caution`; `at` = the pass's start.
  `detail` = "412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept them as
  raw evidence and made no telemetry from them." ("not this pass's SCID 1" without a name; SCIDs
  read "SCID 3", "SCIDs 3 and 7", "SCIDs 3, 7 and 9", more than three "12 different SCIDs", and
  "at least 12 different SCIDs" when the list may be short). `refs.subject` and
  `refs.contact_id` are the realized contact ('Open contact record' → History `?contact=`).
- **Applied configuration revisions** (BACKLOG 8d) are `config` events: `raw_kind`
  `config_revision_applied` ("Applied r6 · 2 changes") or `config_revision_rolled_back`
  ("Rolled back to r4"), severity `info`, `at` = applied time, `spacecraft` `null`,
  `refs.subject` `{kind: "config_revision", id: "6", name: "r6"}` (`id` is the revision number;
  Setup has no per-revision route yet, so link to `setup.revisions`). The baseline revision (r1)
  isn't listed. They're mission-wide, so a `spacecraft_id` or `plane` filter leaves them out;
  `/events/density` counts them as `info`. An apply that changes the runtime also shows its
  "… activated" row.
- A watermark retreat is `caution` only when it means something for the operator (a replay or
  late data), and the sentence says so ("… went back to 22:28:30Z (data replay)"); otherwise
  it's `info` (#3).
- `kind` is derived from the entry's source and category; `raw_kind` keeps the original.
  `severity`: timeline critical/error → `critical`, warning → `caution`, cleared/resolved status →
  `nominal`, everything else → `info`.
- The `kind` filter is applied to each fetched page, so a page can hold fewer than `limit` events
  while `next_cursor` is still set. Keep following the cursor. `plane` filtering isn't supported
  (filter client-side with `/fleet` plane data).
- `refs.alarm_id` is `null` (alarm episodes link by point; see alarms.md).
- Errors: `422 invalid_params` (`kind`, `limit`, `cursor`, `from`/`to`).
- U69 A8a: each event carries `record: {status, source_record: {kind, id} | null,
  source_endpoint_ref, scheduled_contact_id, realized_contact_id, path_id,
  capability_instance_id, activation_id, correlation_key}` (each `null` when the producing record
  has none): the producing record's own fields for the detail panel. `status` and
  `source_record.kind` are the producing store's words (Technical details, shown as said).
- Older events (A9d): pass `meta.next_cursor` as `?cursor=`; `null` = nothing older in the window.
- U69 A9b `raw_kind=`: a comma list (at most 20) of exact raw kinds (`command_released`) or
  prefixes ending in `*` (`command_*`); it ANDs with `kind=`. Same on `/events/density`, so the bar
  matches the list. An exact-only list filters in the database; with a prefix, the filter runs per
  fetched page (like `kind`), so keep following `next_cursor`. A bad item → `422 invalid_params`
  (`details.raw_kind`).

- U69 A9a `severity_at_least=caution|critical`: keeps rows whose shown `severity` is at or above
  it (`caution` = caution and critical). Same on `/events/density`. It runs per fetched page,
  like `kind`, so keep following `next_cursor`. Anything else → `422 invalid_params`
  (`details.severity_at_least`).

## `GET /api/v1/missions/:mission_id/events/raw-kinds?from&to` (U69 A9b picker, owner: api)

`{"data": {"from", "to", "raw_kinds": [{"raw_kind": "command_released", "kind": "command", "count": 12}]}}`:
every raw kind in the window with its console `kind` and how many events, most frequent first.
Counted like `/events/density` (no rows loaded), plus the merged configuration revisions and
off-plan bookings. Window at most 31 days (default the last day).

## `GET /api/v1/missions/:mission_id/events/:event_id` (U69 A8b, owner: api)

`{"data": {"event": <one event, the row shape above, with record>}}`: a Timeline permalink. The id
is a row's `id` (URL-encode it; ids contain `:`). Works for stored mission and operational events
and for the rows the Timeline merges in (applied configuration revisions, off-plan bookings). Use
`event.at` to centre the window. `404 event_not_found`.

## `GET /api/v1/missions/:mission_id/events/density`

`{"data": {"bucket_s": 900, "buckets": [{"t", "critical", "caution", "nominal", "info"}], "truncated": false}}`.
Same filters, `plane` included (no cursor). `bucket_s` is 60–86400 (default: about 96 buckets over the window). Buckets
are aligned to `from`; empty buckets are omitted. The window is at most 31 days. Without a
`spacecraft_id` or `plane` filter every event is counted in the database (lead 11-15; no rows
are loaded, so `truncated` is `false`); with one, at most 5,000 events are read (`truncated: true`
beyond that). Both count the same way as the list (same kinds, severities and duplicate rule).

## `GET /api/v1/missions/:mission_id/telemetry/points` (M23, owner: api)

Point search for Telemetry explore (T1) and ⌘K Telemetry. Query: `q` (a case-insensitive
substring of the id, name or description; empty lists everything), `spacecraft_id` (optional;
must be a mission spacecraft), and `limit` 1–200 (default 50).

```json
{"data": {"points": [{
  "id": "EPS.VBAT", "name": "VBAT", "description": null, "unit": "V",
  "subsystem": "EPS", "type": "numeric",
  "latest": {"value": 23.1, "received_at": "…", "limit_state": "critical", "source": "live"}
}]}}
```

- The points are the mission's canonical set: fields of the active binding set's packet
  definitions (`subsystem` is the packet name) plus governed derived telemetry (`subsystem:
  "Derived"`). It's the same set the LiveView point picker offers, sorted by id.
- `type`: `numeric | enum | text`, from the field's data type.
- `latest` appears only with `spacecraft_id`. `source` is `live | history`:
  - `live`: from the current-value store. On :4011 that store is in memory, and every server
    restart empties it until the spacecraft sends telemetry again.
  - `history`: the store has no value since the restart, so it's the newest stored sample from
    the telemetry history (551cb796). Its `received_at` can be days old; show it as such.
  - `null`: no stored sample for that point and spacecraft (never received, or past retention).
    If the history store can't be read, it's also `null` for that request.
  - `limit_state` is `critical | caution | nominal | no_data`, from the limit projection on
    either source; never `null`.
- `has_limits` (on each point, with or without `spacecraft_id`; ux T1): `true` when the point has
  an active limit definition. `false` reads "No limits" ("No limits are defined for this point.");
  `true` with `limit_state: no_data` reads "Not checked yet". Neither is nominal or counted in "Out
  of limits". `limit_state` keeps its values.
- `description` is often `null`: packet fields don't carry one yet.
- Errors: `422 invalid_params` (`limit`, `spacecraft_id`).

## One sample (§11c(D) D1, owner: api)

`GET /api/v1/missions/:mission_id/telemetry/samples/:sample_id?point_id=&spacecraft_id=&receipt_time=&at=`
→ `{data: {status, sample}}`. `point_id` and `spacecraft_id` (the console spacecraft id) are
required; `receipt_time` (ISO-8601) makes the match exact: pass it when you have it (the alarm
episode's `trigger.receipt_time`, an event's `sample.receipt_time`). Without it, `at` (the
sample's generation time) bounds the search to ±60 s; with neither, the last 24 hours, which may
answer `ambiguous`. Display rows are never paged (limit 1), and source execution's 5 s budget ends
a slow read as `timeout`. It runs the same authorized read the legacy Explore
page's "Selected sample" made (the dashboard source resolver, then physical inspection on the
resolved bindings) and its allowlisted projection.

- `status`: `ready | not_found | ambiguous | timeout | unsupported | unavailable`; `sample` is `null`
  unless `ready`.
- `sample`: `{point_id, point_name, sample_id, spacecraft_id, receipt_time, generation_time,
  quality: good | suspect | bad, raw_value, engineering_value, engineering_unit, source, record}`.
  - `raw_value` / `engineering_value`: `{state: ready | not_recorded | limited | unsupported, text,
    format: json | hex | null}`; `limited` = too large to show (no text), not a cut-off value.
  - `engineering_unit`: from the point's catalog definition, or `null`.
  - `source`: `{realm: flight | rehearsal | replay | simulation, data_source_id, data_source_name,
    source_binding_id, binding_label, binding_version, source_endpoint_id, endpoint_label,
    replay_run_id, replay_run_label}`.
  - `record`: `{packet_id, evidence_id, packet_definition_id, packet_definition_name,
    packet_definition_version, validity_state: canonical | duplicate | conflict | superseded |
    advisory | null}` (`advisory`: kept for reference, never the record of truth).
- Every name/label is `null` when it can't be resolved. The console never shows the id in its place
  (ux U25): it drops that part of the line; ids appear in Technical details only.
- Errors: `422 invalid_params` (`point_id` / `spacecraft_id` missing, `receipt_time` or `at` not
  ISO-8601);
  `404 mission_not_found`. The read authorizes like Explore did (operate the mission).

## `POST /api/v1/missions/:mission_id/dev/space_packets` and `.../dev/tm_frames` (dev and test only, #780)

Development ingest: one packet or frame through the real ingest path, for seeding a dev mission and
for tests. **The routes exist only in dev and test**: `config :cadence_web, :dev_ingest_routes, true`
in `config/dev.exs` and `config/test.exs`, read at compile time by the router
(`CadenceWeb.Console.DevIngestRoutes`), so a prod release has no such route (a test builds a router
the prod way and finds none). A person's session and CSRF only; a service identity is refused
(`service_not_allowed`), like everywhere on this API, because no named caller needs one.

Body `{"space_packet": {"packet_hex" | "packet_base64", "source_ref"?, "source_endpoint_ref"?,
"spacecraft_id"?, "direction"?, "source_time"?, "receipt_time"?, "metadata"?}}`, or
`{"tm_frame": {"frame_hex" | "frame_base64", "frame_size"?, "secondary_header_length"?,
"ocf_length"?, ...}}`. 200 `{data: {raw_evidence, packet_records, transfer_frame_records,
protocol_anomalies, dispatch_decisions, outputs}}`. 422 `invalid_params` for a missing or malformed
body, or when the ingest refuses it (`details.ingest`, for example no active binding set).

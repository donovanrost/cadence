# Realtime: `/socket/console`

Status: **socket, `mission:<id>` invalidations and the `fleet` push implemented**. Live points
and uplink progress are **designed below and not built yet**; see "Planned".

## Connecting

```ts
import { Socket } from "phoenix";
const socket = new Socket("/socket/console", { params: { _csrf_token: csrfToken } });
socket.connect();
```

- Session-authenticated. Phoenix exposes the cookie session to the socket only when
  `_csrf_token` is valid, and `check_origin` is on. A bad or missing token means the connect is
  refused (the client sees repeated connection errors).
- Websocket only (no longpoll).
- Sign-out disconnects the socket. When the socket keeps failing to reconnect, call
  `GET /api/v1/session`. A `401` there means the session is gone, so redirect to sign-in.

## Topic `mission:<mission_id>`

Join authorization is the same as the REST mission routes (operate the mission in its own
organization). A refused join returns `{"reason": "mission_not_found"}` (or `"unauthenticated"`).

Join reply:

```json
{"mission_id": "mission_…", "resources": ["alarms", "catalog", "commanding", "dashboards", "data_sources",
  "events", "limits", "settings", "spacecraft", "telemetry"]}
```

### Event `invalidate` (server to client)

```json
{"resources": ["commanding", "telemetry"]}
```

This means "data in these areas changed; refetch the REST reads that depend on them". Events are
coalesced: at most one push per 500 ms window per channel, listing every resource that changed in
that window. Treat it as a hint. The client should also refetch after any reconnect, because
pushes are not replayed.

| resource | fires on |
| --- | --- |
| `alarms` | a point's limit state **changed** (transitions only, not every evaluation), or any alarm episode changed (raised, escalated, cleared, acknowledged, assigned, noted). Use this for the alarm and episode lists, the action queue and fleet state |
| `commanding` | command stages, requests, approvals, queue, release attempts, verifiers |
| `spacecraft` | spacecraft and profile configuration, packet bindings, app installations |
| `telemetry` | new samples committed (source watermark), backfills, revision-state changes. This fires about every 500 ms on live feeds, so throttle telemetry-driven refetches client-side |
| `contacts` | contact facts (scheduled/realized contacts, contact actions) and, once domain publishes it, reservation, plan and run changes. See contacts.md |
| `stations` | station availability windows (operator, provider or simulator). See contacts.md, S7 |
| `pass_results` | pass results (S9 close-out, provider results). See contacts.md, pass review |
| `attention` | mission "needs acknowledgment" items (DECISIONS #54: pass-resolution conflicts raised, acknowledged or resolved). Refetch the action queue and `/counts` |
| `limits` | limit definition changes |
| `events` | mission event changes |
| `catalog` | catalog revision changes |
| `data_sources` | data-source bindings and health |
| `dashboards` | dashboard documents and versions |
| `settings` | mission settings |
| `configuration` | mission change sets and revisions (see changes.md, which also covers `change_set_progress` and `config_runtime`) |
| `activations` | activation requests decided or resumed through the console (activations.md) |

Map these to the endpoint docs: each endpoint doc lists the `invalidate` resources that should
trigger its refetch.

### Event `fleet` (server to client, opt-in; owner api-ops)

Live fleet state for Now, so the matrix and tiles don't refetch `GET /fleet`.

- Start with `channel.push("fleet:subscribe", {})` (reply `ok`); stop with `fleet:unsubscribe`.
  Subscribe only while a screen shows the fleet. The subscription lasts until unsubscribe, leave
  or reconnect. **After every (re)join, subscribe again**, since a new channel process starts from a full snapshot.
- The first push after subscribing is a **full snapshot**: `full: true`, `seq: 1`, and every row.
  After that, each push has `full: false` and `seq` one higher than the last. You don't need
  `GET /fleet` while subscribed. If you ever see a gap in `seq`, unsubscribe and subscribe again.

```json
{"seq": 7, "full": false,
 "observed_at": "…", "stale_after_s": 900, "last_received_at": "…",
 "counts": {…}, "commands": {…}, "limits": {"configured": true},
 "spacecraft": [<full GET /fleet row>, …],
 "heard": {"spacecraft-earendil-312": "2026-11-08T02:41:15Z"},
 "removed": ["spacecraft-…"]}
```

- `counts`, `commands`, `limits`, `last_received_at` and `observed_at`: the same fields as `GET /fleet`, on
  **every** push (replace them wholesale). `commands.awaiting_viewer` is for this viewer.
- `spacecraft`: full rows that changed **materially** (state, limit state, worst point, `stale`, profile,
  geometry, name), plus new spacecraft. Replace your row by `id`.
- `heard`: `id → last_received_at` for rows whose **only** change is a newer receipt. Set that one
  field. These are batched onto the 10 s tick, so per-row `last_received_at` lags real receipts
  by up to 10 s (freshness is server-decided and flips arrive as material changes).
- `removed`: ids of deleted spacecraft. Drop those rows.
- Timing: material pushes come at most once a second, within about a second of an `alarms`,
  `spacecraft`, `commanding`, `limits` or `contacts` change. A **tick every 10 s** always pushes (possibly with no
  rows), which catches spacecraft going stale with no event. Treat it as a heartbeat too.
- The `invalidate` events still flow alongside. While subscribed, ignore `alarms`/`spacecraft`/
  `commanding` for the fleet read (keep them for the other reads).

### Topic `command_group:<mission_id>:<command_group_id>` (owner api-ops)

Live Uplink & verify for one group. Join authorization is the same as `mission:<id>`, plus the
group must exist (`{"reason": "command_group_not_found"}` otherwise).

- Event `group`: `{"seq", "group": <GET /command-groups/:id payload>}`. Sent once after join
  (`seq: 1`), then after any commanding change in the mission (at most once a second), **only when
  the view changed**. Replace your copy wholesale; `seq` increases by one per push.
- After a reconnect, rejoin; the first push is the full view again.

## Spacecraft live values (M8)

These are the shapes I plan to build, revised with fe-ops' comments (plans/ops.md).

- **Topic `spacecraft:<mission_id>:<spacecraft_id>` (M8)**, like `command_group:`: the console is
  addressed by mission, so the mission is in the topic. Joined while one spacecraft is open
  (Investigate B1). It needs the same access as `mission:<id>` (`operate_mission`). Join errors:
  `{"reason": "mission_not_found" | "spacecraft_not_found" | "too_many_points"}`.
  - **Join** payload `{"point_ids": [...]}`, at most 200 (`too_many_points` above that). An
    empty payload (or no `point_ids`) selects none: the reply has `points: []` and nothing is
    pushed until `points:set`.
    Reply `{"spacecraft_id", "mission_id", "points": [{"point_id", "unit", "type"}]}`.
    `type` is `numeric | enum | text`:
    - `uint`, `int` and `float` fields are `numeric`;
    - `bool`, or a parameter whose catalog type is enumerated, is `enum`;
    - `string` and `binary` are `text`.
    - An unknown point has `type: null` and `unit: null`.
  - **`points:set`** (client → server) `{"point_ids": [...]}` replaces the selection without
    rejoining. Reply `{:ok, {"points": [...]}}` (same shape as the join reply), or
    `{:error, {"reason": "too_many_points"}}`.
  - **Event `points`** `{"seq", "samples": [{"point_id", "value_json", "generation_time",
    "received_at", "limit_state"}]}`:
    - Triggered by the mission's telemetry invalidation and throttled to at most once a second.
      Latency is the ingest commit plus up to 1 s.
    - A point appears when its latest sample differs from the last one pushed. Order is commit
      order, so a backfilled sample can carry an older `generation_time`: insert by
      `generation_time`.
    - `value_json` is JSON text (64-bit safe).
    - `limit_state` is `critical | caution | nominal`, or `null` when no limit is evaluated for
      that point (distinct from no data, which simply has no sample).
  - `seq` restarts at 1 on every join, and the first push after a join is the current value of
    every selected point that has one. On reconnect, refetch the history window and continue from
    the next push. Nothing is replayed.
  - B2 (event log) has no stream of its own: refetch `/events` on the mission channel's
    `invalidate` (`alarms`, `contacts`, `commanding`, `telemetry`).
- (Done as `command_group:<mission_id>:<command_group_id>`, above.)

## `dashboard:<mission_id>:<dashboard_id>` (dashboards C1, api-ops)

Live pushes for one dashboard. The full proposal and client notes are in
`docs/apogee/plans/dashboards-live.md`; this is what the server does.

- **Join `{}`** (the shared-channel join). Authorization is D5's (`operate_mission`, active
  dashboard). Reply: `{dashboard_id, current_version}`. Errors `{reason}`: `mission_not_found`,
  `dashboard_not_found`, `dashboard_archived`, `unauthenticated`. Joined alone, only `version`
  events arrive.
- **`view:subscribe` / `view:set {runtime: {from, to, spacecraft_id}, refresh_ms}`**: `runtime` uses
  D5's grammar (null or absent fields mean the dashboard's defaults). `refresh_ms` is 1000–60000,
  or null for Off.
  - Reply: `ok {seq: 0}`, or `error {reason: "invalid_params", field: "range" | "spacecraft_id" |
    "refresh_ms"}` or `error {reason: "dashboard_unavailable"}`. The subscription is resolved
    before the reply, so a spacecraft from another mission is refused here.
  - Send it after every (re)join.
- **`view:unsubscribe {}`**: stops data pushes and stays joined.
- **`view {seq, full, version, resolved_at, context, snapshot | null, placements, removed}`**:
  - `full: true` with `seq: 1` after each subscribe or set and after a version change. `snapshot` is
    D5's, `placements` and `removed` are `[]`.
  - Otherwise `full: false`. `placements` holds only the placements whose DTO changed (replace them
    by `id`), `removed` the placement ids that are gone, and `context` is the new context.
  - `seq` goes up by one per push. On a gap, send `view:subscribe` again.
  - Data pushes happen only for a sliding (live) range with a `refresh_ms`. The server re-resolves
    every `refresh_ms` after the previous resolve and pushes only when something changed. Frozen
    ranges and Off get the full view only.
- **`version {current_version, saved_by: {kind, id, name} | null, saved_at, archived}`**: sent to
  every joined client when the dashboard is saved, restored or archived elsewhere (seen within
  about 250 ms). A subscriber then gets a `full` view, unless `archived: true`, which stops
  pushes.

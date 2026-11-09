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
  `GET /api/console/v1/session`. A `401` there means the session is gone, so redirect to sign-in.

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
| `limits` | limit definition changes |
| `events` | mission event changes |
| `catalog` | catalog revision changes |
| `data_sources` | data-source bindings and health |
| `dashboards` | dashboard documents and versions |
| `settings` | mission settings |
| `configuration` | mission change sets and revisions (see changes.md, which also covers `change_set_progress` and `config_runtime`) |

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
  `spacecraft`, `commanding` or `limits` change. A **tick every 10 s** always pushes (possibly with no
  rows), which catches spacecraft going stale with no event. Treat it as a heartbeat too.
- The `invalidate` events still flow alongside. While subscribed, ignore `alarms`/`spacecraft`/
  `commanding` for the fleet read (keep them for the other reads).

## Planned (with fe-ops, for M8)

These are the shapes I plan to build, revised with fe-ops' comments (plans/ops.md).

- Topic `spacecraft:<spacecraft_id>`, joined while one spacecraft is open (Investigate):
  `points` event `{"samples": [{"point_id", "value", "generation_time", "received_at", "limit_state"}]}`
  for that spacecraft's subscribed points, throttled. `value` keeps its exact type and
  `limit_state` uses the alarm vocabulary. The join payload `{"point_ids": [...]}` selects the
  points (capped at 200), and the join reply carries each point's `unit`.
- Topic `uplink:<command_request_id>` for live uplink and verify progress (Commanding flow).

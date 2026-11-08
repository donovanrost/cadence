# Realtime: `/socket/console`

Status: **socket and `mission:<id>` invalidations implemented**. Data-carrying pushes (fleet
deltas, live points) are **designed below and not built yet**; see "Planned".

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
| `alarms` | a point's limit state **changed** (transitions only, not every evaluation). Use this for the alarm list, the action queue and fleet state |
| `commanding` | command stages, requests, approvals, queue, release attempts, verifiers |
| `spacecraft` | spacecraft and profile configuration, packet bindings, app installations |
| `telemetry` | new samples committed (source watermark), backfills, revision-state changes. This fires about every 500 ms on live feeds, so throttle telemetry-driven refetches client-side |
| `limits` | limit definition changes |
| `events` | mission event changes |
| `catalog` | catalog revision changes |
| `data_sources` | data-source bindings and health |
| `dashboards` | dashboard documents and versions |
| `settings` | mission settings |

Map these to the endpoint docs: each endpoint doc lists the `invalidate` resources that should
trigger its refetch.

## Planned (with fe-ops, for M8)

These are the shapes I plan to build, revised with fe-ops' comments (plans/ops.md).

- `fleet` event on `mission:<id>`: `{"seq", "observed_at", "counts", "commands", "spacecraft": [<full
  GET /fleet row>]}`, containing only rows that changed since the previous push. `seq` increases
  by one per push on the channel. `GET /fleet` will return the channel's current `seq`, so the
  client can drop older pushes and refetch on a gap. Throttled to at most 1 per second.
- Topic `spacecraft:<spacecraft_id>`, joined while one spacecraft is open (Investigate):
  `points` event `{"samples": [{"point_id", "value", "generation_time", "received_at", "limit_state"}]}`
  for that spacecraft's subscribed points, throttled. `value` keeps its exact type and
  `limit_state` uses the alarm vocabulary. The join payload `{"point_ids": [...]}` selects the
  points (capped at 200), and the join reply carries each point's `unit`.
- Topic `uplink:<command_request_id>` for live uplink and verify progress (Commanding flow).

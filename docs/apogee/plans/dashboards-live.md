# Dashboards slice 7: live push (C1 proposal)

Owner: dashboards. For: api-ops (builds C1 after L6/L5), cc lead. Plan: `plans/dashboards.md` § Live data, step 2.
Today (step 1) the viewer refetches D5 on the mission channel's `invalidate` (`dashboards`, and for sliding ranges
`telemetry`, `limits`, `alarms`, `events`), at most once per refresh interval. C1 replaces that loop with
server pushes of the placements that changed. Conventions follow `realtime.md` (`fleet`, `command_group`).

## Topic `dashboard:<mission_id>:<dashboard_id>`
- **Join `{}`.** This is the console's shared-channel join; `acquireChannel` sends no join payload, as for
  `mission:`. Authorization is the same as D5: `operate_mission`, and the dashboard must exist and be active.
- **Join errors:** `{"reason": "mission_not_found" | "dashboard_not_found" | "unauthenticated"}`.
- **Join reply:** `{"dashboard_id", "current_version"}`.
- Join alone streams nothing except `version` events (below). The editor stays joined for those, while live values
  are paused.

### Client → server
- `view:subscribe {runtime: {from, to, spacecraft_id}, refresh_ms}`:
  - `from`/`to` use D5's grammar (`now-6h`/`now`, or ISO), and null means the dashboard's defaults.
    `spacecraft_id` is null or one of the mission's spacecraft.
  - `refresh_ms` is 1000–60000, or null for "Off" (no data pushes; document changes still push).
  - Reply `ok {seq: 0}`, or `error {reason: "invalid_params", field: "range" | "spacecraft_id" | "refresh_ms"}`.
  - The client sends it **after every (re)join** (the fleet rule): a new channel process starts from a full
    snapshot.
- `view:set {runtime, refresh_ms}`: replaces the subscription without rejoining. Same reply. The next push is
  `full`.
- `view:unsubscribe {}`: stop data pushes and stay joined (the editor does this).

### Server → client
- **`view`** `{seq, full, version, resolved_at, context, snapshot | null, placements, removed}`:
  - `full: true` (`seq: 1` after each subscribe or set, or after a version change): `snapshot` is the whole
    `WorkspaceSnapshot` exactly as D5 sends it, and `placements` / `removed` are `[]`.
  - `full: false`: `snapshot` is null. `placements` lists only the placements whose DTO changed (same placement
    shape as the snapshot's, replace by `id`), and `removed` lists placement ids that are gone (a repeat that
    shrank). `context` is the snapshot's context object (the live window moves) and replaces the client's copy.
  - `seq` goes up by one per push. On a gap the client sends `view:subscribe` again (it doesn't refetch D5).
  - `version` is the document version the data was resolved for.
- **`version`** `{current_version, saved_by {kind, id, name} | null, saved_at}`: sent to every joined client when the
  dashboard is saved, restored or archived elsewhere. Subscribed clients then get a `full` view for the new version.
  An archived dashboard sends `{archived: true}` here and stops pushing.

### Timing and cost
- Data pushes are driven by the dashboard's `RuntimeInvalidation`, filtered with the existing
  `RuntimeInvalidationRelevance`, and re-run with `resolve_mode: :live_tick` (only the affected requests). They come
  at most once per `refresh_ms`, and only when a placement's DTO changed. A frozen (absolute) range never gets data
  pushes.
- A subscriber gets a full push within about 1 s of subscribing. Document changes push within about 1 s.
- Subscribers with the same `(dashboard, version, runtime)` may share one resolver (`RuntimeCoordinator`). That's
  api-ops' call; it changes nothing on the wire.
- Payload: a full push is D5's snapshot (≤ 10k values per frame, as today). Deltas are usually a few placements.

## Client (dashboards; built against this, switched on when C1 lands)
- `viewer/useDashboardLive.ts` joins the topic, subscribes with the URL's runtime and refresh, sends `view:set` when
  they change, `view:unsubscribe` while editing, and resubscribes on a `seq` gap.
- `model/live-merge.ts` (pure, tested) applies `view` pushes to the snapshot.
- D5 still loads the head (`dashboard`, `can_edit`, `scope_options`) and the first snapshot. While the channel is
  subscribed, step 1's data-invalidation refetch is off. A `version` event raises the editor's "saved by someone
  else" callout directly.
- Until C1 ships, a single flag keeps the viewer on step 1.
- Not in C1: time-series appends (C2, plan step 3). Only if full placement deltas prove too large.

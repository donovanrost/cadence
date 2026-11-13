# Dashboards (owner: api-ops)

Console endpoints for dashboards (BACKLOG §11e, DECISIONS #76). The plan and the asks are in
`docs/apogee/plans/dashboards.md`.

## D0: `dashboard.author` capability

`GET /session` lists `dashboard.author` in `organizations[].capabilities` and the top-level
`capabilities` when `Policy :author_dashboards` passes for at least one of the organization's
missions (`Cadence.Dashboards.Capabilities`). Today that's any mission operator. Authoring routes
still enforce it per mission. People rows don't carry it.

## D5: `GET /api/console/v1/missions/:mission_id/dashboards/:dashboard_id`

Query: `from`, `to` (`now-6h` … `now` for a live sliding window, or ISO bounds for a frozen range
up to 31 days; both or neither) and `spacecraft_id` (one of this mission's spacecraft).

```json
{"data": {
  "dashboard": {"id": "…", "name": "Bus overview", "description": null, "tags": ["power"],
                "current_version": 12, "updated_at": "2026-11-13T02:51:00Z"},
  "can_edit": true,
  "scope_options": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312"}],
  "snapshot": {…} | null,
  "resolved_at": "2026-11-13T02:52:10Z"}}
```

- Wraps `Reads.Dashboards.DashboardPage.load/4`, with the runtime admitted by `OpsWorkspaceURL`.
  Only `from`, `to` and the spacecraft enter it.
- `snapshot` is `WorkspaceSnapshot.build/4`'s map, passed through unchanged. `null` means the
  dashboard was never made current and the viewer isn't an author: "This dashboard has no saved
  version yet."
- `current_version` is the current (published) version. `can_edit` means the viewer may author it.
  `tags` come from the document's `metadata.tags` (`[]` when absent). `scope_options` holds at
  most 1000 spacecraft.
- Reading doesn't record the dashboard as recently viewed. That's D6's record-view write.
- Errors:
  - `404 not_found`: unknown, archived, or another mission's dashboard.
  - `422 invalid_params` with `details.field`: `spacecraft_id` (not this mission's) or `range`
    (bad or one-sided `from`/`to`, or a range over 31 days).
  - `503 dashboard_unavailable`: the resolve failed.
- Invalidation: refetch on `invalidate` with `dashboards`, `telemetry`, `limits`, `alarms` or
  `events`.

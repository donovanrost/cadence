# Setup endpoints (Readiness, Spacecraft, Catalog, Profiles, People)

Conventions: [README.md](README.md). Requested shapes: `docs/apogee/plans/setup-shapes.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| S | `GET /missions/:mission_id/spacecraft` | **implemented** |
| R | `GET /missions/:mission_id/readiness` | planned. Backed by domain's `Cadence.Reads.Readiness.mission/2`; the shape in setup-shapes.md is the target |
| (2) | spacecraft detail, profiles list/detail/versions | planned |
| (3) | catalog databases/revisions/import runs, upload, import-run channel | planned |
| (4) | batch spacecraft validate + create | planned |
| (5) | org members, invitations, service identities | planned (`/organizations/:organization_id/...`) |

## `GET /api/console/v1/missions/:mission_id/spacecraft`

The Setup spacecraft directory. It is unpaginated (the client filters) and sorted by `scid`, then
`name`, with spacecraft lacking a SCID last. Refetch on `invalidate` with `spacecraft`.

```json
{"data": {"spacecraft": [
  {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312, "norad_id": null,
   "plane": 13, "slot": 12,
   "profile": {"id": "profile-…", "name": "Earendil Block 1", "version": 1},
   "routing_rule_count": 6,
   "ready": true,
   "last_received_at": null}
]}}
```

- `scid`: integer or null. `norad_id`, `plane` and `slot` are integers or null, read from
  spacecraft metadata (`norad_id`, `plane`, `slot`) until domain makes them first-class.
- `profile`: null when unbound. `profile.version` is the version the spacecraft is pinned to.
  `profile.name` may be null if the profile was deleted.
- `routing_rule_count`: active, enabled routing rules for this spacecraft. Under DECISIONS #3 this
  becomes the materialized count from the profile's rules.
- `ready`: has a SCID, a profile, and `routing_rule_count > 0`.
- `last_received_at`: newest telemetry or limit evaluation received, or null if never heard
  ("Awaiting first AOS"). It is the same source as `/fleet`. It replaces the requested
  `first_heard_at`, which needs a projection that doesn't exist yet.
- **Not in v1:** `configuration` (`active_version`, `draft_status`) from the requested shape. The
  configuration draft and activation model is being reworked into mission change sets
  (DECISIONS #1), so this field arrives with that seam instead of shipping a shape that is about
  to change.

Errors: `404 mission_not_found`.

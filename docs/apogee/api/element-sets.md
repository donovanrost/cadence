# Element sets (orbits)

Owner: **ground**. Issue #889 (slice 1 of #732). Design: `docs/pass-prediction-design.md` and
DECISIONS #114.

An element set is one spacecraft's orbit as SGP4 mean elements at an epoch. It arrives as a TLE or
an OMM. Cadence parses and validates it, then stores it as an immutable row together with the text
it came from.

- **History.** Every set is kept. A spacecraft's **current** set is the one with the newest
  epoch. A set with an older epoch is stored as history and doesn't replace the current one.
- **Idempotency.** The natural key is `(mission, spacecraft, epoch, content_sha256)`. Sending the
  same set again stores nothing and answers with the stored row.
- **Hashing.** `content_sha256` is the SHA-256 of `raw`, the text as stored.
  - A TLE is stored as its lines with trailing whitespace removed, joined by `\n`, so CRLF line
    ends and trailing blanks don't make it a different set.
  - A JSON OMM is stored as the object re-encoded with its keys sorted.
  - A KVN OMM is stored as its non-blank lines.

Prediction (slices 2 and 3) reads the current set. These endpoints only store and read element
sets.

## Auth

- **Persons** use the session cookie, plus CSRF on writes.
- **Writes** need mission management: an organization admin, or a mission admin of this mission.
  Any member who can open the mission can read.
- **Service identities** reach none of these endpoints; they get `403 service_not_allowed`
  (`CadenceWeb.Console.ServiceAccess`). The catalog feed will be the first service to opt in.
- **`source`** is `manual` when a person stores the set and `api` when a service does.

## The element-set object

```json
{
  "id": "elset_…",
  "spacecraft_id": "spacecraft-earendil-001",
  "format": "tle",
  "source": "manual",
  "epoch": "2008-09-20T12:25:40.104192Z",
  "object_name": "ISS (ZARYA)",
  "norad_id": 25544,
  "element_set_number": 292,
  "elements": {
    "mean_motion_rev_per_day": 15.72125391,
    "eccentricity": 0.0006703,
    "inclination_deg": 51.6416,
    "raan_deg": 247.4627,
    "arg_perigee_deg": 130.536,
    "mean_anomaly_deg": 325.0288,
    "bstar": -1.1606e-5,
    "mean_motion_dot": -2.182e-5,
    "mean_motion_ddot": 0.0
  },
  "content_sha256": "…",
  "raw": "ISS (ZARYA)\n1 25544U …\n2 25544 …",
  "received_at": "2026-11-27T10:00:00.000000Z",
  "created_by": {"kind": "user", "id": "…", "name": "Mira K."}
}
```

- **Mean motion** is in revolutions per day (Kozai, as SGP4 takes it).
- **`mean_motion_dot`** is ṅ/2 in rev/day². **`mean_motion_ddot`** is n̈/6 in rev/day³.
- **`bstar`** is in inverse Earth radii.
- **Optional fields.** `object_name`, `norad_id` and `element_set_number` are `null` when the
  message doesn't carry them.
- **`created_by`** is the actor as `{kind, id, name}`, like every other stored actor.

## The set in a request

Each request carries exactly one of these:

- **`tle`**: text, as two element lines or as three lines with a title line first (`0 NAME` or
  `NAME`). The text is checked as follows:
  - each element line must be 69 columns, start with its line number, and have a mod-10 checksum
    in column 69;
  - the catalog number must be the same on both lines;
  - Alpha-5 catalog numbers are read.
- **`omm`**: an object (CCSDS OMM JSON, as CelesTrak or Space-Track emit it, with numbers or
  numeric strings), or KVN text (`KEY = value` lines; `COMMENT` lines and units in brackets are
  ignored).
  - **Required:** `EPOCH` (UTC, calendar or day-of-year form), `MEAN_MOTION`, `ECCENTRICITY`,
    `INCLINATION`, `RA_OF_ASC_NODE`, `ARG_OF_PERICENTER`, `MEAN_ANOMALY` and `BSTAR`.
  - **Optional:** `MEAN_MOTION_DOT` and `MEAN_MOTION_DDOT` default to 0.
  - **Theory:** a `MEAN_ELEMENT_THEORY` other than `SGP4` is refused.

## Endpoints

### `POST /missions/:mission_id/spacecraft/:spacecraft_id/element-sets`

Body: `{"tle": "…"}` or `{"omm": {…} | "…"}`.

- `201 {"data": <element set>, "meta": {"result": "created"}}`.
- `200 {"data": <stored element set>, "meta": {"result": "unchanged"}}` when the same set is
  already stored.
- `404 spacecraft_not_found`, `403 forbidden`, `422 invalid_params` (neither or both of `tle` and
  `omm`), or a refusal below.

### `POST /missions/:mission_id/element-sets`

This is the bulk endpoint for a fleet. Platform's fleet seed uses it.

Body: `{"element_sets": [{"spacecraft_id": "…", "tle": "…"} | {"spacecraft_id": "…", "omm": …}]}`,
with 1 to 1,000 items.

```json
{"data": {
  "results": [
    {"index": 0, "spacecraft_id": "…", "result": "created", "element_set": {…}},
    {"index": 1, "spacecraft_id": "…", "result": "unchanged", "element_set": {…}},
    {"index": 2, "spacecraft_id": "…", "result": "refused",
     "error": {"code": "element_set_bad_checksum", "message": "…", "details": {"field": "line1", "expected": 7}}}
  ],
  "counts": {"created": 1, "unchanged": 1, "refused": 1}
}}
```

- **One answer per item.** Each item is answered on its own, in request order (`index`). One bad
  item doesn't refuse the others.
- **Unknown spacecraft.** An item that names a spacecraft the mission doesn't have is refused with
  `spacecraft_not_found`.
- **Malformed items.** An item without a `spacecraft_id`, or without exactly one of `tle` and
  `omm`, is refused with `invalid_params`.
- **Repeats.** An item that repeats an earlier item of the same request answers `unchanged` with
  that item's row.
- **Whole-request refusals.** `422 element_set_batch_too_large` over 1,000 items;
  `422 invalid_params` for an empty or missing list.
- **Cost.** The stored rows are written in one transaction. The server reads the named spacecraft
  in batches of 100 and the already-stored keys in one query, then writes in batches of 500. It
  never queries per spacecraft.

### `GET /missions/:mission_id/spacecraft/:spacecraft_id/element-sets`

This is the spacecraft's history, newest epoch first (ties broken by id).

- **Query:** `?limit=` (1–200, default 50) and `?cursor=` (the previous page's `next_cursor`).
- **Answer:** `{"data": [<element set>…], "meta": {"next_cursor": "…" | null}}`.
- **Stable pages.** A set stored while a client pages doesn't move a page boundary.
- **Errors:** `422 invalid_params` with `details.field` = `cursor` or `limit`, and
  `404 spacecraft_not_found`.

### `GET /missions/:mission_id/spacecraft/:spacecraft_id/element-sets/current`

- **Answer:** `{"data": <element set>}`, the newest epoch.
- **No set yet:** `{"data": null}` when the spacecraft has none.
- **Errors:** `404 spacecraft_not_found`.

## Refusals

Every refusal answers 422 (or is the item's `error` in a bulk answer). `details.field` names the
field, and `details.message` says why.

| Code | When |
| --- | --- |
| `element_set_unparseable` | The text isn't a TLE or an OMM, a line has the wrong length or line number, a field isn't a number (or is a JSON integer beyond 10^15), a required OMM key is missing, or the epoch isn't a time |
| `element_set_bad_checksum` | A TLE line's column 69 isn't the mod-10 sum of its digits (`details.expected`) |
| `element_set_catalog_number_mismatch` | The two TLE lines name different catalog numbers |
| `element_set_non_physical` | Eccentricity outside [0, 1), mean motion ≤ 0, inclination outside [0, 180]°, or RAAN, argument of perigee or mean anomaly outside [0, 360]° |
| `element_set_epoch_in_future` | The epoch is more than a day after the server's clock |
| `element_set_unsupported_mean_element_theory` | An OMM's `MEAN_ELEMENT_THEORY` isn't SGP4 |
| `element_set_unsupported_reference` | An OMM supplies `CENTER_NAME` other than `EARTH`, `REF_FRAME` other than `TEME` or `TIME_SYSTEM` other than `UTC` (`details.field`, `details.expected`); each key is optional |
| `element_set_batch_too_large` | A bulk request carries more than 1,000 items |

Deep-space sets (a period of 225 min or more) are stored. Prediction refuses them with
`deep_space_not_supported` until the SDP4 slice lands (#732, slice 7).

# Pass prediction: element sets, SGP4 and station visibility (#732)

Status: agreed (CTO, 2026-11-26). DECISIONS #114, superseding #4.

## Problem

Cadence has no orbit model. A pass exists only as a provider opportunity, and the simulator
invents those by hashing `(seed, craft)` with no station geometry
(`CadenceSimulator.Provider.generate_opportunities/5`). Elevation is `nil` everywhere. Planning
and Book a pass therefore work on numbers that no real geometry backs.

## Decision

1. **SGP4 in pure Elixir, in a new dependency-free package `packages/sgp4`.** It is a port of
   Vallado's reference implementation (2006 revision, WGS72, `improved` mode), tested against
   Vallado's full verification set (`SGP4-VER.TLE` / `tcppver.out`), including its error cases.
   - **Not `ex-orbital-dynamics`.** It parses TLE and OMM as metadata only, with no SGP4 or
     SDP4. Its propagators are two-body and J2 over Cartesian states, and it pulls in Nx. It also
     ships about 4,500 modules of planning code that Cadence would not use. DECISIONS #4 named it
     only as a candidate.
   - **Not a Rust NIF.** The benchmark below meets the budget without native code, so the build
     doesn't need a Rust toolchain or precompiled NIF artifacts.
2. **Near-earth (SGP4) first, deep space (SDP4) as its own slice.** An element set with a period
   of 225 min or more is stored, but prediction refuses it with `deep_space_not_supported` until
   the SDP4 slice lands. Every current fleet (Earendil, QA, scale) is LEO.
3. **Predicted passes are stored rows, recomputed incrementally.** They are not computed on read.

## Benchmark

The script is `dev/pass-prediction-benchmark/sgp4_pass_search.exs`. It is a prototype of the
package plus the pass search below. It starts with an accuracy gate: Vallado case 00005 at 0,
360, 720 and 1,080 min, which it matches to under 1 m (in practice 0.000 m). The fleet is
synthetic LEO (500–600 km, 53° and 97.6°, spread RAAN and anomaly), with 15 stations at
latitudes from 78°N to 72°S, a 5° mask, a 60 s coarse step, and refinement to 1 s.

| Fleet × 15 stations × 7 days | Wall time | Passes | SGP4 evaluations |
| --- | --- | --- | --- |
| 500 spacecraft | 5.08 s | 271,563 | 13.0 M |
| 1,000 spacecraft | 11.35 s | 543,120 | 26.0 M |

These are laptop 1 numbers: M1, 8 cores, OTP 29. The evaluation count includes every SGP4
propagation: one per spacecraft per grid point (time zero included), plus refinement and the
search past each end of the window. Passes that cross either end of the window are counted.
Following the #217 measurement rule, the recorded pair will be re-run on laptop 2 and posted on
#177.

Since slice 2 the script runs `packages/sgp4` (`Sgp4.Passes.search/5`) instead of the
prototype, with stations on the WGS84 ellipsoid rather than a sphere. Each pass costs three more
propagations, for the elevation at TCA and the azimuth at AOS and LOS. On the same laptop it
finds 275,361 passes for 500 spacecraft in 5.42 s (13.9 M evaluations), and 550,815 for 1,000
in 11.12 s (27.8 M). The ellipsoid moves the stations, which accounts for the 1.4% more
passes.

- **CPU cost.** About 80 ms of CPU per spacecraft-week across 15 stations, so re-predicting one
  spacecraft after a new element set takes well under a second.
- **Where the time goes.** Refinement is 61% of the evaluations (AOS and LOS bisection, TCA by
  golden section). Brent's method or parabolic TCA would cut that if we ever need to, but the
  budget doesn't ask for it.
- **A Rust NIF would be faster still**, roughly an order of magnitude per evaluation. That would
  matter only for much larger fleets or a 1 s coarse step, so we revisit it only if a
  measurement says so.

## Model

### Element sets (slice 1)

The table is `orbit_element_sets`. Each row is immutable and history is kept:

- `organization_id`, `mission_id`, `spacecraft_id` (scoped FK);
- `format`: `omm` or `tle`;
- `source`: `manual` or `api` now, `catalog` later;
- the raw text as received;
- the parsed mean elements as typed columns: epoch, mean motion (Kozai), eccentricity,
  inclination, RAAN, argument of perigee, mean anomaly, B*, ṅ/2, n̈/6, NORAD id, element-set
  number;
- `content_sha256`, `received_at`, `created_by`.

Each spacecraft's current element set is the valid one with the newest epoch. A row with an
older epoch is kept as history and doesn't replace the current one. The natural key is
`(mission_id, spacecraft_id, epoch, content_sha256)`, so re-sending the same set is idempotent.

**API (`/api/v1`)**, with session and CSRF for persons. A service identity is denied unless the
action opts in; the catalog feed will be the first one to opt in.

- `POST /missions/:mission_id/spacecraft/:spacecraft_id/element-sets`: one OMM (JSON or KVN) or
  one TLE (two or three lines).
- `POST /missions/:mission_id/element-sets`: bulk for a fleet. A list of `{spacecraft_id, omm |
  tle}`, answered per item. Platform's fleet seed sends orbits through this endpoint (#706).
- `GET /missions/:mission_id/spacecraft/:spacecraft_id/element-sets`: history, cursor-paged.
  Also a `current` read.

Validation refuses an unparseable element set, a bad checksum, a non-physical element
(eccentricity outside [0, 1), mean motion ≤ 0), and an epoch more than a day in the future.

### Station geometry (slice 2)

Prediction needs each station's WGS84 geodetic latitude, longitude and height, plus an elevation
mask. Cadence stores no station location today.

- **Location.** Location becomes typed columns on the station record, reported by the provider
  adapter where the provider gives one (the simulator will). Otherwise a mission admin sets it.
- **Mask.** Each station gets an elevation mask, with a mission default of 5°. A per-azimuth
  horizon mask is a follow-up.
- **Which table.** The columns go on whichever station table survives #128's deletion of the
  legacy Communications app. This is being settled with console now. There is no third station
  table.

### Propagation and visibility (slice 2)

For each spacecraft and its current element set, `Sgp4.init/1` runs once. Then:

- **Coarse grid.** Positions are computed on a coarse grid. The step is 60 s for LEO, or a
  quarter of the shortest pass above the mask if that is smaller. They are rotated TEME→ECEF by
  GMST (IAU-82). Polar motion is ignored because its effect is under 20 m. All stations are
  evaluated from the same position, so one SGP4 call serves all 15 stations.
- **Refinement.** For each station, a sign change of `sin(el) − sin(mask)` brackets an AOS or a
  LOS. Each bracket is refined by bisection to 1 s, and TCA is found by golden section to 1 s.
- **Output per pass:** AOS, TCA, LOS, maximum elevation, and azimuth at AOS and at LOS.
- **Passes at the window's ends.** A pass that overlaps the window is found whole. If the
  spacecraft is above the mask at the window start, the search steps back until it is below,
  then bisects to the real AOS. If a pass is still open at the window end, the search steps on
  until LOS. Both directions are bounded by the spacecraft's synodic period, 2π / (n − ω⊕): the
  time for it to come round again relative to the rotating earth, even when it co-rotates. No
  pass is longer at any near-earth period or mask. That is about 100 minutes in LEO, and at most
  about 267 minutes just under the 225-minute deep-space limit, where a single pass can last
  well over an hour. If no crossing is found within the bound, the search fails explicitly for
  that pass (`pass_not_bracketed`). It never stores the bound as an AOS or LOS. The benchmark
  gates on a 220-minute equatorial orbit straight above a station, whose pass runs from about
  −38 to +38 minutes. In the store (slice 3), the daily horizon extension starts its search at
  the AOS of the last stored pass on each spacecraft and station pair and replaces passes from
  there, so a pass that crosses the old horizon is replaced, not stored twice.
- **Short passes.** A pass shorter than the coarse step can fall between two grid points and be
  missed. That is acceptable because such a pass is shorter than any schedulable contact. The
  bound is documented and tested.
- **Accuracy.** SGP4's own error dominates: about 1 km at epoch, growing a few km per day. AOS
  and LOS are therefore good to a few seconds near epoch and degrade with element-set age, which
  is why the console shows the age. The station ellipsoid and refraction are below that error.

This runs in `Task.async_stream` over spacecraft, bounded by schedulers, in a supervised job,
never in a request.

### Predicted pass store (slice 3)

The table is `predicted_passes`. Each row holds:

- `organization_id`, `mission_id`, `spacecraft_id`, `ground_station_id`;
- `element_set_id` (the element set the pass was computed from);
- `aos`, `tca`, `los`, `max_elevation_deg`, `aos_azimuth_deg`, `los_azimuth_deg`;
- `computed_at`.

Indexes are `(mission_id, ground_station_id, aos)` and `(mission_id, spacecraft_id, aos)`.

- **Horizon.** The horizon is rolling: 7 days by default, with a mission setting of up to 14.
- **Size.** That comes to about 270k rows per week at 500 × 15, and about 1.1M at 1,000 × 15
  over 14 days.
- **Bounded at any fleet size.** Passes that ended more than 7 days ago are pruned, so the table
  holds at most the horizon plus 7 days. Provider opportunities and bookings keep their own
  records, so pruning a predicted pass loses no contact history.

Recompute is incremental:

| Trigger | Recomputes |
| --- | --- |
| New current element set | That spacecraft: delete and insert its future passes in one transaction |
| Station location or mask change | That station, for all spacecraft |
| Daily horizon extension | One more day for every spacecraft |
| Full mission (seed, admin) | Everything, batched |
| Daily prune | Deletes passes that ended more than 7 days ago (what planning history reads) |

Writes use `Cadence.Persistence.BulkInsert` (#872): typed arrays and one statement per
2,000 rows. A request path never queries per spacecraft. Reads are by mission and window, paged.

### Use (slices 4 and 5)

- **Planning and Book a pass** read predicted passes for geometry: elevation, TCA and the pass
  window.
- **Provider opportunities stay the source of truth for what can be booked.** Each one is
  matched to the predicted pass with the same spacecraft and station and an overlapping window.
  An opportunity that matches no predicted pass is flagged `no_predicted_pass`. That points to a
  stale element set, a wrong station location, or a provider error.
- **Providers get the orbit from Cadence (slice 5a, #968).** A real ground network doesn't log
  in to its customer's ops system for ephemeris. The customer hands it over, or the network
  looks the spacecraft up by NORAD id. Cadence does the same (option C, agreed with platform and
  the CTO on 2026-11-27):
  - **Capability.** Each provider's capabilities declare `orbit.source`, either
    `accepts_ephemeris_upload` or `looks_up_by_norad_id`. A provider that declares nothing is
    read as lookup.
  - **Push.** When an element set becomes a spacecraft's current one, a durable job, staged with
    the pass-prediction job, uploads it as an OMM to each bound upload provider. It goes through
    the provider contract (`PUT /provider/v1/spacecraft/:ref/ephemeris`), idempotent per content
    hash. A failed upload is retried with backoff. The push is the re-sync: there is one source
    of truth, and a failed or stale push is exactly what `no_predicted_pass` catches.
  - **Lookup providers.** Nothing is sent to them. A current element set without a NORAD id is
    recorded as `norad_id_missing` for that binding and counted on the providers read, never
    skipped silently.
  - **State.** Each (provider, spacecraft) pair is recorded as `uploaded`, `failed`, `lookup` or
    `norad_id_missing`.
- **The simulator (slice 5b, #893)** generates its opportunities from predicted passes computed
  by the same package, from the element sets uploaded to it. Dev and tests then run on real
  geometry. This replaces `generate_opportunities/5`'s hash. Since 5a, the simulator declares
  `accepts_ephemeris_upload` and stores each upload. A scenario whose `orbit_readiness.source_kind`
  is `uploaded` is ready only for spacecraft with an upload at most 14 days old.

### Console (slice 6, a console issue)

Console builds this slice. Ground owns the API contract it reads.

- **Spacecraft.** A spacecraft gets an Orbit section: its current element set (format, epoch,
  age, source) with history, and its predicted passes (AOS, LOS, maximum elevation, station),
  paged.
- **Elevation.** Elevation is shown wherever it reads "not available" today.
- **No flight dynamics in the browser.** It stays that way: the console reads the server's
  passes.

## Slices

Each slice becomes a sub-issue of #732 under #211 once this note is agreed.

1. **Element-set store and API**, including bulk. This also closes the fleet-seed gap on #706.
2. **`packages/sgp4`** with the Vallado verification set, plus **station geometry** and the
   **visibility search**.
3. **Predicted-pass store and recompute** (jobs, triggers, horizon, pruning), measured at 500 and 1,000
   on laptop 2 and recorded on #177.
4. **Planning and Book a pass integration**, with the opportunity ↔ predicted-pass match and the
   flag.
5. **Simulator.** (5a, #968) Cadence uploads each spacecraft's current element set to its upload
   providers. Lookup providers are checked for a NORAD id. (5b, #893) The simulator's
   opportunities come from predicted passes over the uploaded sets.
6. **Console** Orbit section and elevation. This is a console issue (frontend, not a Codex agent);
   ground supplies the API contract.
7. **SDP4** (deep space).

A catalog feed (Space-Track or CelesTrak) and per-azimuth horizon masks are follow-ups outside
#732.

## Settled with the CTO (2026-11-26)

- The default elevation mask is 5°, and it can be set per station.
- Slice 6 goes to console.
- Slice 3 includes pruning.
- The station table is settled with console, with no third table.

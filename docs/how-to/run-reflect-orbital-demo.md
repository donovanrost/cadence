---
title: Run the Reflect Orbital Demo
tags: [how-to, demo, constellation, ground-network]
status: active
created: 2026-10-19
updated: 2026-10-19
---

# Run the Reflect Orbital Demo

This development fixture creates **Reflect Orbital → Earendil** in the existing
Cadence database. It is a synthetic constellation rehearsal for an interview,
inspired by [Reflect Orbital's published constellation ambitions](https://www.reflectorbital.com/).
It is not their spacecraft database, flight architecture, ground-network contract,
or an OpenC3 COSMOS integration.

## Start and seed

Run the private worktree stack from the repository root. See
[Per-worktree development environment](../dev-environment.md) for prerequisites and ports.
The default local user is `admin@example.com`; set `EARENDIL_DEMO_EMAIL` before seeding
to use another existing account.

```sh
dev/stack up
```

`up` starts the independent simulator, migrates both stores, runs the Reflect Orbital
and QA seeds, and starts the named Phoenix node and console. The simulator binds a
slot-specific loopback port and stores its scenario, run, delivery profiles, and
reservations under `var/reflect_orbital/provider.ets`. Its provider token is private
to this worktree in `mise.local.toml`. Use `dev/stack status` for the URLs.

The seed is rerunnable: it uses stable identities, reuses the simulator run and
delivery profiles, and reconciles this fixture’s 500 spacecraft to the complete demo database.
Re-running it intentionally restores the fixture’s catalog, telemetry and commanding inputs.
It does not delete or reset other organizations. It grants the chosen existing
user organization-admin membership in Reflect Orbital. A stopped simulator run
is reported as an error rather than silently replaced. Run `dev/stack down` when
finished; the persisted demo remains available.

## What is configured

| Area | Demo configuration |
| --- | --- |
| Fleet | EARENDIL-001 through EARENDIL-500, unique CCSDS TM SCIDs 1–500 |
| Orbit metadata | 20 planes × 25 spacecraft; 625 km, 97.9° inclination, phased RAAN/anomaly |
| Bus | Shared version-pinned Earendil Block 1 profile; TM downlink, TC uplink, 1,115-byte frames, VC 0 |
| Payload metadata | Solar reflector; 475 deployed, 25 stowed for commissioning; illumination disabled |
| Catalog | Unmodified `dev/catalogs/demo_spacecraft.yaml`: 10 telemetry packets and 27 commands |
| Ground network | 10 synthetic sites with 38 modeled antennas, synchronized through the provider HTTP API |
| Delivery | 10 version-pinned TCP ingress profiles/transports on loopback ports derived from `EARENDIL_INGRESS_BASE_PORT` |
| Routing | 500 provider spacecraft mappings; primary and backup routes for each spacecraft |
| Scheduling | Deterministic synthetic visibility, 97-minute cadence, eight-minute windows, bounded jitter |
| Access | Existing authenticated organization and mission routes; no demo-only web routes |

The ten locations are Svalbard, Troll, Fairbanks, Kiruna, Hawaii, Santiago,
Punta Arenas, Hartebeesthoek, Perth, and Invercargill. Coordinates are approximate
location metadata; the sites, antenna sizes, capacities, frequencies/rates, and
orbital elements are illustrative assumptions. No external ground provider is
connected. Orbit metadata is not propagated to calculate passes.

Each site has a named delivery gateway. Routing selects a delivery gateway;
the station/antenna is selected from the provider's opportunity results at
reservation time. Gateway naming does not restrict a route to a particular
physical site. The simulator controls antenna conflicts and contact lifecycle.

The simulator's optional `telemetry_profile.spacecraft_frames` maps provider
spacecraft references to SCID/VCID values. The fixture supplies all 500 mappings,
so contacts no longer emit SCID zero for every spacecraft. Unconfigured scenarios
retain the previous default; explicit legacy data-plane values take precedence.

## Presenter walkthrough

1. Sign in at Cadence at the Phoenix URL from `dev/stack status`. From platform administration,
   open **Organizations → Reflect Orbital → Open Organization**.
2. Open **Earendil's spacecraft directory** (`/missions/mission-earendil-demo/spacecraft`).
   Show 500 assets, the shared profile, unique identities, and pagination/search.
3. Open EARENDIL-001 and its configuration. Show the versioned catalog, APID
   selection, frame interpretation, and primary/backup delivery routes.
4. Open **Ground Stations** (`/missions/mission-earendil-demo/comms/ground-stations`)
   and **Providers** (`/missions/mission-earendil-demo/comms/providers`).
   Show synchronized fleet/site inventory and the organization account's mission grant.
5. Open **Contacts** (`/missions/mission-earendil-demo/ops/contacts`)
   or **Ops → Requirements** to search provider-owned opportunities. Use a future
   two-hour horizon; synthetic windows are intentionally not accelerated.

The seed saves command and telemetry configurations for all 500 assets. All 10
APIDs are selected, including housekeeping, thermal, EPS, ADCS, communications,
payload, science, stress-test and debug definitions. Telemetry uses the managed
runtime source endpoint selected by both scheduling routes. The separate provider
mapping supplies the spacecraft reference used to reserve contacts.
The simulator loads the same YAML as Cadence.

To update an already seeded fleet without recreating the network:

```sh
cd apps/cadence_web
mix run --no-start ../../dev/reflect_orbital_configure.exs
```

After an importer fix, append `--reimport` to create a new catalog revision from
the same YAML and assign it to the saved configurations. Activate the new saved
revisions with the activation command below; the previously reviewed model is
retained unchanged.

Activate the fleet in the existing named development server (`dev/stack up`),
from the repository root:

```sh
mise exec -- env ERL_EPMD_ADDRESS=127.0.0.1 elixir --sname "earendil_setup_$CADENCE_DEV_SLOT" --cookie "$CADENCE_ERLANG_COOKIE" --erl '-kernel inet_dist_use_interface {127,0,0,1}' dev/reflect_orbital_activate.exs --single-operator
```

**`--single-operator` explicitly changes only Earendil’s activation setting to
direct activation.** It does not change the organization default. This option was
approved for the local interview demo. Omit it to retain an existing policy;
independent approval remains required if direct activation has not been selected.
The command is rerunnable and skips activation when every desired revision is
already active.

One governed activation admits the exact 500 saved revisions together. A changed
revision rejects the whole batch. The implementation bounds the fleet at 500
spacecraft, 1,000 source endpoints and 4 MiB of activation metadata. Command
lookups accept the same bounded fleet metadata; ordinary activation metadata
retains its 64 KiB lookup bound. The script verifies applied telemetry stamps,
5,000 packet dispatch bindings, the running generation, and all 27 command
catalog definitions for each spacecraft.

Activation enables decoding and command preparation. Live downlink still needs a
scheduled active contact. The provider fixture provisions downlink delivery;
actual command transmission requires an uplink transport/contact. No commands are
sent by the setup. QuestDB is needed for telemetry history.

### Command preparation

Open the **Commanding workspace** (`/missions/mission-earendil-demo/ops/commands/workspace`).
Search for a spacecraft such as `EARENDIL-001` and select its runtime target, which
shows `SCID 1`. The separate `EARENDIL-001 TT&C` result is the provider mapping;
use the target with the spacecraft's SCID for the command rehearsal.

Select `NOOP` to show automatic validation, or `SET_MODE` to demonstrate argument
entry. Search and select additional spacecraft to prepare up to 25 targets at a
time. `EARENDIL-500` is available through the same search. The workspace groups
identical active model manifests into shared command evidence, so the full fleet
remains available within the catalog response bounds. Different model manifests
retain separate compatibility checks.

The demo supports command preparation and queueing. A queued command can only
transmit when an appropriate uplink transport/contact is configured; the fixture's
downlink connections do not provide that uplink.

The mission overview shows a bounded 25-spacecraft preview and whole-fleet
readiness totals; the paginated Spacecraft directory is the complete inventory.
The seed verifies unique SCIDs and two schedulable provider routes for every asset.

COMMS Overview and Validation scan the fleet in batches of 100, with a ceiling of
10,000 records per resource kind. Overview shows the total finding count and a
bounded preview. Validation provides 20 findings per page, with blocking issues
first. The downlink fixture can report warnings about optional advanced protocol
behaviors; those warnings do not mean the COMMS feature or telemetry decoder is
unavailable.

## Live telemetry dashboard rehearsal

After activating the fleet, run this from the repository root in a separate
terminal, with Cadence and QuestDB already running:

```sh
mise run earendil-live
```

This starts **EARENDIL-001 through EARENDIL-010 at 1 Hz per packet family**.
Each spacecraft emits all ten packet families from the assigned demo YAML every
second: 100 packets/second across the ten vehicles. The other 490 spacecraft
remain configured and selectable, with no simulated live feed.

Use `mise run earendil-live -- --craft 500 --shape peak` for all 500
configured spacecraft, or `--shape average --per-site 8` (or `16`) for up to
that many spacecraft per site. The selected spacecraft must be configured and
activated on the target Cadence node. Additional rehearsal
paths use dedicated listeners at port `43000 + SCID`. For the simulator's
standalone 1,000-path benchmark, see [Measure simulator contact load](measure-simulator-load.md).

The simulator sends CCSDS TM frames over the ten local TCP ingress paths. Cadence
performs normal frame processing, database-driven decoding, current-value updates,
monitoring, and history persistence. Values are synthetic generic spacecraft data,
not Reflect Orbital flight telemetry. The live task uses info-level server logging
to avoid flooding the development terminal with per-packet SQL; warnings and errors
remain enabled. Restart Cadence to restore its configured logging level.

Managed QuestDB writes use bounded HTTP ingestion batches at the slot-specific
`CADENCE_QUESTDB_HTTP_ENDPOINT`. Reads continue through the SQL API. The migrated table's timestamp and
idempotency key retain retry deduplication. Counters outside QuestDB's signed LONG
range use the lossless JSON integer representation; these values remain readable
but do not participate in native numeric aggregates.

The task creates six native dashboards and a 30-second rotating wallboard playlist:

- **Fleet Watch** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-fleet`)
- **Spacecraft Overview** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-overview`)
- **Electrical Power** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-power`)
- **Thermal Control** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-thermal`)
- **Attitude & Pointing** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-attitude`)
- **Communications & Payload** (`/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-comms-payload`)

Use the dashboard's spacecraft selector to switch subsystem views. All views
refresh every second and show five-minute receipt-time trends. Open the dashboard
directory to present **Earendil — Demo Rotation**. Rerunning the task reuses the
saved dashboards and playlist, preserving manual dashboard edits.
The playlist presents published snapshots and refreshes on each entry change or
manual refresh; open an individual dashboard for continuous live updates.

Startup probes QuestDB and saves its supported query capabilities before creating
the views. Trend charts use native decimation to preserve the range of samples
that arrive together after TCP buffering. To intentionally restore the fixture's
dashboard definitions, run `EARENDIL_REBUILD_DASHBOARDS=1 mise run earendil-live`.
After a server restart, allow time for the ten telemetry partitions to recover
their recorded state before the feeds start. This can take several minutes after
repeated rehearsals, so start the feed before the presentation.

For uninterrupted presentation, the task creates two-hour **manual rehearsal
contacts**, associated with the ten synthetic ground sites. These are explicitly
labeled continuous simulations; they are not provider-booked orbital passes.
They occupy the ten ports starting at `EARENDIL_INGRESS_BASE_PORT` while active, so do not book overlapping provider
contacts onto the same gateways during the rehearsal. The provider simulator's
ordinary eight-minute visibility windows remain available for a separate scheduling
walkthrough.

The live process exits when its contacts end. Stop it earlier with Ctrl-C; saved
dashboards and recorded history remain. Rerunning reuses unexpired rehearsal
contacts, or creates new ones after expiry. Set `EARENDIL_DEMO_CONTACT_SECONDS`
before starting to choose a new contact duration between 60 and 28,800 seconds
(default 7,200). An existing contact retains its original end time.

## Connection-refused warnings

Cadence and the simulator are separate processes. If the simulator exits, provider
polling retries the slot's `EARENDIL_PROVIDER_URL` and Req reports `connection refused`.
Run `dev/stack up` to restart it; the persisted scenario and run are reused. Check
`dev/stack status` and the logs in `var/stack/` when a service does not recover.

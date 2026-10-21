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

Run these commands from the repository root in separate terminals. Postgres and
an existing Cadence user are required. The default local user is
`admin@example.com`; set `EARENDIL_DEMO_EMAIL` to use another existing account.

Start OrbStack (or the configured Docker engine), then the local telemetry history
and observability services. The repository's `mise` environment enables OTLP
exports to port 4318, so the collector must be running:

```sh
docker compose up -d questdb greptimedb tempo loki otel_collector grafana
```

Start the independent simulator (leave it running):

```sh
mise run earendil-simulator
```

Apply migrations and run the seed:

```sh
cd apps/cadence_web
mix ecto.migrate -r Cadence.Repo
mix cadence.questdb.migrate
mix run --no-start ../../dev/reflect_orbital_demo.exs
```

Start the named Cadence server with the local provider credential (leave it running):

```sh
POOL_SIZE=30 DB_QUEUE_TARGET_MS=1000 mise run cadence
```

The repository's `mise` environment also defines this public demo credential, so
`mise run cadence` inherits it. A server started before adding that environment
variable needs to be restarted with it. Do not start a second server on port 4001.

The larger development database pool leaves capacity for dashboard reads alongside
ten concurrent telemetry decoders and their history writers. The queue target allows
short local CPU/I/O bursts without dropping database requests. These environment
overrides apply to this server process; the development defaults remain 10 connections
and a 50 ms queue target. Finish builds and test suites before starting the live feeds.

The simulator binds **127.0.0.1:4101** and uses separate public local admin and
provider tokens. It stores its scenario, run, delivery profiles, and reservations
under `var/reflect_orbital/provider.dets`. These credentials and endpoints are only
for local development.

The seed is rerunnable: it uses stable identities, reuses the simulator run and
delivery profiles, and reconciles this fixture’s 500 spacecraft to the complete demo database.
Re-running it intentionally restores the fixture’s catalog, telemetry and commanding inputs.
It does not delete or reset other organizations. It grants the chosen existing
user organization-admin membership in Reflect Orbital. A stopped simulator run
is reported as an error rather than silently replaced. Stop the processes with
Ctrl-C when finished; the persisted demo remains available.

## What is configured

| Area | Demo configuration |
| --- | --- |
| Fleet | EARENDIL-001 through EARENDIL-500, unique CCSDS TM SCIDs 1–500 |
| Orbit metadata | 20 planes × 25 spacecraft; 625 km, 97.9° inclination, phased RAAN/anomaly |
| Bus | Shared version-pinned Earendil Block 1 profile; TM downlink, TC uplink, 1,115-byte frames, VC 0 |
| Payload metadata | Solar reflector; 475 deployed, 25 stowed for commissioning; illumination disabled |
| Catalog | Unmodified `legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml`: 10 telemetry packets and 27 commands |
| Ground network | 10 synthetic sites with 38 modeled antennas, synchronized through the provider HTTP API |
| Delivery | 10 version-pinned TCP ingress profiles/transports on loopback ports 42100–42109 |
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

1. Sign in at [Cadence](http://localhost:4001). From platform administration,
   open **Organizations → Reflect Orbital → Open Organization**.
2. Open [Earendil's spacecraft directory](http://localhost:4001/missions/mission-earendil-demo/spacecraft).
   Show 500 assets, the shared profile, unique identities, and pagination/search.
3. Open EARENDIL-001 and its configuration. Show the versioned catalog, APID
   selection, frame interpretation, and primary/backup delivery routes.
4. Open [Ground Stations](http://localhost:4001/missions/mission-earendil-demo/comms/ground-stations)
   and [Providers](http://localhost:4001/missions/mission-earendil-demo/comms/providers).
   Show synchronized fleet/site inventory and the organization account's mission grant.
5. Open [Contacts](http://localhost:4001/missions/mission-earendil-demo/ops/contacts)
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

Activate the fleet in the existing named development server (`mise run cadence`),
from the repository root:

```sh
elixir --sname earendil_setup --cookie cadence dev/reflect_orbital_activate.exs --single-operator
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

Open the [Commanding workspace](http://localhost:4001/missions/mission-earendil-demo/ops/commands/workspace).
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

The simulator sends CCSDS TM frames over the ten local TCP ingress paths. Cadence
performs normal frame processing, database-driven decoding, current-value updates,
monitoring, and history persistence. Values are synthetic generic spacecraft data,
not Reflect Orbital flight telemetry. The live task uses info-level server logging
to avoid flooding the development terminal with per-packet SQL; warnings and errors
remain enabled. Restart Cadence to restore its configured logging level.

Managed QuestDB writes use bounded HTTP ingestion batches on the existing port
9000. Reads continue through the SQL API. The migrated table's timestamp and
idempotency key retain retry deduplication. Counters outside QuestDB's signed LONG
range use the lossless JSON integer representation; these values remain readable
but do not participate in native numeric aggregates.

The task creates six native dashboards and a 30-second rotating wallboard playlist:

- [Fleet Watch](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-fleet)
- [Spacecraft Overview](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-overview)
- [Electrical Power](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-power)
- [Thermal Control](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-thermal)
- [Attitude & Pointing](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-attitude)
- [Communications & Payload](http://localhost:4001/missions/mission-earendil-demo/ops/dashboards/dashboard-earendil-comms-payload)

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
They occupy ports 42100–42109 while active, so do not book overlapping provider
contacts onto the same gateways during the rehearsal. The provider simulator's
ordinary eight-minute visibility windows remain available for a separate scheduling
walkthrough.

The live process exits when its contacts end. Stop it earlier with Ctrl-C; saved
dashboards and recorded history remain. Rerunning reuses unexpired rehearsal
contacts, or creates new ones after expiry. Set `EARENDIL_DEMO_CONTACT_SECONDS`
before starting to choose a new contact duration between 60 and 28,800 seconds
(default 7,200). An existing contact retains its original end time.

## Connection-refused warnings

Cadence and the simulator are separate processes. Starting `mise run cadence`
does not start the simulator. If the simulator exits, provider polling retries
`http://127.0.0.1:4101/provider/v1/capabilities` and Req reports
`connection refused`. Restart `mise run earendil-simulator` in its own terminal;
the persisted scenario and run are reused. Its health endpoint is
`http://127.0.0.1:4101/health`.

The other local dependencies are QuestDB on port 9000 and the OTLP collector on
port 4318. Use `docker compose ps` to check them and rerun the startup command
above if they are stopped. Missing QuestDB prevents telemetry history access;
a missing collector prevents observability exports. Restart these services after
a reboot or after stopping the Docker engine. Do not disable provider retries or
logging to conceal an unavailable service.

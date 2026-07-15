# Simulator Provider Integration Flow

The ground-network simulator is an external provider peer. It does not bootstrap
or administer Cadence. The supported development flow deliberately exercises the
same integration boundary as a commercial provider.

> This walkthrough describes the implemented Simulator Provider Contract v1 and
> normalized Cadence Provider Client. Mission Provider and provider-managed
> Transport persistence remain the next checkpoints in the
> [Stage 2 implementation plan](superpowers/plans/2026-07-13-contact-scheduling-stage-2-provider-delivery-contract.md).

## 1. Start the simulator

```bash
export CADENCE_SIMULATOR_HTTP_ENABLED=true
export CADENCE_SIMULATOR_PORT=4101
export CADENCE_SIMULATOR_ADMIN_API_TOKEN=local-simulator-admin-token
export CADENCE_SIMULATOR_PROVIDER_API_TOKEN=local-simulator-provider-token
export CADENCE_SIMULATOR_STORE_PATH="$PWD/var/cadence_simulator_provider.dets"
export CADENCE_SIMULATOR_DEFINITIONS_PATH="$PWD/legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml"

cd apps/cadence_simulator
mix run --no-halt
```

Create a scenario and start a run through `/admin/v1/scenarios` and
`/admin/v1/scenarios/:id/runs` with the administrator credential. Scenario/run
administration is simulator surface area, not Cadence surface area.

## 2. Start Cadence

Start Cadence independently on its normal web/API port. No simulator environment
variables are required by Cadence.

## 3. Configure the mission provider

Provision the Cadence TCP destination once through
`POST /provider/v1/delivery-profiles`, using the provider credential and the
run's `provider_environment_ref`. Save the returned Delivery Profile reference.

There is not yet a supported UI path for this new setup. The automated boundary
test persists the compatibility Provider Profile directly. Stage 2 Task 6
replaces the old provider form with the normal Mission Provider setup journey.
For checkpoint development, the persisted bridge contains:

Configure:

- TCP mode `listen`, direction `downlink`, and the port on which Cadence accepts
  telemetry;
- fixed-size framing when the simulator sends TM frames;
- External Scheduling `Enabled`;
- Provider Integration `Cadence Ground Network Simulator`;
- the simulator API URL and provider credential;
- the active provider environment reference;
- Service Profile `service-realtime-ttc-downlink`;
- the provisioned Delivery Profile reference.

The nested scheduling configuration selects the provider control-plane adapter.
The existing TCP configuration remains the temporary runtime bridge; Contact
requests themselves contain no host, port, framing, or `run_id` fields.

## 4. Configure spacecraft mappings and routes

Create Cadence spacecraft/source endpoints whose provider references match the
simulator spacecraft inventory. Create an active downlink link assignment that
binds the spacecraft and source endpoint to a selected path template and the
exact provider-profile version.

Cadence owns its spacecraft identity and byte-interpretation catalog. The
simulator owns its provider spacecraft inventory and telemetry generator
definitions.

## 5. Schedule and execute contacts

In the authenticated mission UI, open **Ops → Contacts**. Select a ready
spacecraft route, choose a bounded UTC search window, search the provider, and
reserve one opportunity.

Cadence then:

1. resolves the live mission route and searches through the configured provider
   client;
2. persists a mission-owned `ProviderReservation` attempt and idempotency key
   before mutating the provider;
3. reserves the selected opportunity without holding a database transaction
   across HTTP;
4. durably polls uncertain or nonterminal reservations until the provider state
   converges;
5. materializes exactly one canonical `ScheduledContact` when provider capacity
   is confirmed;
6. realizes the contact through the existing scheduler;
7. receives telemetry through the normal TCP provider and TM ingress runtime.

The page displays provider reservation state separately from Cadence contact
state. Cancellation also crosses the provider boundary and is reconciled from
the durable reservation record. No global simulator process, in-memory event
cursor, or simulator administration client runs inside Cadence.

## Manual two-BEAM smoke test

Keep the simulator BEAM from step 1 running. In another terminal, create a
small scenario and run:

```bash
export SIMULATOR_URL=http://127.0.0.1:4101
export SIMULATOR_ADMIN_TOKEN=local-simulator-admin-token
export SIMULATOR_PROVIDER_TOKEN=local-simulator-provider-token
export CADENCE_INGRESS_PORT=4100

SCENARIO_ID=$(curl --silent --fail \
  --request POST "$SIMULATOR_URL/admin/v1/scenarios" \
  --header "Authorization: Bearer $SIMULATOR_ADMIN_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "name": "Cadence manual scheduling smoke",
    "spacecraft_count": 3,
    "spacecraft_prefix": "SC",
    "pass_model": {
      "cadence_seconds": 60,
      "duration_seconds": 30,
      "jitter_seconds": 0
    },
    "telemetry_profile": {
      "rate_hz": 5.0,
      "noise_amplitude": 0.1
    }
  }' | jq --raw-output '.data.id')

RUN_ID=$(curl --silent --fail \
  --request POST "$SIMULATOR_URL/admin/v1/scenarios/$SCENARIO_ID/runs" \
  --header "Authorization: Bearer $SIMULATOR_ADMIN_TOKEN" \
  --header "Content-Type: application/json" \
  --data '{"seed": 2026, "speed": 1.0}' | jq --raw-output '.data.id')

echo "$RUN_ID"

DELIVERY_PROFILE_ID=$(curl --silent --fail \
  --request POST "$SIMULATOR_URL/provider/v1/delivery-profiles" \
  --header "Authorization: Bearer $SIMULATOR_PROVIDER_TOKEN" \
  --header "X-Simulator-Environment-Ref: $RUN_ID" \
  --header "Content-Type: application/json" \
  --data "{
    \"display_name\": \"Cadence primary telemetry ingress\",
    \"client_reference\": \"mission-primary-downlink\",
    \"direction\": \"downlink\",
    \"delivery_kind\": \"realtime_stream\",
    \"target\": {
      \"protocol\": \"tcp\",
      \"mode\": \"provider_connects\",
      \"host\": \"127.0.0.1\",
      \"port\": $CADENCE_INGRESS_PORT
    },
    \"framing\": {
      \"family\": \"ccsds_tm\",
      \"mode\": \"fixed_size\",
      \"frame_bytes\": 1115
    }
  }" | jq --raw-output '.data.id')

echo "$DELIVERY_PROFILE_ID"
```

Start Cadence in a second BEAM. Configure the compatibility mission provider with
the environment, Service Profile, and Delivery Profile references, map one source
endpoint to `SC-001`, and create the active downlink link assignment. In
**Ops → Contacts**, search a future window, reserve an opportunity, and observe
Contact, pass, and delivery state independently. The Scheduled Contact should
appear only after confirmation, and telemetry should arrive through the
mission's ordinary TCP/TM ingress path while the contact is active.

See [Ground Network Simulator](ground-network-simulator.md) for API and scenario
details.

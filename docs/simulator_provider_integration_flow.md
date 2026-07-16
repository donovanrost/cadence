# Simulator Provider Integration Flow

The ground-network simulator is an external provider peer. It does not bootstrap
or administer Cadence. The supported development flow deliberately exercises the
same integration boundary as a commercial provider.

> This walkthrough describes the implemented Simulator Provider Contract v1 and
> normalized Cadence Provider Client, persisted Mission Provider setup, and
> provider-managed Transport persistence. Scheduling now binds exact Provider,
> Transport, Service Profile, and Delivery Profile versions. The separate-app
> proof validates provider inventory over HTTP, streams normal CCSDS TM over TCP,
> and recovers a lost post-commit response by client reference as described in the
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

Start Cadence independently on its normal web/API port. Configure only the
provider credential backend that resolves the reference entered below; Cadence
does not consume the simulator's scenario or administration configuration.

## 3. Configure the mission provider

Open **Comms → Providers → New Provider**. Select `Ground Network Simulator`,
then enter the simulator provider API URL, an opaque credential reference, and
the run's `provider_environment_ref`. Use **Validate** to check access and
**Sync Inventory** to load the simulator's spacecraft, station, Service Profile,
and Delivery Profile summaries.

Provision the Cadence TCP destination once through
`POST /provider/v1/delivery-profiles`, using the provider credential and the
run's `provider_environment_ref`, when a compatible Delivery Profile does not
already exist. Sync again after provisioning.

The Provider UI deliberately contains no TCP mode, host, port, framing,
reconnect, TLS, or raw-token fields. Those concerns belong to the Delivery
Profile and Transport.

## 4. Create the provider-managed Transport

Open **Comms → Transports → New Transport** and choose **Ground Station
Provider** as the origin. Select the validated Mission Provider, a compatible
active Service Profile, and a ready Delivery Profile. Cadence persists the exact
Provider and profile versions, derives the actual TCP configuration, and shows
host, port, framing, and reliability as read-only fields. Raw profile evidence
is available only under administrator diagnostics.

Direct TCP remains available from the same form. Choosing **Direct** keeps the
TCP endpoint, framing, reconnect, and TLS controls user-configurable.

## 5. Configure spacecraft mappings and routes

Create Cadence spacecraft/source endpoints whose provider references match the
simulator spacecraft inventory. Create an enabled inbound Routing Rule that
selects the exact provider-managed Transport version. Cadence materializes the
runtime path and internal Provider Profile needed by the current execution
engine; neither is the provider control-plane identity.

Cadence owns its spacecraft identity and byte-interpretation catalog. The
simulator owns its provider spacecraft inventory and telemetry generator
definitions.

## 6. Schedule and execute contacts

In the authenticated mission UI, open **Ops → Contacts**. Select a ready
spacecraft route, choose a bounded UTC search window, search the provider, and
reserve one opportunity.

Cadence then:

1. resolves the spacecraft mapping, Routing Rule, exact provider-managed
   Transport, Mission Provider, Service Profile, and Delivery Profile;
2. persists those exact bindings, a mission-owned `ProviderReservation`
   attempt, and its idempotency key before mutating the provider;
3. reserves the selected opportunity without holding a database transaction
   across HTTP;
4. durably polls uncertain or nonterminal reservations until the provider state
   converges;
5. validates the returned delivery descriptor against approved Transport setup
   and materializes exactly one canonical `ScheduledContact` when provider
   capacity is confirmed;
6. realizes the contact through the existing scheduler;
7. receives telemetry through the normal TCP provider and TM ingress runtime.

The page displays Provider, Service, Delivery, Transport, Contact status, pass
phase, and delivery status. A conflicting descriptor remains visible as a
durable provider/configuration failure and is never connected. Cancellation
also crosses the provider boundary and is reconciled from the durable
reservation record. No global simulator process, in-memory event cursor, or
simulator administration client runs inside Cadence.

## Manual two-BEAM smoke test

From the repository root, start the simulator in terminal A. The provider HTTP
surface is disabled by default, so set the complete runtime configuration before
starting the BEAM:

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

Keep terminal A running. In terminal B, create a small scenario, immutable run,
and provider-owned Delivery Profile. The administrator token is used only for
scenario/run operations. The provider token and environment header are used
only for the customer-facing provider API:

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

Start Cadence as the second BEAM from the repository root in terminal C. The
credential reference configured in Cadence below resolves the provider token
from this process environment; the token is never persisted in the Mission
Provider record:

```bash
export SIMULATOR_PROVIDER_TOKEN=local-simulator-provider-token
mix phx.server
```

In the authenticated mission UI:

1. Open **Comms → Providers → New Provider** and select **Ground Network
   Simulator**. Set the base URL to `http://127.0.0.1:4101`, the credential
   reference to `env://SIMULATOR_PROVIDER_TOKEN`, and the provider environment
   to the printed `$RUN_ID`.
2. On the Provider detail page, select **Validate**, then **Sync Inventory**.
   The synchronized inventory must include the Delivery Profile printed above.
3. Open **Comms → Transports → New Transport**, choose **Ground Station
   Provider**, and select the exact Provider, active Service Profile, and ready
   Delivery Profile. Verify that the derived TCP host, port, and CCSDS framing
   are read-only.
4. Create or select the Cadence spacecraft, map its source endpoint to provider
   spacecraft `SC-001`, and create an enabled inbound Routing Rule selecting the
   new Transport.
5. Open **Ops → Contacts**, choose the ready route, search a future UTC window,
   and reserve an opportunity.

The reservation request contains opportunity, spacecraft, Service Profile,
Delivery Profile, client-reference, and tag fields only. The Scheduled Contact
appears after provider confirmation and descriptor validation. Contact status,
pass phase, and delivery status advance independently, while telemetry arrives
through the ordinary TCP/TM ingress path. Exact references and the sanitized
immutable descriptor are available in administrator diagnostics; secrets are
not.

See [Ground Network Simulator](ground-network-simulator.md) for API and scenario
details.

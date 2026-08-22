# Simulator Provider Integration Flow

The ground-network simulator is an external provider peer. It does not bootstrap
or administer Cadence. The supported development flow deliberately exercises the
same integration boundary as a commercial provider.

> This walkthrough describes the implemented Stage 5 flow: organization-owned
> Provider Account and credentials, exact mission grant, mission delivery
> policy, provider-managed Transport, provider-owned orbit readiness, Contact
> Requirements, recurring templates, fleet policy/runs, versioned Plans, guarded
> automation, durable provider events and changes, and normal TCP/CCSDS
> delivery. The separate-app proof crosses those same HTTP and TCP boundaries
> and exercises scale, restart, fault, approval, repair, configuration-failure,
> and ambiguous-outcome recovery as described in the
> [Stage 5 implementation plan](superpowers/plans/2026-07-16-contact-scheduling-stage-5-fleet-planning-and-automation.md).

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
does not consume the simulator's scenario or administration configuration. For
the local environment backend, export the provider token into the Cadence
process. Production Provider Accounts use the configured external secret
manager instead.

## 3. Register and grant the Provider Account

As an organization administrator, open **Provider Accounts → Register Account**.
Select `Ground Network Simulator` and enter:

- base URL `http://127.0.0.1:4101`;
- region `local` and the run's `provider_environment_ref` as the environment;
- event ingestion mode `Polling`;
- **Local environment** secret backend with
  `SIMULATOR_PROVIDER_TOKEN` as its backend key;
- the organization-wide service, direction, station, delivery-kind, and quota
  guardrails appropriate for the demo.

Cadence stores only a stable registry reference and the environment-variable
name. The local backend is enabled by `apps/cadence/config/dev.exs`; production
must use an approved external secret manager over HTTPS. On the new account detail, select
**Validate**, then grant the exact account version to the mission. Mission grant
restrictions can narrow but never widen the account guardrails.

## 4. Configure the Mission Provider

Open **Comms → Providers → New Provider**. Select the exact account grant. The
form shows account/environment/credential status as inherited, read-only setup;
it does not ask the mission to copy those fields. Configure permitted resources
and the mission delivery policy, then create and validate the Mission Provider.
Use **Sync Inventory** to load the simulator's spacecraft, station, Service
Profile, and Delivery Profile summaries.

Use **Require approval** for the safest default. Use **Bounded automatic** only
after defining explicit shift, retained-duration, and approved-station
tolerances. The mission policy cannot widen organization or grant guardrails.

Provision the Cadence TCP destination once through
`POST /provider/v1/delivery-profiles`, using the provider credential and the
run's `provider_environment_ref`, when a compatible Delivery Profile does not
already exist. Sync again after provisioning.

The Provider UI deliberately contains no TCP mode, host, port, framing,
reconnect, TLS, or raw-token fields. Those concerns belong to the Delivery
Profile and Transport.

## 5. Create the provider-managed Transport

Open **Comms → Transports → New Transport** and choose **Ground Station
Provider** as the origin. Select the validated Mission Provider, a compatible
active Service Profile, and a ready Delivery Profile. Cadence persists the exact
Provider and profile versions, derives the actual TCP configuration, and shows
host, port, framing, and reliability as read-only fields. Raw profile evidence
is available only under administrator diagnostics.

Direct TCP remains available from the same form. Choosing **Direct** keeps the
TCP endpoint, framing, reconnect, and TLS controls user-configurable.

## 6. Configure spacecraft mappings and routes

Create Cadence spacecraft/source endpoints whose provider references match the
simulator spacecraft inventory. Create an enabled inbound Routing Rule that
selects the exact provider-managed Transport version. Cadence materializes the
runtime path and internal Provider Profile needed by the current execution
engine; neither is the provider control-plane identity.

Cadence owns its spacecraft identity and byte-interpretation catalog. The
simulator owns its provider spacecraft inventory, synthetic ephemeris/readiness,
visibility generation, and telemetry generator definitions. Cadence records
the provider's orbit-readiness evidence but does not call the simulator admin
API or propagate an orbit.

## 7. Plan, approve, execute, and review contacts

In the authenticated mission UI, open **Ops → Requirements** and select **Plan a
contact**. Describe the spacecraft, intent, bounded UTC horizon, and success
measure. Search the exact current Requirement version, inspect provider-level
results, select one or more eligible windows, and create a draft Contact Plan.
Submit the exact Plan version for approval. An organization administrator
reviews its immutable hash, policy, route bindings, expiry, warnings, and
unsatisfied outcomes before approving. Execute only the approved version.

Cadence then:

1. versions mission intent without selecting provider capacity;
2. resolves the spacecraft mapping, Routing Rule, exact provider-managed
   Transport, Provider Account, mission grant, Mission Provider, delivery
   policy, Service Profile, and Delivery Profile;
3. asks every eligible provider route for authoritative windows and persists
   successful empty results, provider failures, and orbit-not-ready evidence as
   distinct outcomes;
4. snapshots and evaluates opportunities, then freezes one exact Plan version;
5. creates one durable execution item per approved selection and persists those
   exact bindings, a mission-owned `ProviderReservation`
   attempt, and its idempotency key before mutating the provider;
6. reserves the selected opportunity without holding a database transaction
   across HTTP;
7. durably polls uncertain or nonterminal reservations until the provider state
   converges, then projects the linked execution item without repeating the
   provider mutation;
8. stores provider events before advancing the exact account cursor and uses
   them as advisory triggers for authoritative Contact describe;
9. validates the returned delivery descriptor against approved Transport setup
   and materializes exactly one canonical `ScheduledContact` when provider
   capacity is confirmed;
10. realizes the contact through the existing scheduler;
11. receives telemetry through the normal TCP provider and TM ingress runtime.

The page displays Provider, Service, Delivery, Transport, Contact status, pass
phase, and delivery status. A conflicting descriptor remains visible as a
durable provider/configuration failure and is never connected. Cancellation
also crosses the provider boundary and is reconciled from the durable
reservation record. No global simulator process, in-memory event cursor, or
simulator administration client runs inside Cadence.

**Ops → Contacts** still supports direct ad hoc search and reservation. That
path deliberately leaves Requirement, Plan, and opportunity-snapshot references
null; Cadence does not invent hidden planning records.

For mission-scale work, open **Ops → Planning**. An organization administrator
approves the exact Fleet Planning Policy and may activate recurring Requirement
Templates. A mission member starts a bounded horizon run. Cadence materializes
occurrences idempotently, composes ordinary Stage 4 provider searches with
policy-bounded concurrency, records one deterministic decision per snapshot,
and creates an ordinary candidate Contact Plan.

Automation is optional. An administrator may issue a short-lived, exact-policy
Automation Grant to a named mission service identity. The service may perform
only the contiguous plan/submit/approve/execute actions allowed by that grant.
Partial execution creates a repair run that locks successful and uncertain
provider commitments and searches only unmet work.

Select a Contact row to open its detail page. The page separates requested,
provider-confirmed, Cadence-accepted, and actual truth and shows Contact, pass,
delivery, and Cadence lifecycle independently. A future material proposal needs
a current organization-admin approval or rejection with a reason. A provider
fact that is already effective needs acknowledgment and contingency work rather
than a misleading reject action. Endpoint, framing, credential, spacecraft,
direction, or profile drift is never approvable; it blocks execution until an
administrator remediates versioned setup.

The Provider Account detail reports durable cursor health, inbox backlog,
quarantine count, last-event time, grants, credential state, and recent audit
activity. Restarts resume from the persisted cursor and expired leases recover
automatically. After correcting a poison payload or adapter/configuration defect,
an organization-authorized recovery can requeue the exact quarantined inbox row
through `Cadence.GroundNetworks.ProviderEventInbox.reprocess/3`. The retry and
its convergent domain decision are append-only audit evidence.

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
    "orbit_readiness": {
      "status": "current",
      "source_kind": "synthetic",
      "ephemeris_ref": "manual-smoke-oem-v1",
      "version": 1,
      "validity_seconds": 604800
    },
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

Start Cadence as the second BEAM from the web composition root in terminal C. The
credential reference configured in Cadence below resolves the provider token
from this process environment; the token is never persisted in the Provider
Account, Mission Provider, reservation, diagnostics, event, or audit record:

```bash
cd apps/cadence_web
export SIMULATOR_PROVIDER_TOKEN=local-simulator-provider-token
mix phx.server
```

In the authenticated mission UI:

1. As an organization administrator, open **Provider Accounts → Register
   Account** and select **Ground Network Simulator**. Set the base URL to
   `http://127.0.0.1:4101`, the environment to the printed `$RUN_ID`, event mode
   to **Polling**, and secret backend to **Local environment** with backend key
   `SIMULATOR_PROVIDER_TOKEN`. Validate the account.
2. On the Provider Account detail, grant the account to the mission.
3. Open **Comms → Providers → New Provider**, select the exact grant, configure
   the mission delivery policy, and create the Mission Provider. Select
   **Validate**, then **Sync Inventory**.
   The synchronized inventory must include the Delivery Profile printed above.
4. Open **Comms → Transports → New Transport**, choose **Ground Station
   Provider**, and select the exact Provider, active Service Profile, and ready
   Delivery Profile. Verify that the derived TCP host, port, and CCSDS framing
   are read-only.
5. Create or select the Cadence spacecraft, map its source endpoint to provider
   spacecraft `SC-001`, and create an enabled inbound Routing Rule selecting the
   new Transport.
6. Open **Ops → Requirements**, select **Plan a contact**, create a downlink
   Requirement for `SC-001`, and search its current version. Confirm the
   simulator route reports current synthetic orbit evidence rather than a
   Cadence-generated pass.
7. Select an eligible opportunity and create a draft Plan. Submit the exact
   version, approve it as an organization administrator with a reason, and
   execute it.
8. Open the linked Contact under **Ops → Contacts** to follow provider, pass,
   delivery, and Cadence state.

The reservation request contains opportunity, spacecraft, Service Profile,
Delivery Profile, client-reference, and tag fields only. The Scheduled Contact
appears after provider confirmation and descriptor validation. Contact status,
pass phase, and delivery status advance independently, while telemetry arrives
through the ordinary TCP/TM ingress path. Exact references and the sanitized
immutable descriptor are available in administrator diagnostics; secrets are
not.

To exercise failure handling without changing Cadence, use the simulator admin
API. `PATCH /admin/v1/runs/:id/fault-profile` can configure provider outage,
rejection/acquisition/early-termination rates, post-commit response loss,
network loss/latency/jitter, and bounded event omission, duplication, delay,
reordering, or identity collision. `POST
/admin/v1/runs/:id/contacts/:contact_id/changes` can initiate timing, antenna,
station, capacity, counteroffer, cancellation, or delivery-configuration drift.
Cadence never calls either endpoint.

See [Ground Network Simulator](ground-network-simulator.md) for API and scenario
details.

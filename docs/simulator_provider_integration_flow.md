# Simulator Provider Integration Flow

The ground-network simulator is an external provider peer. It does not bootstrap
or administer Cadence. The supported development flow deliberately exercises the
same integration boundary as a commercial provider.

## 1. Start the simulator

```bash
export CADENCE_SIMULATOR_HTTP_ENABLED=true
export CADENCE_SIMULATOR_PORT=4101
export CADENCE_SIMULATOR_API_TOKEN=local-simulator-token
export CADENCE_SIMULATOR_STORE_PATH="$PWD/var/cadence_simulator_provider.dets"
export CADENCE_SIMULATOR_DEFINITIONS_PATH="$PWD/legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml"

cd apps/cadence_simulator
mix run --no-halt
```

Create a scenario and start a run through the simulator's `/v1/scenarios` and
`/v1/scenarios/:id/runs` endpoints. Scenario/run administration is simulator
surface area, not Cadence surface area.

## 2. Start Cadence

Start Cadence independently on its normal web/API port. No simulator environment
variables are required by Cadence.

## 3. Configure the mission provider

In the authenticated mission UI, open **Comms → Providers → New Provider**.

Configure:

- TCP mode `listen`, direction `downlink`, and the port on which Cadence accepts
  telemetry;
- fixed-size framing when the simulator sends TM frames;
- External Scheduling `Enabled`;
- Provider Integration `Cadence Ground Network Simulator`;
- the simulator API URL and token;
- the host the simulator can use to reach Cadence's telemetry listener;
- the active provider run ID.

This creates one ordinary mission-owned `ProviderProfile`. The nested scheduling
configuration selects the provider control-plane adapter, while the existing TCP
configuration controls contact-time byte ingress.

## 4. Configure spacecraft mappings and paths

Create Cadence spacecraft/source endpoints whose provider references match the
simulator spacecraft inventory, then create the selected downlink path templates
using the provider profile.

Cadence owns its spacecraft identity and byte-interpretation catalog. The
simulator owns its provider spacecraft inventory and telemetry generator
definitions.

## 5. Schedule and execute contacts

Cadence uses `Cadence.Contacts.ProviderBooking` to:

1. discover opportunities through the configured provider client;
2. reserve the selected provider opportunity;
3. persist the canonical Cadence `ScheduledContact` with the external reservation
   reference;
4. realize the contact through the existing scheduler;
5. receive telemetry through the normal TCP provider and TM ingress runtime.

Provider terminal events are reconciled through the generic provider-contact
reconciler supplied with the configured adapter's event function. No global
simulator process or simulator administration client runs inside Cadence.

See [Ground Network Simulator](ground-network-simulator.md) for API and scenario
details.

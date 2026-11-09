# #44 · Earendil uplink path (Compose → Approve → Uplink → Verify)

Owner: **domain**. Status: **draft for review** (2026-11-09). Reviewer: director.
`L` = `apps/cadence/lib/cadence`, `S` = `apps/cadence_simulator/lib/cadence_simulator`.

## Why this is more than a seed change

The demo can't uplink anywhere. The generic pieces already exist and are proven by
`cop1/loopback_integration_test.exs`:

- routing rules map outbound to an uplink path template;
- `ReleaseTargetSelection` picks the selected uplink path and its uplink-gateway transport
  binding;
- the `tcp_socket` adapter listens for the simulator's COP-1 `LoopbackPeer`;
- the peer decodes TC, runs FARM, replies with CLCWs, and applies the command's yaml `effects`
  to the spacecraft's telemetry.

What's missing is the provider-managed version of that path. Six of the gaps below are
plumbing. Two are decisions (**D1**, **D2**).

## Plan

1. **Simulator uplink delivery profiles** (`S/provider/delivery_profiles.ex`):
   - accept `direction: "uplink"`, TCP `provider_connects`, `ccsds_tc` framing with a TC frame
     size;
   - add a default uplink TT&C service profile;
   - advertise `"uplink"` in capabilities;
   - the Earendil fixture provisions one uplink delivery per site, each on its own port.
2. **Simulator COP-1 peer per contact** (`S/provider/orchestrator.ex`): when a contact
   activates, if the run has an uplink delivery at the contact's station, start
   `start_cop1_loopback_peer(host, port, tc_frame_size, command_target: <the contact's TM
   stream>)`. Track and stop it with the stream, under its own key.
3. **Cadence provider-managed outbound transport** (`L/comms/transport_store.ex`,
   `transport_kinds/tcp_socket.ex`):
   - an uplink delivery profile materializes as `listen`, `direction_capability: :outbound`,
     `ingress_protocol_family: "cop1_clcw"`, 4-byte CLCW messages, with `uplink_resource_id`
     set to the transport id;
   - `normalize_config` keeps `ingress_transport_binding_id`.
4. **Uplink gateway transport profile** (`L/comms/routing_rule_store.ex`): materializing an
   outbound rule also persists an `uplink_gateway` transport profile and references it from
   the uplink path template. The profile holds:
   - `cop1` FOP and the simulator's frame size;
   - the craft's scid;
   - `provider_binding_id` set to the provider profile id.

   The provider binding's `ingress_transport_binding_id` points back at the gateway, which
   lets CLCWs reach FOP.
5. **Seed** (`dev/reflect_orbital/seed.exs`): one provider-managed uplink transport per site,
   and one primary outbound route per craft at its primary site. That's all
   `UplinkResolution` (#41) needs.
6. **Verifiers** for a handful of demo commands (`SET_MODE` checks `HK.sc_mode`, plus
   `transport:completed`), in a demo copy of the yaml so the legacy reference stays untouched.
   Without verifiers, a command reads `not_required`, never `satisfied`.

## D1 · Booking carries the uplink path (needs approval)

Today a booked contact carries only the downlink path, and its intents are hard-coded to
`[:telemetry_downlink]` (`provider_reservations.ex:970`). So commanding has no uplink path to
release on.

**Proposal:** when a pass is booked at a station where the craft's primary outbound route
lands, the scheduled contact also gets that route's uplink path template plus intent
`:command_window`. Validation then requires a selected uplink path. Passes at other stations
stay downlink-only. This changes what a booked pass is for every mission with outbound routes,
not just the demo.

## D2 · Session qualification in dev (needs your decision)

Every TCP uplink session starts `blocked: fencing_unproven`. Only a qualification policy can
make it `ready`, and the default qualifies nothing (`L/runtime/session_qualification.ex`). Its
contract says a policy "must not accept a configuration flag as proof of authority". The
loopback test passes only by installing a test policy.

Options:

- **(a)** A simulator qualification policy that verifies real evidence from the simulator:
  - the peer sends a signed hello over the session (a run id plus an HMAC with a per-run
    secret that Cadence holds from provider sync);
  - the policy checks it against the session basis.

  This honours the contract. It's about a day of work.
- **(b)** A dev-only policy that qualifies sessions whose provider is the simulator account.
  This is quick, but it is exactly "config as proof". It must be refused outside `MIX_ENV=dev`.

**Recommendation: (a).** (b) would put a fencing bypass in the tree, next to code that has to
fail closed.

## Risks

- **Port collisions.** One TCP listener per contact path per site port means two concurrent
  contacts at one site get `eaddrinuse`. Downlink already has this risk. The per-site
  `uplink_resource_id` would also give `uplink_resource_conflict` for concurrent contacts.
  I'll document both and pace the demo; I won't fix them in #44.
- **Sync ordering.** The new delivery profiles reach Cadence only through provider sync, so the
  seed must sync before it creates the transports.

## Order

Items 1–5 and 6 can be built now (no behaviour change for other missions). D1 and D2 come
after you approve them. Done means a `SET_MODE` command composed and approved in the console
uplinks on a real Earendil pass on :4011 and reads `satisfied`. Then I tell qa and fe-ops.

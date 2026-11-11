# #44 · Earendil uplink path (Compose → Approve → Uplink → Verify)

Owner: **domain**. Status: **approved** (2026-11-09): D1 as DECISIONS #46 with conditions, D2 option
(a). Reviewer: director.
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

## D1 · Booking carries the uplink path (approved, DECISIONS #46)

**Decision:**
- Attach the uplink path and `:command_window` **only when the provider reservation includes
  uplink service, both requested and confirmed**.
- Otherwise the pass stays downlink-only and shows the visible reason `uplink not booked`.
- New bookings only; existing contacts keep their snapshot.
- A selected uplink path is required only on contacts that carry `:command_window`.

The provider contract therefore grows an optional uplink leg on the contact request,
`uplink: {service_profile_ref, delivery_profile_ref}`, which the provider confirms or rejects
on the contact. The simulator implements it with a default uplink TT&C service profile.

Today a booked contact carries only the downlink path, and its intents are hard-coded to
`[:telemetry_downlink]` (`provider_reservations.ex:970`). So commanding has no uplink path to
release on.

**Proposal:** when a pass is booked at a station where the craft's primary outbound route
lands, the scheduled contact also gets that route's uplink path template plus intent
`:command_window`. Validation then requires a selected uplink path. Passes at other stations
stay downlink-only. This changes what a booked pass is for every mission with outbound routes,
not just the demo.

## D2 · Session qualification in dev (decided: option a, no bypass in the tree)

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

### D2 as built: provider attestation (refines option a)

Option (a) was a signed hello on the session. It is built as a **challenge–response over the
provider API** instead, for two reasons:

- an in-band hello would change the TCP stream's 4-byte CLCW framing, which lives in the data
  plane;
- attesting the peer address binds the evidence to the exact TCP connection.

Here's the flow:

1. **Basis.** When the provider connects, the TCP adapter registers the session. Its basis now
   includes the connection's **peer address**. The session's `basis_sha256` changes with every
   incarnation, so it serves as a fresh challenge.
2. **Driver.** `Cadence.Control.UplinkQualification`, a composition-level process, finds blocked
   provider-managed uplink sessions. For each one it calls the provider:

   `POST /provider/v1/contacts/:id/uplink-attestation {challenge, purpose: fencing | protocol}`

   The provider answers `{contact_ref, challenge, purpose, peer, farm, valid_until, signature}`.
   The signature is HMAC-SHA256 under the provider API credential Cadence already holds, over a
   canonical string. The simulator signs only for an active contact whose uplink leg is
   included and whose COP-1 peer is connected. `peer` is that peer's own socket address;
   `farm` is its FARM state, which `protocol` attestations report.
3. **Recovery.** The driver runs `begin_recovery` (fencing) and then `complete_recovery`
   (protocol), and re-qualifies before the 5-minute evidence window ends.
4. **Policy.** `Cadence.GroundNetworks.ProviderSessionQualification` is the configured
   `SessionQualification`. It accepts only when all of these hold:
   - the signature verifies under the credential of the provider that booked the session's
     contact;
   - `challenge` equals the current `basis_sha256`;
   - `contact_ref` is the provider contact of the session's realized contact;
   - `peer` equals the peer in the basis;
   - for protocol recovery, the FARM is unlocked.

   Configuration alone can't qualify a session, and with no provider evidence the session
   stays blocked. The policy is not dev-only, because it checks real evidence.

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

## Back-to-back releases and FOP faults (#33)

COP-1's FOP keeps one release in flight: a release is accepted, its frames go out, and the
release completes when a CLCW acknowledges them. The release path now separates **busy** from
**broken**:

| FOP state | Admission | Release | What the operator sees |
| --- | --- | --- | --- |
| `active`, nothing in flight | admits | accepted; `transport:started` | released |
| `active` / `retransmit_without_wait`, release in flight | refuses `{:uplink_busy, :cop1_release_in_flight}`, no attempt claimed | — | still queued; the lane retries in 0.5 s and is kicked when the release completes or fails |
| `retransmit_with_wait` (CLCW wait) | refuses `{:uplink_busy, :cop1_wait}` | — | still queued |
| `initializing_without_bc` / `initializing_with_bc` | refuses `{:uplink_busy, :cop1_initializing}` | — | still queued |
| `initial` (alerted: lockout, NN(R) error, transmission limit, …; or never initialized) | admits | refused by the FOP before anything is sent (`cop1_not_initialized`): the attempt is `release_failed` and the request canceled | failed; stop-on-failure cancels the group's later members (`earlier_command_failed`) |
| disabled | admits | refused (`cop1_disabled`): `release_failed` | failed |

An alert while a release is in flight is that release's **transport failure**: the gateway
reports the FOP's `{:failure, release, reason}` as signal phase `failure` (`transport:failed`,
`cop1_alert`), and the release's pending transport verifiers fail at once
(`failure_reason: "transport_failed"`) instead of timing out. Before #33 that signal crashed
the gateway.

So a group `[A, B, C]` on one target:
- **No fault:** A releases; B and C wait (busy) and release in order as each completes.
- **Lockout while A is in flight:** A's verifier fails (`verify_failed`). B and C fail closed
  (`earlier_command_failed`) on the lane's next attempt, without ever reaching the FOP.
- **FOP already alerted before A:** A is `release_failed`; B and C fail closed.

A Halt'd or refused head no longer waits for the 60 s safety poll: the lane goes on to the
next entry at once. Recovering an alerted FOP (re-initializing the AD service) is an operator
action and isn't automated here.

## One uplink session per pass (#34, DECISIONS #59)

A provider-managed pass is its own external uplink session, so its uplink resource is the
booking's: `ContactRuntimeConfig` scopes each provider binding's `uplink_resource_id` to the
pass (`<listener resource>:pass:<provider contact ref>`). Consequences:

- **Across passes:** a new pass has no earlier sends on its resource, so it doesn't need a
  protocol restore. Before #59 every pass after a route's first command was refused with
  `protocol_state_restore_required` and could never command.
- **Within a pass:** a restart still finds that pass's sends and fails closed
  (`protocol_state_restore_required`). Readiness shows `blocked` with that reason. Recover
  uplink re-runs qualification only; it can't restore protocol state (see the follow-up below).
- **Listener exclusivity:** unchanged. A pass's TCP listener binds its port exclusively, so a
  second concurrent session on the same listener can't start (`tcp_provider_listen_failed`).

**FOP initialization.** A pass's FOP never assumes V(S) = 0: a real FARM keeps V(R) across
passes. Provider-managed gateways are configured `cop1_initialization: first_clcw`. The FOP
waits, and admission answers busy (`cop1_awaiting_clcw`), until the spacecraft's first CLCW
arrives. Then V(S) and the next frame number take its N(R), and AD service is initiated with
CLCW check against that report. A first report showing lockout leaves the FOP alerted, so
releases fail and stop-on-failure applies. The simulator peer reports its CLCW on connect,
as a spacecraft does continuously in the TM OCF. The `configured` mode (initiate from
`initial_frame_seq` at start) stays the default for hand-built and test transports.

### Follow-up for the runtime owner (main): restoring protocol state

Not built here; logged for main's runtime owner. After a restart within a pass, main's API can
install a checkpoint (`restore_protocol_checkpoint`) but nothing can complete recovery:
`complete_session_recovery` refuses while a restoration is installed, and nothing clears it.
That is main's planned "Recovery commit and readiness contract" in
`docs/multi-node-runtime-plan.md`:
1. apply the audited frame/attempt reconciliation;
2. commit a recovered checkpoint revision;
3. issue a readiness receipt bound to it.

Until that exists, a mid-pass restart leaves the rest of that pass unable to command; the next
pass is unaffected.

**Dev note (seed).** The Earendil seed creates uplink routes only when they're missing, so a
change to the uplink gateway configuration (like #59's `cop1_initialization`) doesn't reach
existing routes on a re-seed. Re-materialize their legs once on the node:
`for r <- RoutingRuleStore.list_routing_rules(org, mission), r.direction == :outbound, do:
RoutingRuleStore.update_routing_rule(org, mission, r.routing_rule_id, %{})`. Already-booked
passes pick the new profile up when their contact starts.

## A command releases only over its target spacecraft (SAFETY #38, DECISIONS #66)

The target is the spacecraft of the request's source endpoint. `ReleaseTargetGuard` checks the
contact, uplink path and gateway against it:

| Piece | Must | Refusal |
| --- | --- | --- |
| Realized contact | serve only the target's endpoints, and at least one | `release_contact_not_target_spacecraft` |
| Uplink path | name the target's endpoint, or (none named) come from a routing rule for the target | `release_path_not_target_spacecraft` |
| Gateway binding | carry a SCID (integer, or a string that is exactly one) | `uplink_gateway_scid_unknown` |
| Gateway binding | carry the target's SCID; the target has one | `release_gateway_not_target_spacecraft`, `release_target_scid_unknown` |

- **Lane dispatch** only considers the target's own contacts, and runs the full check on what
  it picks. A queued command with no own pass waits (`no_release_target`). It never borrows
  another spacecraft's pass.
- **At release**, the check runs again just before transmit. A refusal is `release_failed`
  (never uncertain) with nothing sent, and the group's stop-on-failure applies.
- **Verifiers**: a telemetry verifier only evaluates samples whose `spacecraft_id` is its
  command's target. Another spacecraft's sample, or one with no spacecraft, verifies nothing,
  so a missing confirmation times out rather than verifying falsely. Transport verifiers are
  keyed by the release attempt, which the guard already binds.

**Live check of verifier scope (SET_MODE "Mode applied", #65 option A).** In the simulator,
`HK.sc_mode` cycles every state with no command, 10 s each from BOOT at stream start (80 s),
so the target's own HK reads SCIENCE (raw 4) for 10 s of every 80 s. A 60 s verifier can be
satisfied by that cycle before the command takes. "Satisfied" alone doesn't prove it. The
evidence is: the satisfying sample is the target's, and it was generated after "Accepted on
board"; after it, `HK.sc_mode` holds the commanded value for the rest of the pass. The value
override lives in that contact's TM stream only, so it ends at LOS and the next pass cycles from
BOOT. There's nothing to restore.

**Root cause.** The selection code treated an uplink path with no `source_endpoint_ref` as
matching any request, and it walked every active contact in the mission. Route-materialized
uplink paths have no endpoint, and each route's gateway carries its own spacecraft's SCID, so
the other spacecraft accepted the frame. Main and develop have the same selection code and the
same route materialization.

## A lost CLCW can't strand a pass (#38, DECISIONS #59 follow-up)

**What happened.** On 2026-11-11, 010's NOOP never released during its own pass. A
provider-managed pass's FOP starts from the spacecraft's first CLCW (#59). The simulator peer
sent that CLCW once, on connect, and the report was lost. The FOP then waited all pass
(`uplink_busy: cop1_awaiting_clcw`), and readiness still read ready. api's 583aaafc made those
waits visible and readiness fail closed when the runtime can't answer.

**Decision.**

- **The spacecraft reports continuously.** A real spacecraft puts its CLCW in every downlink
  frame's OCF. The simulator's COP-1 peer now reports on connect and then every
  `clcw_report_interval_ms` (default 1 s) while connected, so a lost report costs one interval.
- **Readiness follows the CLCW stream.** The gateway stamps when it started waiting and when it
  last had a CLCW (`cop1_started_at`, `cop1_clcw_at`; wall-clock ms, checkpointed as dynamic
  state). A qualified session reads:

  | CLCW stream | Readiness |
  | --- | --- |
  | waiting for the first report, under 15 s | qualifying `cop1_awaiting_clcw` |
  | no first report within 15 s | **blocked** `cop1_no_clcw_report` (an `uplink_blocked` attention item when groups wait) |
  | last report under 15 s old | ready |
  | last report older than 15 s | qualifying `cop1_clcw_stale` |
  | runtime can't say | qualifying `uplink_state_unavailable` |

- Admission is unchanged: the gateway still refuses busy (`cop1_awaiting_clcw`) without claiming
  a release, and the FOP's own timers handle a stream that stops mid-release.

**TM ingest and commanding.** Profiles declare a 4-byte OCF (`ocf_length`), but Cadence only
records that it's present. Today CLCWs reach the FOP only over the uplink socket, so TM ingest
health doesn't gate commanding. Routing OCF CLCWs to the FOP (what a real ground segment does)
would make it gate commanding: a stalled downlink would read `cop1_clcw_stale`. Decided in
[DECISIONS #70](../DECISIONS.md) (not scheduled yet): when OCF CLCWs are routed to the FOP,
they're extracted at frame ingest, before the projector/persistence gate, so TSDB health never
gates commanding. Only the link itself (no frames arriving) does.

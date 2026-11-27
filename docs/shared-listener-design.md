# Inbound telemetry: tie a connection to an authenticated delivery before routing (#130)

Status: proposal for the CTO. It informs #129 (the server side of the listener choice) and
#202 (the console form, blocked).

## Problem

A provider delivers downlink by connecting to a host and port that Cadence listens on. Nothing
in that connection says who is connecting or which mission's pass it serves. Cadence decides
which spacecraft the bytes belong to from the port and from the SCID in the first TM frame.
SCIDs are 10 bits and assigned per mission, so they are not unique across missions or
organizations. A peer that can reach the port, or a provider configured with the wrong
destination, can have its telemetry stored as another spacecraft's.

## What develop does today

| Fact | Where |
| --- | --- |
| A listen host:port belongs to one mission, refused at save and at contact start, across all organizations ("the port is a resource of the node, not of a tenant"). | `comms/listen_claims.ex:2-19`, `guard/3` at :80, `check_paths/2` at :108 |
| Own listener: the first peer to connect takes the pass; a second peer is refused and logged (DECISIONS #67). A peer that qualification can't verify is dropped. | `provider_adapters/tcp_socket.ex:548-576`, :306-332 |
| Shared listener: one acceptor per (mission, provider profile). It routes a peer by the first frame's SCID among that mission's registered contacts, plus an expected peer address when the profile has one. "Identification is routing among our own registered contacts, not attestation." | `runtime/profile_acceptor.ex:2-25`, `match_scid/3` at :293-303, `peer_allowed?/2` at :313-316, name at :147 |
| Optional fallback: with exactly one registration and unreadable framing, that registration takes the peer. | `profile_acceptor.ex:305-311` |
| After routing, frames whose SCID isn't the contact's spacecraft are refused per frame and reported (`contact_scid_mismatch`). | `contacts/scid_mismatch.ex:45`, `contacts/scid_mismatch_attention.ex:2-6` |
| No TLS is implemented. `tls_enabled` is stored configuration only; the adapter and acceptor use plain `:gen_tcp`. | `comms/transport_kinds/tcp_socket.ex:190`; `profile_acceptor.ex:42` |
| The provider contract provisions a delivery destination once (`target.mode: provider_connects`, host, port) before any reservation. A contact's `delivery` is `{}`, so there is no per-contact identity on the wire. Credentials are opaque references. | `docs/superpowers/specs/2026-07-13-simulator-provider-contract-v1.md:433-486`, :560-584 |
| The simulator connects in plain TCP to that target. | `cadence_simulator/provider/delivery_profiles.ex:111`, :133 |

### `listener: "shared"` is not usable end to end

- **Runtime:** the runtime honours `listener: "shared"` in a provider profile's configuration
  (`tcp_socket.ex:84-103`, :746-750), but only the test fixtures set it
  (`test/support/shared_listener_fixtures.ex`).
- **Transport kind:** the TCP transport kind never carries the key. `normalize_config/1` builds a
  fresh map without it (`transport_kinds/tcp_socket.ex:175-208`), and `listener` isn't in its
  known keys (:27-51). A stored or staged `listener: "shared"` is silently dropped, and the
  materialized provider profile never has it (:315-338).
- **Console:** the console has the form rules (`frontend/apps/console/src/features/comms/listener.ts`,
  #407), but the server schema offers no `configuration.listener` field, so the field never shows.
- **The re-cut:** the server re-cut (2a242aad3 feat listener, ff275c848 diff labels, 54513ad61
  direction words, 8692e3c6e cleanup) exists only on a local `api/listener-recut` branch. It isn't
  on origin or develop. It adds `TCPSocket.DeliveryProfile`, `TCPSocket.Form`, the schema field
  and tests.

## Threat model

Cross-mission attribution on one listener is mostly prevented today: ListenClaims gives each
endpoint to one mission, and an acceptor routes only among its own mission's contacts. What
remains:

1. **A misdirected provider delivery.** One provider serves missions A and B, possibly in two
   organizations. A's delivery profile is set up, by mistake or by a provider fault, with B's
   host:port. A's frames reach B's listener. If one of B's contacts that is active then has the
   same SCID (likely, with 1,024 values), the frames are stored as B's spacecraft. Neither the
   SCID check nor ListenClaims can see this: the port is B's, and the SCID matches B's contact.
2. **An unauthenticated peer.** Anyone who can reach the port during a pass can connect, send
   frames with that pass's SCID, and be stored as the spacecraft. On an own listener, the first
   connection also takes the pass from the real provider (a denial of service); qualification
   can drop an unverified peer, but only after it has connected.
3. **Replay.** A captured stream replayed during a later pass of the same spacecraft is accepted.
   Routing only exists while a contact is registered, which limits the window but doesn't close
   it.
4. **The opt-in fallback.** A single registration takes an unidentifiable peer with no SCID
   check at all.

The effect in every case is wrong or forged telemetry recorded against a spacecraft, which
operators command from. That's a safety and integrity problem, not only a confidentiality one.

## Options

| Option | Security | Provider compatibility (assumptions marked) | Cost at 500 spacecraft | Effort |
| --- | --- | --- | --- | --- |
| (a) Own listener per booking, ports from a pool, the target sent per contact | Closes case 1 if every booking's port is unique and short-lived. Cases 2 and 3 stay open: still unauthenticated. | Needs a per-contact delivery target. Today's contract provisions targets before reservation (`delivery: {}`), so it is a contract change. *Assumption:* many real providers fix the destination per dataflow or delivery configuration, not per pass. | One port per concurrent pass; tens on average, low hundreds at peak. Firewall rules must open a range. | Medium: port pool, contract, simulator. |
| (b) Shared or own listener with mutual TLS: a client certificate per mission provider binding, checked before any frame is read | Closes 1 and 2: the connection is bound to an authenticated provider binding (mission and provider) before routing, and routing then considers only contacts booked through that binding. 3 narrows to a compromised provider. | *Assumption:* TLS to a customer endpoint is common for TCP stream delivery and client certificates are widely supported, but that varies by provider and must be confirmed per provider. The simulator can do it easily. | One port per mission and provider; certificates and a TLS handshake per connection. | Medium-large: TLS listener, certificate issue and rotation through the existing credential references, contract capability, simulator. |
| (b′) A per-contact token in a preamble before the first frame | Closes 1 to 3 for providers that send it. | Non-standard. *Assumption:* no real provider sends a Cadence-specific preamble; it's useful for the simulator and Cadence-aware gateways only. | Negligible. | Small. |
| (c) A source-address allowlist per provider binding (`expected_peer_address`, today only in provider profile configuration) | Weak alone: addresses are shared behind NAT or cloud egress and can be spoofed on some networks. It does narrow cases 1 and 2. | Works with any provider that publishes egress ranges (*assumption:* most do). | Negligible. | Small: the field exists in the acceptor. |
| (d) Combine (c) now with (b), plus binding-scoped routing | Defence in depth. The interim step doesn't depend on provider TLS. | As (b) and (c). | As (b). | Staged. |

**Binding-scoped routing** is a cheap step in every option. Each registration already carries its
provider binding. An acceptor or own listener should only route a connection to contacts booked
through the provider binding that connection is known to come from (by certificate, by token, or
by address under (c)), and never fall back to "any contact of the mission with this SCID".

## Recommendation

Adopt (d):

1. **Now, without depending on any provider.**
   - Every listen endpoint that receives provider-managed deliveries needs a source allowlist on
     its provider binding, put on the transport and materialized into the profile.
   - Shared-listener routing becomes binding-scoped.
   - The unidentified-peer fallback is removed, which is fine with no legacy to keep.
   - A peer outside the allowlist is refused before any frame is read, and counted as a refusal
     on the shared listener (U50).
2. **Then, mutual TLS as a contract capability**, `delivery_auth: "mtls"`.
   - Cadence issues a client identity per mission provider binding, held behind the existing
     credential references, and verifies it in the TLS handshake before routing.
   - The simulator implements it, and provider-managed listen endpoints require it outside dev.
   - The allowlist stays as a second check.
3. **The shared listener becomes a capacity choice, not a security one.** #129 and #202 land on
   top of step 1, and step 2 follows.
4. **Not recommended now:** per-booking ports (a) and the token preamble (b′). (a) changes the
   reservation contract for a gain mTLS gives more cleanly. (b′) only helps Cadence-aware senders.
   Revisit (a) if a provider can do neither TLS nor a stable egress range.

## Decisions for the CTO

1. Is "a connection is bound to an authenticated mission provider binding before any frame is
   routed" the requirement for listen-mode downlink, with mutual TLS as the target mechanism?
2. Until mutual TLS lands, may the shared listener ship (#129, #202) with a mandatory source
   allowlist and binding-scoped routing, or should it stay off until mutual TLS?
3. Remove the opt-in single-registration fallback (`fallback_single_registration`) now?
4. Should a provider-managed listen endpoint with neither an allowlist nor mutual TLS be refused
   at save outside dev, or only flagged?
5. Re-land the server re-cut (2a242aad3..8692e3c6e) as the basis for #129, or rebuild it on
   today's transport kind?

## Slices after approval

1. **Binding-scoped routing and the allowlist (server).**
   - Add `expected_peer_addresses` (a list) to the TCP transport kind and its materialized profile.
   - Registrations route by (provider binding, SCID). Remove the fallback. Refuse an unallowed peer
     before reading.
   - Tests: a cross-organization SCID collision (case 1) is refused, an unallowed peer is refused,
     and two bindings sharing a port never cross.
2. **Listener choice (#129 server, #202 console).** Carry `listener` through the transport kind,
   the schema field and the change-set labels, re-landed or rebuilt per question 5. The console
   form then uses the field.
3. **Mutual TLS.**
   - A TLS listener (`:ssl`) in the acceptor and in own listeners.
   - Client identities per mission provider binding, with rotation, held behind credential
     references.
   - The `delivery_auth` capability in the provider contract, the simulator presenting its
     certificate, and a save-time rule per question 4.
4. **Simulator and end to end.** The simulator delivers over mutual TLS. e2e covers a
   misconfigured delivery (A's stream sent to B's port) being refused and counted, never stored.

Data is disposable in dev, so none of this needs a compatibility path: existing profiles are
re-materialized from their transports.

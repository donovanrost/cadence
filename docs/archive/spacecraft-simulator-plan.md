---
title: Spacecraft Simulator Plan
tags: [architecture, implementation-plan, simulator, cop-1]
related:
  - "[[cop-1]]"
  - "[[target]]"
  - "[[interface]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Spacecraft Simulator Plan (COP-1 + CFDP)

## Goals and Constraints
- Provide a realistic spacecraft-side simulator for CCSDS COP-1 and CFDP.
- Support both in-process harness use and a standalone service.
- Start with TM framing (current stack) and leave room for AOS/USLP later.
- Keep protocol engines library-first so they can be reused by tests and services.
- Be multi-tenant and mission-scoped, with no shared state across missions.
- Prefer deterministic timing for tests using `Cadence.Time.Timer`.
- Reuse existing CCSDS SDLP codecs on both ground and spacecraft sides; add a
  dedicated TC codec where SDLP does not cover it.

## Current State
- `mix cadence.simulate` generates telemetry values with TM framing and optional OCF.
- TM framing is implemented; AOS/USLP are planned but not yet present.
- Uplink/downlink pipelines exist for SDLP framing/deframing.
- TCP interfaces support both server and client modes, but TCP server uplink currently
  broadcasts to all clients.
- COP-1 CLCW encode/decode and a FARM skeleton are implemented; FARM can ingest TC
  frames and emit CLCW for TM OCF.
- Minimal TC framing (encode/decode + segmentation) is available for uplink so COP-1
  can be exercised end-to-end with fixed-size frames.

## Protocol Scope
- COP-1: implement spacecraft-side FARM and CLCW generation first.
  - FOP (ground-side) is out of scope for the simulator but can be added later for
    loopback testing.
  - CLCW is emitted in TM OCF (4 bytes) so ground-side can validate FARM state.
- CFDP: implement Class 1 and Class 2 with timers and filestore abstraction.
- TC: add TC framing/deframing to support COP-1 state machines end-to-end.
- SDLP profiles: TM now, AOS/USLP later without refactoring core transport modules.

## Architecture Overview
```
                           +---------------------------+
Uplink bytes (TC) --------> | SpacecraftSim (per craft) | ----> Downlink bytes (TM)
                           +---------------------------+
                                    |
                                    v
                           +---------------------------+
                           | COP-1 FARM (state)        |
                           | CFDP Entity (state)       |
                           | Telemetry/Command Sim     |
                           +---------------------------+
```

Two layers:
- SpacecraftSim: one spacecraft instance (one connection, one COP-1 FARM, one CFDP entity).
- ConstellationSim: supervisor that owns many SpacecraftSim instances and shared
  orchestration (contacts, orbit dynamics, ground station emulation).

Transport adapters:
- TCP client mode (default) connects to Cadence `TcpServerInterface`.
- TCP server mode listens for Cadence `TcpClientInterface`.

## Proposed Module Layout
```
lib/cadence/ccsds/transport/
  cop1/
    farm.ex
    clcw.ex
    config.ex
  cfdp/
    entity.ex
    timers.ex
    filestore.ex
    pdus/...
lib/cadence/simulator/
  spacecraft_sim.ex
  constellation_sim.ex
  transport/
    tcp_client.ex
    tcp_server.ex
  dynamics/
    telemetry_provider.ex
    orbit_model.ex (future)
  faults/
    loss_model.ex
    latency_model.ex
lib/mix/tasks/
  cadence.spacecraft_sim.ex
```

## Data Flow (TM Only, Initial)
Uplink:
```
TCP bytes -> TC frame decode (TM/TC once added)
         -> COP-1 FARM ingest
         -> (optional) CFDP receive + command handler
```

Downlink:
```
Telemetry + CFDP PDUs + CLCW
  -> SDU encode (space packet or CFDP PDU)
  -> TM frame encode with OCF (CLCW)
  -> TCP bytes out
```

## Connection Modes
- `mode: :connect` (default): simulator connects to Cadence `TcpServerInterface`.
- `mode: :listen`: simulator accepts Cadence `TcpClientInterface`.
- Future: allow multiple spacecraft sharing one TCP server connection after routing
  by APID/SCID/VCID is implemented in `TcpServerInterface`.

## Multi-Spacecraft Strategy
Near-term:
- One spacecraft per TCP connection. This keeps COP-1 and CFDP state clean and
  avoids the current TCP server broadcast limitation.

Long-term:
- ConstellationSim can spin up N SpacecraftSim instances.
- Add uplink routing in `TcpServerInterface` (route by APID/SCID/VCID) so multiple
  spacecraft can share a single interface/port without receiving each other's TC.

## Static Uplink Routing
`TcpServerInterface` can optionally route uplink frames by SCID/VCID before any
downlink frames are received. Enable `routing: "scid_vcid"` and provide
`routing_static` entries that bind a client to a route.

Example (interface config):
```
routing: "scid_vcid"
routing_static:
  - client_index: 1
    scid: 10
    vcid: 0
  - remote_address: "127.0.0.1"
    remote_port: 42001
    scid: 20
    vcid: 1
```

Static routes are not overridden by learned downlink routes.

### Static vs Learned Routing
- Prefer static routes for deterministic uplink during initial contacts, TC-only
  tests, or when downlink is delayed/unavailable.
- Prefer learned routes when continuous downlink is available and you want the
  server to bind clients automatically from TM frames.
- Static routes take precedence over learned routes; if a client is statically
  mapped it will not be re-learned from downlink.

## Configuration Surface (Draft)
CLI entrypoint:
```
mix cadence.spacecraft_sim \
  --mission-id <uuid> \
  --target <id> \
  --mode connect \
  --output tcp:localhost:9999 \
  --frame tm --frame-size 1115 --scid 42 --vcid 0 \
  --cop1 true --cfdp class2 \
  --loss 0.0 --latency-ms 0
```

Config areas:
- Link: profile (tm/aos/uslp), frame size, scid, vcid, ocf enabled.
- Uplink link: uplink_profile (tc/tm/aos/uslp), uplink_frame_size (optional override).
- COP-1: window size, lockout/wait behavior, FARM timers.
- CFDP: class 1/2, timers, checksum, filestore path or in-memory.
- Dynamics: telemetry provider, scenario file, noise models.
- Faults: loss/latency/jitter/contact windows.

## Testing Strategy
- Unit tests:
  - COP-1 FARM state transitions, lockout/wait/retransmit behavior.
  - CLCW encode/decode correctness (bit fields and counters).
  - CFDP Class 1/2 transaction flows and timers.
- Integration tests:
  - Start `TcpServerInterface` + SpacecraftSim (connect mode).
  - Validate TM downlink with CLCW in OCF and CFDP PDUs.
  - Validate TC uplink handling once TC framing is in place.
- Harness tests:
  - In-process SpacecraftSim with `Cadence.Time.Timer` virtual time.

## Implementation Phases
1) Transport primitives (done)
   - COP-1 CLCW struct + encode/decode.
   - FARM state machine skeleton.
   - Minimal TC frame encode/decode + segmentation for uplink.
2) SpacecraftSim skeleton
   - TCP client mode to Cadence `TcpServerInterface`.
   - TM downlink with CLCW in OCF (static for now).
3) TC framing
   - Implement TC frame encode/decode and wire FARM ingest.
4) CFDP Class 1
   - Entity, PDUs, timers, minimal filestore.
5) CFDP Class 2
   - ACK/NAK, retransmissions, fault handling.
6) ConstellationSim
   - Manage many SpacecraftSim instances.
7) AOS/USLP support
   - Reuse SDLP profile modules once available.

## Known Limitations and Risks
- `TcpServerInterface` currently broadcasts uplink to all clients. This makes
  multi-spacecraft on one interface unsafe until routing by APID/SCID/VCID is added.
- COP-1 depends on TC framing; simulator will be partial until TC is implemented.
- CFDP Class 2 requires careful timer/fault modeling to avoid false positives.

## Follow-on Work
- Add a simulated ground station provider (contact schedules, visibility windows).
- Add orbit/attitude models to drive telemetry and contact availability.
- Add end-to-end COP-1 loopback (FOP + FARM) for ground-side testing.

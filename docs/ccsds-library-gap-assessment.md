---
title: "CCSDS Library Gap Assessment"
tags: [architecture, ccsds, simulator, telemetry, commanding]
status: active
created: 2026-07-19
updated: 2026-07-20
---

# CCSDS Library Gap Assessment

## Purpose

`cadence_ccsds` is the shared, dependency-leaf protocol library used by Cadence
and the simulator. It is deliberately separate from catalog interpretation,
persistence, tenancy, jobs, activation, and runtime orchestration.

The library implements a useful CCSDS subset. It must not yet be described as a
complete CCSDS protocol stack or as flight-qualified.

The standards baseline for this assessment is the
[CCSDS active publications catalog](https://ccsds.org/publications/allpubs/),
including:

- CCSDS 132.0-B-3, TM Space Data Link Protocol;
- CCSDS 133.0-B-2, Space Packet Protocol;
- CCSDS 231.0-B-4, TC Synchronization and Channel Coding;
- CCSDS 232.0-B-4 with corrigendum 1, TC Space Data Link Protocol;
- CCSDS 232.1-B-2 with corrigendum 1, Communications Operation Procedure-1;
- CCSDS 355.0-B-2, Space Data Link Security Protocol;
- CCSDS 732.0-B-5, AOS Space Data Link Protocol; and
- CCSDS 732.1-B-3, Unified Space Data Link Protocol.

## Implemented subset

The shared library currently owns:

- a first-class Space Packet model and strict CCSDS 133.0-B-2 primary-header
  codec;
- bounded streaming Space Packet decoding, independent per-APID sequence
  helpers, and mission-pattern Idle Packet construction;
- semantic `LinkFrame` and `SDUOctets` value types;
- fixed-length TM transfer-frame encoding and decoding;
- TM packet-oriented segmentation and reassembly;
- variable-length TC transfer-frame encoding and streaming decoding;
- the standard TC primary header and one-octet Segment Header;
- TC MAP segmentation and stateful receive reassembly;
- standard CLCW wire encoding and decoding; and
- a small, pure COP-1 sending-side state machine for the current Cadence
  single-release workflow.

Cadence now wraps catalog-compiled `:space_packet` command application data in
telecommand Space Packets before TC segmentation. The uplink gateway maintains
the packet sequence count independently per APID. The simulator removes that
shared packet envelope before invoking the portable catalog command decoder,
and its generated telemetry packets and TM idle padding use the same shared
codec. Packet secondary-header contents remain opaque because their format is
mission-managed by the Space Packet Protocol.

TC Segment Header presence remains a managed per-VC setting, as required by the
protocol. The frame does not carry a Segment Header presence bit. Type-AD
reassembly checks frame sequence continuity; Type-BD reassembly uses arrival
order because Type-B frame sequence numbers are not available for that purpose.

## Remaining gaps

| Priority | Area | Current limitation | Library work |
| --- | --- | --- | --- |
| P0 | Frame error control | TM and TC codecs do not generate or validate the optional Frame Error Control Field. Corrupt frames can be presented as good data. | Add the CCSDS CRC implementation, managed FECF presence, encode/decode validation, and explicit quality/drop evidence. |
| P0 | COP-1 receiving side | There is no FARM-1 implementation. The simulator loopback acknowledges accepted Type-AD frames but does not implement positive/negative windows, lockout recovery, Type-BC control directives, or a persistent receiver state per VC. | Add a pure FARM-1 state machine and make loopback CLCWs come from it. |
| P0 | Full FOP-1 behavior | The current FOP is intentionally a small single-release implementation. It does not implement the complete directive/state machine, configurable sliding window, suspend/resume/initialize procedures, all timer modes, or all alert conditions. | Replace or evolve it behind conformance tests derived from CCSDS 232.1-B-2. |
| P1 | TC service completeness | MAP SDU segmentation/reassembly is present, but Packet, Virtual Channel Access, aggregation, Type-BC control-command data, and managed service rules are not represented as distinct APIs. | Add explicit TC service types and management configuration rather than further overloading generic payload metadata. |
| P1 | TM robustness | TM supports packet-carrying frames with no secondary header. It lacks FECF, VC/MC continuity checks, complete idle-data behavior, secondary-header support, VCA service, and richer decode anomaly reporting across reassembly. | Add managed TM channel configuration, continuity tracking, secondary headers, and complete packet/idle handling. |
| P1 | Synchronization and channel coding | The library starts at transfer frames. It does not construct or decode CLTUs, BCH/LDPC codeblocks, start/tail sequences, attached sync markers, randomization, or channel-quality evidence. | Add a separate coding/synchronization layer so frame services remain usable without a physical-link profile. |
| P1 | Conformance evidence | Tests are focused unit and Cadence loopback tests. There are no published CCSDS golden vectors, property tests, malformed-input corpus, fuzzing, or external implementation interoperability runs. | Establish normative vectors and differential/interoperability tests before making compliance claims. |
| P2 | Other space data links | `Types.profile/0` names AOS and USLP, but no AOS or USLP codecs/services exist. | Implement only when a concrete mission or provider requires them; do not imply support from the type atoms. |
| P2 | Encapsulation packets | CCSDS Encapsulation Packet Protocol is absent. | Add after the Space Packet boundary is stable if non-Space-Packet payloads require a standard envelope. |
| P2 | Space Data Link Security | No SDLS security header/trailer processing, anti-replay state, authentication, or encryption hook exists. | Define algorithm-neutral security transforms and state boundaries; keep key custody outside this library. |
| P2 | Standard time codes | CUC/CDS time-code codecs and correlation helpers are absent. | Add as an independent value-codec namespace when catalog packet layouts need standard time fields. |

## Application-specific follow-through

The library should own wire structures, protocol validation, segmentation,
reassembly, and pure protocol state machines. The applications still need to
compose those pieces:

- `cadence_catalog` supplies compiled application layouts and APID metadata but
  remains independent of protocol framing and persistence;
- Cadence should map activated mission configuration to SCID, VCID, MAP, FECF,
  COP-1, and coding profiles;
- the simulator and Cadence should continue to compose catalog application data
  with the shared protocol codecs rather than duplicating wire headers; and
- Cadence should continue to own persistence, tenancy, revisions, import runs,
  governance, activation, jobs, PubSub, and dashboard invalidation.

## Recommended next slice

The next highest-leverage slice is Frame Error Control Field support shared by
TM and TC:

1. add the CCSDS CRC implementation and standard-derived vectors;
2. model FECF presence as managed channel configuration;
3. generate FECFs during TM and TC encoding;
4. validate FECFs before reassembly and surface explicit corruption evidence;
5. add malformed, truncation, and end-to-end simulator vectors.

FARM-1 should follow FECF. Both remain prerequisites before describing the
uplink path as interoperable COP-1 rather than a deterministic loopback
implementation.

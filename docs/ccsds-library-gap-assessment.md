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
- CCSDS 231.0-B-4 with corrigendum 1, TC Synchronization and Channel Coding;
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
- fixed-length TM transfer-frame encoding and decoding for Packet, Idle Data,
  and VCA_SDU Virtual Channels, with managed channel configuration;
- shared CCSDS Frame Error Control Field generation and validation for TM and
  TC, with managed presence and explicit corruption evidence;
- TM Packet segmentation and continuity-aware reassembly keyed by GVCID,
  including independent MCFC/VCFC tracking, partial-packet disposition, and
  source-frame provenance;
- the complete TM Transfer Frame Secondary Header value codec, managed
  Master/Virtual Channel association, and fixed-length validation;
- standards-shaped Idle Packet filling across frame boundaries and the
  continuous annex-D Only Idle Data PN generator and validator;
- TM Virtual Channel Packet and Virtual Channel Access request/indication
  primitives, including VCA status fields and VCFC-derived loss flags;
- variable-length TC transfer-frame encoding and streaming decoding;
- the standard TC primary header and one-octet Segment Header;
- TC MAP segmentation and stateful receive reassembly;
- standard CLCW wire encoding and decoding; and
- strict Type-BC Unlock and Set V(R) control-command codecs;
- a pure, per-VC FARM-1 receiver implementing the E1-E11 acceptance,
  positive/negative-window, wait, lockout, FARM-B, and reporting behavior; and
- a pure, per-VC FOP-1B sender implementing all six states, standard
  directives, AD/BD/BC lower-layer responses, configurable K and T1 behavior,
  CLCW classification, retransmission, suspend/resume, and standard alerts;
- the TC pseudo-randomizer, systematic BCH(63,56) codeblocks with detection or
  single-error correction, and systematic LDPC(128,64) and LDPC(512,256)
  codeblocks with binary hard-decision validation and single-error correction;
  and
- complete BCH and LDPC CLTU construction and decoding, including managed
  randomization, standard start and tail sequences, fill validation, inverted
  polarity and start-error handling, and per-codeword channel-quality evidence;
- distinct request and indication primitives for the MAPP, VCP, MAPA, VCA,
  VCF, and MCF services, with managed SAP addresses, Type-A/Type-B selection,
  coding repetitions, service-exclusivity validation, and the VCA single-frame
  rule; and
- managed Packet Service formats keyed by Packet Version Number, stable packet
  blocking, MAP packet segmentation, receive extraction, maximum-length
  enforcement, and configurable complete/partial packet delivery evidence.

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

FECF presence is supplied as the managed `fecf: true | false` channel setting;
there is no presence bit in either transfer-frame header. Encoding reserves the
final two octets and includes them in the TC Frame Length count. TM detailed
decoding drops a corrupt fixed-length frame with `:invalid_fecf` evidence, while
TC decoding rejects a corrupt variable-length frame before MAP reassembly. The
Cadence uplink gateway, Cadence TM ingress metadata, simulator TM framing, and
simulator COP-1 loopback all propagate the same managed setting.

The simulator COP-1 loopback now keeps independent FARM-1 state per TC virtual
channel. Only accepted Type-AD and Type-BD data reaches command reassembly.
Valid Type-BC Unlock and Set V(R) commands update FARM-1 directly, and emitted
CLCWs report persistent V(R), Wait, Lockout, Retransmit, and FARM-B state.
Cadence bootstrap seeds the receiver's initial V(R) from the uplink gateway's
current `next_frame_seq`; standalone runs can manage V(R) and the positive and
negative window widths explicitly.

The Cadence uplink gateway composes FOP-1 in synchronous lower-layer mode. It
initializes AD service without a CLCW check, maps the existing maximum-retry
setting to the standard Transmission_Limit, supports K values from 1 through
255, exposes Timeout_Type 0 and 1, and manages one replaceable T1 timer per TC
virtual channel. The library's explicit lower-layer mode and management
directives remain independently usable by other applications and simulators.

The pure TC service provider composes the existing frame, segmentation, and
reassembly primitives without owning scheduling or runtime state. Its receive
boundary expects data frames to have already passed FARM-1 and optional SDLS
processing. MAP, Virtual Channel, and Master Channel multiplexing order remains
mission-managed, as the standard does not prescribe those ordering algorithms.

TM channel configuration now makes the otherwise off-wire physical, Master
Channel, Virtual Channel, and Packet-transfer facts explicit: fixed frame and
FECF sizes, valid SCIDs/VCIDs, Packet versus VCA content, FSH/OCF association,
valid Packet Version Numbers, maximum Packet length, and incomplete-Packet
delivery policy. Configuration-plan validation keeps Master Channel FSH/OCF
settings static across its configured Virtual Channels. The frame decoder
reports malformed headers and managed-setting mismatches, while reassembly
reports MCFC/VCFC discontinuities, orphan continuations, FHP resynchronization,
partial-Packet disposition, invalid Packets, and OID validation failures as
portable anomaly evidence.

## Remaining gaps

| Priority | Area | Current limitation | Library work |
| --- | --- | --- | --- |
| P1 | Conformance evidence | Tests include focused unit, malformed-input, state-machine, deterministic boundary-sweep, and Cadence loopback coverage. There is still no maintained published-vector corpus, generative fuzzing, or external implementation interoperability run. | Establish traceable normative vectors and differential/interoperability tests before making compliance claims. |
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
- Cadence should map activated mission configuration to TC service, SCID, VCID,
  MAP, FECF, COP-1, coding profiles, and the shared managed TM channel model;
- the simulator and Cadence should continue to compose catalog application data
  with the shared protocol codecs rather than duplicating wire headers; and
- Cadence should continue to own persistence, tenancy, revisions, import runs,
  governance, activation, jobs, PubSub, and dashboard invalidation.

## Recommended next slice

The next highest-leverage protocol slice is conformance evidence: establish a
maintained, traceable corpus of normative vectors, then add deterministic
property/generative checks and an external implementation interoperability run.

Published normative vectors, malformed-input/property testing, and external
interoperability evidence still remain prerequisites before describing the
uplink path as a complete interoperable or flight-qualified COP-1
implementation.

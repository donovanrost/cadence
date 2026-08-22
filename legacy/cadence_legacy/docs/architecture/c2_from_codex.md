---
title: CCSDS-Based C2 System Architecture
tags: [architecture, reference, ccsds, commanding]
related:
  - "[[command]]"
  - "[[cop-1]]"
  - "[[interface]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# CCSDS-Based C2 System Architecture (Elixir)

## Purpose

This document defines a long-term CCSDS C2 stack for Cadence with strict layer
boundaries, explicit state ownership, and first-class support for TM, AOS, and
USLP. The goal is to remain faithful to CCSDS concepts while keeping the system
extensible for new PDUs and transport layers.

Goals:
- TM, AOS, and USLP at the Space Data Link layer
- Space Packets, Encapsulation Packets, and declarative custom PDUs
- Future transport layers (CFDP, COP-1)
- Clear separation of wire formats, protocol semantics, and application logic

---

Design Principles

1. Typed artifacts at every boundary
   Raw bytes are only used at the system edges. Each stage emits a struct with
   metadata (origin, timestamps, quality, error flags).
2. Profile-specific SDLP semantics
   TM, AOS, and USLP implement a shared SDLP contract but own their own
   segmentation/reassembly rules.
3. Explicit state ownership
   Any reassembly or transport state lives in a single, clearly scoped service.
4. Deterministic SDU mapping
   Mapping from link identifiers to SDU types is configuration-driven and
   complete for each profile.
5. Schema-driven payloads
   Custom PDUs are defined declaratively with versioned schemas.

---

Core Artifacts (Strict Boundaries)

LinkFrame (SDLP-level)
Represents a TM/AOS/USLP frame and its link metadata.

Required fields:
- profile (tm | aos | uslp)
- scid
- vcid
- map_id (AOS/USLP only)
- frame_seq
- quality
- payload_octets
- ocf (optional)
- timestamp

SDUOctets
Output of profile-specific reassembly. This is the unit consumed by SDU codecs.

Required fields:
- profile
- scid
- vcid
- map_id (AOS/USLP only)
- sdu_kind_hint (from mapping policy)
- octets
- quality
- source_frames

PDU
Decoded payload suitable for transport or application logic.

Examples:
- SpacePacket struct
- EncapsulationPacket struct
- Custom{name, version} map/struct from schema

ReleasedUplinkFrame
Uplink bytes released for transport with link metadata.

Required fields:
- mission_id
- transport_id
- bytes
- kind (direct | initial | retransmit | bypass)
- stream_id (optional)
- seq (optional)
- retries (optional)
- correlation_id (optional, aggregate_id/recording_id)

TransportUnit (optional)
PDU augmented with transport state and context (e.g., CFDP).

---

High-Level Data Flow

Downlink (Read Path)

RF / Modem Bytes
  -> FrameDecode (TM/AOS/USLP) -> LinkFrame
  -> VC/Map Demux (profile) -> LinkFrame streams
  -> Reassembly (profile-specific, stateful) -> SDUOctets
  -> SDUDecode (Space/Encap/Custom) -> PDU
  -> Transport (optional) -> TransportUnit
  -> C2 Routing / Storage / Events

Uplink (Write Path)

Command / PDU
  -> SDUEncode -> SDUOctets
  -> Segmentation (profile-specific, stateful) -> LinkFrame
  -> FrameEncode (TM/AOS/USLP) -> ReleasedUplinkFrame
  -> LinkAdapter -> RF / Modem Bytes

---

Explicit Reassembly Ownership

Reassembly is owned by the SDLP profile, not the generic SDU layer.

- TM Reassembly Service
  Handles TM segmentation rules and VC-level buffering.
- AOS Reassembly Service
  Handles AOS MAP rules and VC/MAP buffering.
- USLP Reassembly Service
  Handles USLP MAPs, variable frame formats, and sequencing semantics.

Each reassembly service:
- Is stateful (GenServer or supervised pipeline stage).
- Owns sequence tracking, loss handling, and quality flags.
- Emits SDUOctets with provenance and confidence.

This prevents generic SDU stages from accumulating profile-specific logic.

---

Deterministic SDU Mapping

Mapping depends on the full link context and is explicit configuration:

- TM: (scid, vcid, direction) -> SDU type
- AOS: (scid, vcid, map_id, direction) -> SDU type
- USLP: (scid, vcid, map_id, direction) -> SDU type

No guessing. Mapping is part of mission/tenant configuration.

---

Module Layout

ccsds/
  core/            # artifact structs, stage interfaces, config plumbing
  sdlp/
    tm/            # TM codec + TM reassembly/segmentation
    aos/           # AOS codec + AOS reassembly/segmentation
    uslp/          # USLP codec + USLP reassembly/segmentation
  sdu/             # SDUOctets, mapping policy, SDU registry
  packet/          # Space Packet codec
  encap/           # Encapsulation Packet codec
  custom/          # schema compiler + versioned registry
  transport/       # CFDP, COP-1, etc
  c2/              # mission-facing pipeline assembly

---

Stage Contracts

FrameDecode / FrameEncode (stateless)
- Pure codec operations for each profile.

Reassembly / Segmentation (stateful, profile-specific)
- Own segmentation semantics and buffering.
- Emit and consume typed artifacts, never raw bytes.

SDUDecode / SDUEncode (stateless)
- Convert SDUOctets <-> PDU based on configured codec.

Transport (stateful)
- Consumes PDUs and manages reliability state and higher-level events.

Uplink Release (stateless)
- Emits ReleasedUplinkFrame for link adapters.
- Avoid direct byte sends outside this contract.

---

Custom PDU Schemas (Versioned)

Schemas are stored with:
(tenant, mission, name, version)

Rules:
- Validate and compile schemas at upload time.
- Decode uses explicit version (no implicit auto-upgrades).
- Support schema migration metadata for replay and compatibility.

---

Multi-Tenant Configuration Boundaries

Each mission/tenant defines:
- Link profile (TM/AOS/USLP)
- SDU mapping policy
- Allowed codec registry entries
- Transport handlers and routes

Pipelines are assembled per mission and do not share state across tenants.

---

Glossary (Artifacts and Ownership)

- LinkFrame: per-frame link artifact, emitted by FrameDecode.
- SDUOctets: reassembled data unit, emitted by profile-specific reassembly.
- PDU: decoded payload, emitted by SDUDecode.
- TransportUnit: transport-managed artifact, emitted by transport handlers.
- Reassembly: stateful service owned by SDLP profile modules only.

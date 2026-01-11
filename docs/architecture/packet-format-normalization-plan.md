# Packet Format Normalization + Deframing Plan

## Goal
Support CCSDS and proprietary packet formats by normalizing all protocol output
into a single internal packet structure. Downstream pipeline stages (identify →
decom → convert → derive → CVT) remain unchanged.

## Strategy
Use one canonical definition-set schema with format-specific parsers/adapters
that map external headers/terminology into the canonical model.

This assumes external formats carry the same core information (packet key,
timestamp, target, payload layout), just with different terminology and framing.

## Big Picture Flow
```
Ingress (interfaces)
  -> Deframer (TM/AOS/USLP)
     -> Packet Parser (CCSDS or custom)
        -> Normalize -> Packet struct
           -> Identify -> Decom -> Convert -> Derive -> CVT
```

## Phase 1 — Inventory & Assumptions (Done)
Touchpoints:
- `Cadence.Telemetry.Packet` (parsing, payload extraction)
- `Cadence.Runtime.Telemetry.PacketIdentifier` (APID-based lookup)
- `Cadence.Telemetry.Decommutation` (binary extraction)
- `ProtocolChain` (format selection via `packet_format/0`)

Implicit assumptions today:
- CCSDS header exists and includes APID.
- `target_id` is injected via metadata.
- Payload is CCSDS binary layout.

## Phase 2 — Normalized Packet Contract
Define a stable internal packet shape and API.

Required fields:
- `mission_id`
- `target_id`
- `raw`
- `format` (ex: `:ccsds`, `:custom_x`)
- `header` (format-specific struct or map)
- `packet_time` (if available)
- `metadata` (source/interface tags)

Required functions:
- `Packet.parse(format, binary, metadata)`
- `Packet.get_payload(packet)`
- `Packet.get_key(packet)` (canonical packet identifier)
- `Packet.get_format(packet)`

### Internal packet shape (conceptual)
```
Packet
  mission_id
  target_id
  format
  header
  packet_time
  raw
  metadata
```

### Canonical fields for definition sets
These fields are the internal model that adapters map into:
- `packet_key`: canonical packet identifier (APID, or custom ID)
- `packet_name`: human-friendly name
- `target_id`: target resolved from deframer/metadata
- `timestamp`: canonical time source (packet or frame)
- `payload_layout`: bit offsets/sizes/types for extraction
- `format`: `:ccsds | :custom_x`

### Canonical packet key options
Candidate keys the adapters can map into `packet_key`:
- `apid` (CCSDS Space Packets)
- `service_subservice` (CCSDS Packet Utilization Standard style)
- `packet_type` (mission-defined numeric ID)
- `message_id` (generic “message type” ID)

Recommendation:
- Keep `packet_key` numeric (integer) when possible.
- Allow `packet_key_alt` (string/tuple) for formats that do not have a single ID.

## Phase 3 — Deframing Layer
Add TM/AOS/USLP deframers as ProtocolChain modules.

Deframer responsibilities:
- delineate frames
- extract SCID/VCID
- map SCID → `target_id`
- emit CCSDS Space Packets + metadata

Deframer output contract:
- `{packet_binary, :ccsds, %{target_id: ..., scid: ..., vcid: ...}}`

### Deframing metadata flow
```
Frame (SCID/VCID)
  -> deframer
     -> metadata.target_id = map(scid)
     -> packet_binary (CCSDS)
```

Decisions:
- SCID → target mapping source (config vs DB)
- Behavior on unknown SCID (drop, quarantine, error)
- OID idle-data validation mode (none/prefix/strict)

### OID (Only Idle Data) handling
OID frames signal "no packets" for a Virtual Channel and should be discarded.
The deframer treats OID frames as empty and clears any partial packet buffer
for the VCID to avoid cross-contamination.

Optional idle-data validation modes:
- `:none` (default): trust FHP=2046, do not validate PN pattern
- `:prefix`: validate the first N bytes of PN idle data
- `:strict`: validate the full data field against the PN sequence

Protocol config example:
```
%{
  protocol_type: :tm_frame,
  protocol_config: %{
    frame_size: 1115,
    scid_target_map: %{42 => "SAT-42"},
    oid_validation: :prefix,
    oid_validation_prefix_bytes: 10
  }
}
```

Simulator note:
- The TM simulator currently pads frames with idle packets (APID 0x7FF).
- If we want to exercise OID frames, add a simulator mode that emits FHP=2046
  with PN idle data in the TFDF for a given VCID.

## Phase 4 — Format Adapter Layer
Implement format adapters:
- CCSDS adapter (existing logic moved under contract)
- Custom format adapter (stub/template)

ProtocolChain integration:
- `packet_format/0` returns `:ccsds | :raw | :custom_x`
- Deframer attaches `format` + metadata

## Phase 5 — Identification & Lane Routing
Identification:
- Replace APID-only lookup with `Packet.get_key/1`
- Maintain target-scoped definition-set lookup
- Format-specific ETS index keys as needed

Lane routing:
- Selectors may match on `packet_key`, `target_id`, `format`,
  or metadata (`interface_id`, `source`)

### Lane/shard routing
```
Packet (target_id, packet_key)
  -> LaneSelector (rules/overrides)
     -> shard = hash(target_id, packet_key, virtual_shards) % shard_count
        -> ShardWorker
```

## Phase 6 — Decommutation Support
Decommutation dispatch:
- Extend `Decommutation.decommutate/3` to accept `:custom_x`
- Implement extractor when payload is not CCSDS binary

## Phase 7 — Tests & Migration
Tests:
- Deframing + SCID → target routing
- Custom format parsing + identification
- Keep CCSDS integration tests intact

Migration:
- CCSDS remains default
- Deframers and custom formats added via interface protocol config

## Open Questions
1. Canonical packet key for custom formats?
2. SCID → target mapping source (config vs DB)?
3. Unknown SCID behavior (drop/park/error)?

## Stack Diagram (where IDs live)
```
Radio Link
  -> TM/AOS/USLP Frame (SCID/VCID live here)
     -> Space Packet (APID or packet_key)
        -> Payload (telemetry fields)
```

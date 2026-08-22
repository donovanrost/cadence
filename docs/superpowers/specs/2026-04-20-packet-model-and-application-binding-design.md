# Design: Packet Model and Application Binding

- Status: draft
- Created: 2026-04-20
- Scope: separate packet-model compilation from built-in telemetry consumption and future custom application binding
- Related ADRs: [001](../../decisions/001-mission-scoped-runtime-and-selector-model.md), [008](../../decisions/008-multi-format-catalog-import-architecture.md), [009](../../decisions/009-canonical-telemetry-catalog-model.md)

## Summary

Cadence currently blurs two different concerns:

- can the imported catalog be represented as runtime packet structure?
- can the built-in telemetry decom runtime consume that structure as operator telemetry?

That blur is acceptable for the earliest built-in telemetry slice, but it becomes misleading as soon as the catalog contains packet content that is valid mission data but not scalar operator telemetry. A `binary` payload field is the clearest example:

- the catalog import is valid
- the packet is real
- the APID may matter operationally
- the built-in telemetry runtime does not know how to turn that field into point samples

Today this tends to surface as an "unsupported telemetry type" diagnostic, which invites the wrong conclusion: that the packet will go unused. The intended Cadence direction is different. Packet structure should be a mission/runtime resource, while built-in telemetry decom and future custom applications should both bind to that resource model.

This design introduces that conceptual split:

1. canonical catalog snapshot
2. packet-model compilation
3. application binding

Under this model, built-in telemetry decom is treated as a first-party application rather than the owner of packet semantics.

## Problem

The current mental model is too telemetry-centric.

In practice:

- the catalog compiler narrows imported packet structure directly into the needs of `definition_bound_telemetry`
- fields outside that built-in telemetry slice appear as "unsupported"
- users may infer that Cadence rejected the packet or that the APID will go unused

That creates three concrete problems:

1. It makes valid payload-bearing packets look like import/runtime failures rather than unclaimed resources.
2. It pushes first-party telemetry decom into the role of "architecture owner" when it should be just one consumer.
3. It makes the future plugin/application model harder, because custom applications would appear to depend on APIDs directly instead of mission packet semantics.

## Goals

- Treat packet definitions as mission-scoped runtime resources, not telemetry-owned resources.
- Make built-in telemetry decom one application consumer of packet structure, not the canonical owner of packet semantics.
- Preserve the distinction between:
  - invalid catalog data
  - packet structures Cadence cannot yet represent generically
  - packet structures Cadence can represent but built-in telemetry does not consume
  - packet structures available for custom application binding
- Give the UI language that keeps users from misreading "not consumed by built-in telemetry" as "dead packet."
- Keep the design compatible with the original plugin/custom-application direction without requiring a full plugin runtime to be built immediately.

## Non-goals

- Designing the full plugin packaging, upload, sandboxing, or execution model.
- Designing application lifecycle, deployment, billing, isolation, or tenancy policy.
- Replacing the current built-in telemetry runtime in this slice.
- Modeling every possible packet-processing use case up front.
- Defining a permanent concrete module or schema name for every proposed concept in this document.

## Current State

Today the main runtime-facing telemetry compilation path does all of the following in one step:

- compile a catalog snapshot
- decide which packets can become governed packet definitions
- decide which definitions become selector inputs for `definition_bound_telemetry`
- emit diagnostics when imported packet content falls outside that runtime slice

That is a reasonable first implementation, but it makes these cases hard to distinguish:

- `string` or `binary` packet fields
- payload packets that need app-specific parsing
- mixed packets where part of the content is operator telemetry and part is opaque payload

The result is that "unsupported by built-in telemetry decom" and "unsupported by Cadence" are easy to conflate.

## Core Idea

Cadence should treat packet structure as a shared mission/runtime substrate.

Applications then consume that substrate.

That means:

- telemetry decom is an application
- payload/science handlers are applications
- mission-specific parsers are applications
- built-in telemetry only has special status because it ships with Cadence and gets first-party UI, not because it owns packet semantics

The important change is not primarily technical. It is a boundary change:

> Packet-model compilation should answer "what packet resources can Cadence represent?"  
> Application binding should answer "which consumer claims which packet resources?"

## Proposed Layering

### 1. Canonical catalog snapshot

This layer remains unchanged in principle.

It preserves imported mission semantics:

- packets
- entries
- points
- types
- units
- calibrations
- provenance

This layer is broader than any one runtime consumer.

### 2. Packet-model compilation

Cadence compiles the canonical snapshot into a generic runtime-facing packet model.

This packet model should be neutral with respect to any specific application.

Conceptually, it includes:

- packet identity
- packet selectors
- scoped applicability such as mission default vs source endpoint override
- field layout
- field type metadata
- opaque binary regions
- packet/field provenance

The packet model should answer questions like:

- what packet does this APID currently resolve to for this mission scope?
- what fields or regions exist in the packet?
- which parts are scalar and directly typed?
- which parts are opaque binary payload regions?

This layer should be allowed to represent more than built-in telemetry decom can consume.

### 3. Application binding

Applications bind to packet-model resources.

Applications should express dependencies in semantic packet terms rather than transport-era literals whenever possible.

Examples:

- built-in telemetry decom binds to scalar telemetry-friendly packet fields
- a payload science application binds to packet `SCIENCE_FRAME`
- a custom app binds to binary region `data_block` inside packet `SCIENCE_FRAME`
- a mission parser binds to all packets matching some packet family or semantic tag

APID may still participate in low-level selector materialization, but it should not be the primary semantic contract once a catalog exists.

## Proposed Runtime Concepts

The exact names can change, but Cadence likely needs the following conceptual objects.

### Packet model

A mission-scoped runtime resource derived from the catalog that represents:

- packet identity
- selector/match metadata
- field and region layout
- scope and precedence

This is the object built-in telemetry decom and custom applications both consume.

### Application input contract

A declaration of what an application can consume from the packet model.

Examples:

- scalar numeric fields
- boolean/enumerated state fields
- whole packets
- named binary regions
- raw packet bytes

Built-in telemetry decom would have one contract. A custom payload app would have a different one.

### Binding or claim

A mission-scoped statement that a specific application instance consumes a packet-model resource.

Examples:

- built-in telemetry claims packet `HK`
- payload app `science_reassembler` claims packet `SCIENCE_FRAME`
- app `spectrometer_decoder` claims field or region `data_block`

This turns "is this packet used?" into a first-class runtime question.

## Built-in Telemetry as a First-Party Application

`definition_bound_telemetry` should be thought of as a first-party application capability.

Its consumption rules are intentionally narrower than the full packet model.

For example, it can consume:

- scalar integers
- floats
- booleans
- enumerated values

It may decline to consume:

- large opaque binary fields
- packet regions that require mission-specific decompression or framing
- structures that make sense only to a domain-specific parser

That is not a packet-model failure. It is simply a statement that the built-in telemetry application does not claim that resource.

## Payload Data and Binary Fields

A packet containing a field like:

```yaml
- name: data_block
  bit_offset: 96
  bit_size: 32672
  data_type: binary
```

should not be framed as "bad telemetry."

Instead:

- the catalog import succeeds
- the packet model preserves the field or region
- built-in telemetry decom does not claim it as operator telemetry
- the packet remains available for custom application binding

That means Cadence should distinguish:

- `valid but not bound to built-in telemetry`
- from
- `invalid`

This is the key UX correction.

## UI and Product Language

The current UX risk is that "unsupported telemetry type" sounds like the packet is not useful.

The import and runtime UI should instead distinguish at least three categories:

1. `Compiled for built-in telemetry`
2. `Available for custom application binding`
3. `Invalid or not yet representable`

For a payload packet, the UI should read more like:

- `Packet model compiled successfully`
- `Not consumed by built-in telemetry`
- `Contains binary payload data`
- `Available for custom mission application binding`

Not:

- `error`
- `dead packet`
- `unused APID`

### Suggested import summary language

- `Packet model compiled: N`
- `Bound to built-in telemetry: M`
- `Available for custom applications: K`
- `Import issues: X`

### Suggested packet detail language

- `Built-in telemetry binding: active`
- `Built-in telemetry binding: not applicable`
- `Custom application bindings: none`
- `Custom application bindings: app-x, app-y`
- `Status: unclaimed`

That vocabulary keeps the architecture honest without forcing the operator to think in internal compiler terms.

## Diagnostics Reframing

Diagnostics that currently appear under telemetry compilation may need to be reclassified over time.

The important distinction is:

- `packet model unsupported`
  Cadence cannot yet represent the packet structure generically

vs

- `built-in telemetry unsupported`
  the packet model is valid, but the built-in telemetry application does not consume it

For example:

- `binary` payload field is likely not a packet-model error
- it is likely a built-in telemetry non-claim

That suggests the long-term diagnostic model should carry a category or stage such as:

- import
- packet model
- built-in telemetry binding
- custom application binding

## Why Not Push All the Way Now

There is a real architectural reason to make this split now:

- it prevents first-party telemetry decom from accidentally becoming the core architecture
- it gives a cleaner foundation for future custom applications
- it fixes misleading import semantics

But there is also a good reason to stop short of a full plugin design in this slice:

- only built-in telemetry exists today
- the custom application contract is not concrete enough yet
- overgeneralizing too early risks vague runtime objects and speculative APIs

So the recommended stopping point for this design is:

- clarify the architecture
- clarify UI semantics
- introduce packet-model neutrality
- defer the full plugin runtime design

## Suggested Incremental Rollout

### Phase 1: conceptual and UX correction

- treat unsupported built-in telemetry cases as "available for custom application binding" where appropriate
- revise import-run and packet detail UI language
- avoid implying that such packets are invalid or dead

### Phase 2: packet-model extraction

- separate generic packet-model compilation from built-in telemetry binding
- persist or expose packet-model resources independently of telemetry-specific governed packet definitions

### Phase 3: application binding model

- introduce first-class application input contracts
- allow built-in telemetry and custom applications to bind to packet-model resources
- track claims and unclaimed packet resources explicitly

## Risks

- If the packet model is defined too abstractly, it may become hand-wavy and not materially help implementation.
- If the UI says "available for custom application binding" before any such binding exists, users may overestimate current capability.
- If APID remains the de facto application contract even after this design, Cadence will carry transport-era coupling into the plugin model.

## Acceptance Criteria

- Cadence documentation and UI distinguish packet-model validity from built-in telemetry consumption.
- A valid payload-bearing packet no longer reads as a dead or rejected packet merely because built-in telemetry does not consume it.
- Built-in telemetry decom is explicitly treated as one application consumer of packet semantics, not the owner of packet semantics.
- The future plugin/application model can be expressed in terms of packet-model resources rather than APIDs alone.

## Open Questions

1. What is the smallest useful packet-model object that is more general than built-in telemetry but less general than a full protocol-agnostic dataflow model?
2. Should "available for custom application binding" appear immediately in the UI, or only once a real application-binding surface exists?
3. Do we want unclaimed packet resources to be visible as a first-class mission inventory from the start?
4. Is there a useful intermediate step where built-in telemetry continues to own persistence, but the UI and architecture docs already describe packet-model neutrality?

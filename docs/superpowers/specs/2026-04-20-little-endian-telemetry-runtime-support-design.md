# Design: Little-Endian Telemetry Runtime Support

- Status: draft
- Created: 2026-04-20
- Scope: add runtime support for little-endian telemetry fields in imported and governed packet definitions
- Related ADRs: [001](../../decisions/001-mission-scoped-runtime-and-selector-model.md), [008](../../decisions/008-multi-format-catalog-import-architecture.md), [009](../../decisions/009-canonical-telemetry-catalog-model.md)

## Summary

Cadence already preserves byte-order metadata in the canonical telemetry catalog, and the legacy `cadence_yaml` importer correctly imports little-endian field encodings into telemetry snapshots. The current runtime compiler, governed packet-definition model, and extractor then narrow that richer catalog down to a big-endian-only execution slice.

That is why imports of `legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml` surface diagnostics such as:

- `telemetry_compiler.type_unsupported`
- `telemetry_compiler.integer_little_endian_unsupported`
- `telemetry_compiler.float_little_endian_unsupported`

These are not source-artifact validation failures. They are runtime materialization failures caused by the current `PacketDefinition` / `FieldDefinition` / `Telemetry.Extractor` slice being unable to represent and decode little-endian multi-byte fields.

This design extends the runtime-facing telemetry packet-definition path so Cadence can materialize and execute common little-endian telemetry fields while preserving the current big-endian behavior and keeping unsupported edge cases explicit.

## Problem

Today:

- The canonical telemetry catalog model stores encoding metadata including byte order.
- The telemetry compiler rejects little-endian multi-byte integers and all little-endian floats.
- The governed runtime `FieldDefinition` does not carry byte order.
- The telemetry extractor decodes values with default Erlang bit syntax, which currently assumes big-endian field interpretation.

This produces three concrete problems:

1. Imported mission databases can succeed as catalog snapshots but fail to become runnable runtime config for common telemetry definitions.
2. The importer UI has to explain warnings that are not actually importer issues but downstream runtime limitations.
3. Cadence cannot faithfully represent heterogeneous mission databases that use little-endian payload fields even when the format is otherwise simple and operationally important.

## Goals

- Support little-endian multi-byte integer telemetry fields in governed packet definitions and runtime extraction.
- Support little-endian 32-bit and 64-bit float telemetry fields in governed packet definitions and runtime extraction.
- Preserve big-endian behavior as the default and avoid changing existing materialized definitions unless they opt into byte order explicitly.
- Make byte order a first-class part of governed runtime packet definitions so recompilation, persistence, diffing, and replay all operate on the same representation.
- Narrow current diagnostics so Cadence only warns or errors on cases the runtime still truly cannot execute.
- Keep import success semantics unchanged: canonical snapshot import remains broader than runtime materialization.

## Non-goals

- Adding little-endian support to the command compiler or commanding runtime. This design is telemetry-only.
- Supporting every possible mixed-endianness, packed-bit, or non-byte-aligned encoding case in the first slice.
- Reworking the canonical telemetry catalog model; that model already carries the needed metadata.
- Executing calibration algorithms that are currently preserved-but-not-run. This is unrelated.
- Adding new UI surface area beyond improved diagnostics wording and richer field metadata where already shown.

## Current State

The limitation is spread across three runtime layers:

### 1. Telemetry compiler

`Cadence.Catalog.Telemetry.Compiler` currently rejects:

- little-endian multi-byte integers
- little-endian floats
- several other unsupported packet-entry and type shapes

The relevant diagnostics are emitted in:

- `compile_integer_data_type/4`
- `compile_float_data_type/4`

File:

- [apps/cadence/lib/cadence/catalog/telemetry/compiler.ex](../../../apps/cadence/lib/cadence/catalog/telemetry/compiler.ex)

### 2. Governed runtime field model

`Cadence.Telemetry.FieldDefinition` currently includes:

- `name`
- `offset_bits`
- `size_bits`
- `data_type`
- `engineering_unit`

It does not include `byte_order`.

Files:

- [apps/cadence/lib/cadence/telemetry/field_definition.ex](../../../apps/cadence/lib/cadence/telemetry/field_definition.ex)
- [apps/cadence/lib/cadence/persistence/schemas/packet_definition_field_row.ex](../../../apps/cadence/lib/cadence/persistence/schemas/packet_definition_field_row.ex)

### 3. Runtime extraction

`Cadence.Telemetry.Extractor` decodes:

- `:uint`
- `:int`
- `:float`
- `:bool`

but does so without any field-level byte-order branch.

File:

- [apps/cadence/lib/cadence/telemetry/extractor.ex](../../../apps/cadence/lib/cadence/telemetry/extractor.ex)

## Runtime capability boundary

Cadence should treat byte order as part of governed runtime packet-definition shape, not as an importer-only detail and not as a special-case decode override.

That means the change spans all of:

- canonical snapshot -> compiler selector input -> governed packet definition
- governed packet definition persistence
- runtime extraction and ingest
- diffing and recompilation

The runtime-facing contract becomes:

> A governed telemetry field definition is not fully described by offset, size, and scalar type alone. For multi-byte integers and floats, byte order is part of the executable definition.

## Scope of support in this slice

This slice supports the common and operationally important cases:

- little-endian unsigned integers where `size_bits` is a multiple of 8 and greater than 8
- little-endian signed integers where `size_bits` is a multiple of 8 and greater than 8
- little-endian floats with `size_bits` of 32 or 64
- big-endian behavior for all currently supported cases

This slice does not support:

- little-endian multi-byte integers whose width is not a multiple of 8
- little-endian floats that are not 32 or 64 bits
- little-endian multi-byte fields whose extracted bit slice is not byte-aligned

Those cases remain explicit diagnostics because their semantics are more subtle and should not be guessed.

This is a deliberate release boundary, not a permanent architectural claim.

## Data model changes

### `Cadence.Telemetry.FieldDefinition`

Add:

- `byte_order :: :big_endian | :little_endian`

Semantics:

- `:big_endian` means explicit big-endian
- `:little_endian` means explicit little-endian

Recommended constructor behavior:

- normalize missing byte order to `:big_endian` when a field is created from new compiler output

### Persistence

Add `byte_order` to `governed_packet_definition_fields`.

Schema and row conversion updates required in:

- `Cadence.Persistence.Schemas.PacketDefinitionFieldRow`
- any packet-definition hydration path that reconstructs `FieldDefinition`

Migration shape:

- edit the existing migration that creates `governed_packet_definition_fields`
- add `byte_order :string` there as a required field from the start

Preferred approach:

- because there are no active missions and the database will be reset during development, do not add a forward migration or backfill path
- require `byte_order` explicitly in the schema and row changeset
- keep DB state and runtime state explicit from the first post-reset boot

### Packet definition shape

`Cadence.Telemetry.PacketDefinition` does not itself need a top-level byte-order field. Byte order should remain per field, because mixed-endianness packets are possible and already representable in the canonical catalog.

## Compiler changes

### High-level change

The telemetry compiler should stop rejecting little-endian fields that the runtime can now execute.

Instead, it should compile field byte order into the governed packet definition.

### Integer compilation

Current behavior:

- reject little-endian multi-byte integers

New behavior:

- compile integers into runtime `FieldDefinition`s with:
  - `data_type: :uint` or `:int`
  - `byte_order: :big_endian | :little_endian`

Diagnostics remain only for:

- little-endian integers whose width is not a multiple of 8
- little-endian integers that are otherwise outside the runtime executable subset

Suggested new diagnostic code for retained unsupported cases:

- `telemetry_compiler.integer_little_endian_non_byte_aligned_unsupported`

This replaces the overly broad current `telemetry_compiler.integer_little_endian_unsupported`.

### Float compilation

Current behavior:

- reject all little-endian floats

New behavior:

- compile 32-bit and 64-bit floats with `byte_order`

Diagnostics remain only for:

- unsupported float sizes
- little-endian float fields that are not byte-aligned

Suggested new diagnostic code for retained unsupported cases:

- `telemetry_compiler.float_little_endian_non_byte_aligned_unsupported`

### Type support diagnostics

`telemetry_compiler.type_unsupported` should continue to mean true type-family unsupported cases such as:

- string
- binary
- aggregate-only shapes not yet flattened into packet fields

It should not be relied on to paper over byte-order limitations once those limitations are lifted.

## Runtime extraction changes

### Extraction contract

`Cadence.Telemetry.Extractor` should decode values based on:

- `field.data_type`
- `field.size_bits`
- `field.byte_order`

### Integer decoding

For integers:

- big-endian path remains as-is
- little-endian path requires a byte-oriented decode

Implementation shape:

1. extract `value_bits`
2. assert byte-aligned little-endian preconditions when `field.byte_order == :little_endian`
3. convert the extracted bitstring to bytes
4. decode with little-endian integer syntax or equivalent byte-reversal logic

The extractor should return a precise error when a field requests little-endian decoding but the slice is not byte-aligned. Suggested error:

- `{:little_endian_requires_byte_alignment, offset_bits, size_bits}`

### Float decoding

For floats:

- retain current big-endian decode for 32 and 64 bits
- add little-endian float decode for 32 and 64 bits

The same byte-alignment rule applies.

### Bool decoding

No behavioral change:

- one-bit booleans remain endian-insensitive in practice and should continue to decode exactly as today

## Recompilation, diffing, and governance

Because byte order becomes part of governed field definitions, recompilation and runtime diff must surface it.

That means:

- materialized packet definitions differing only in byte order are real diffs
- `RuntimeDiff` should compare `byte_order`
- any JSON serialization of runtime-facing packet-definition fields should include byte order

This is important because otherwise the system would falsely report "matching" runtime definitions that would decode different numeric values.

## Backwards compatibility

This slice assumes early-development database reset semantics.

Compatibility rules:

- edit the existing migration rather than adding a new additive migration
- reset the local database as part of implementation
- require explicit `byte_order` on all governed packet-definition fields after the reset

This keeps the runtime model simpler and avoids carrying transitional compatibility code for data that does not need to survive.

## Importer and UI implications

The importer itself does not fundamentally change.

What changes is the meaning of diagnostics:

- catalogs that previously imported with runtime warnings may become fully materializable
- the importer UI should continue to distinguish:
  - snapshot import success
  - runtime materialization success

Recommended UI language:

- `Imported into catalog successfully`
- `Runtime-compatible definitions: N`
- `Definitions requiring richer runtime support: M`

For the `demo_spacecraft.yaml` case, once this design lands, little-endian integer and float warnings should disappear for fields that fall inside the newly supported execution subset.

## Testing strategy

### Compiler tests

Expand `Cadence.Catalog.TelemetryCompilerTest` to cover:

- little-endian 16-bit integer compiles successfully
- little-endian 32-bit integer compiles successfully
- little-endian 32-bit float compiles successfully
- little-endian 64-bit float compiles successfully
- little-endian non-byte-multiple integer remains a diagnostic
- little-endian byte-offset-misaligned multi-byte field remains a diagnostic

### Extractor tests

Add direct `Cadence.Telemetry.Extractor` tests for:

- big-endian integer regression coverage
- little-endian integer decode
- big-endian float regression coverage
- little-endian float decode
- explicit byte-alignment failure for little-endian multi-byte fields

### End-to-end ingest tests

Add or extend:

- `Cadence.ProcessTelemetryIngressTest`
- `Cadence.Persistence.PersistTelemetryIngressTest`

with packets containing:

- little-endian 16-bit integer fields
- little-endian 32-bit float fields

and assert:

- raw values are decoded correctly
- persisted sample rows contain the correct values
- existing big-endian tests remain unchanged

### Importer coverage

Add a focused importer test using a YAML payload with:

- one little-endian integer field
- one little-endian float field

and assert:

- canonical snapshot import succeeds
- recompilation produces packet definitions instead of diagnostics
- materialized binding set persists successfully
- ingest against the materialized binding set yields correct decoded telemetry values

## Rollout plan

Suggested implementation order:

1. Edit the existing packet-definition-field migration to add `byte_order`, then reset the database
2. Extend `FieldDefinition` and DB persistence with explicit `byte_order`
3. Add extractor decode support
4. Relax compiler diagnostics and emit `byte_order`
5. Update diffing and runtime JSON serialization
6. Add end-to-end importer and ingest tests
7. Update importer UI copy to reflect narrower runtime warnings

This order keeps the compiler from emitting definitions the runtime cannot yet execute.

## Risks

- Byte-order bugs are silent correctness bugs, not obvious crashes. Test coverage must be value-based, not just "did compile".
- Little-endian packed fields that are not byte-aligned are easy to mis-handle. This design intentionally keeps them out of scope for the first slice.

## Acceptance criteria

- The telemetry compiler no longer emits broad little-endian unsupported diagnostics for byte-aligned multi-byte integers and 32/64-bit floats.
- Governed packet definition fields persist byte order explicitly.
- The runtime extractor decodes supported little-endian integer and float values correctly.
- Existing big-endian telemetry behavior remains unchanged.
- `demo_spacecraft.yaml` imports with fewer runtime-compiler warnings, specifically removing little-endian warnings for supported fields.
- Runtime diff treats byte order as a meaningful field-definition attribute.

## Open questions

1. Do we want the first slice to support byte-aligned little-endian fields only, or also any field whose extracted slice length is a multiple of 8 even if the starting offset is not byte-aligned?
2. Should the importer UI surface a separate count for "catalog preserved but runtime unsupported" definitions, or is the existing diagnostics list sufficient?

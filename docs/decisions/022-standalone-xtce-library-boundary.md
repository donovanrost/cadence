---
title: "ADR-022: Standalone XTCE Library Boundary"
tags: [adr, architecture, xtce, catalog, packages, hex, licensing]
status: accepted
created: 2026-08-21
updated: 2026-08-21
---

# ADR-022: Standalone XTCE Library Boundary

## Status

Accepted

This decision refines ADR-020 and ADR-021. It does not change the decision that
Cadence's Mission Model is the canonical semantic representation consumed by
runtime compilers.

## Context

XTCE is an OMG interchange standard for spacecraft telemetry and commanding
data. The initial Cadence implementation placed bounded XML parsing, normative
schema validation, source-tree traversal, and Cadence Mission Model translation
inside `cadence_catalog`.

That placement mixed two different responsibilities:

- interpreting and validating an XTCE document; and
- translating a valid XTCE document into Cadence's canonical declarations.

The former is useful to any Elixir ground system, analysis tool, validator, or
mission-database workflow. It should not require Cadence types or imply that
Cadence's semantic and runtime models are part of XTCE itself.

## Decision

The dependency-leaf package `packages/xtce` owns the `XTCE.*` modules and OTP
application `:xtce`.

The initial public package supports OMG XTCE 1.3 and owns:

- bounded parsing of binary and filesystem inputs;
- rejection of XML document type and entity declarations;
- identification of the supported namespace and version;
- a small, queryable `XTCE.Document` and `XTCE.Element` source model;
- explicit byte, depth, and element-count limits; and
- validation against a content-addressed, offline copy of the normative schema.

The package has no dependency on `cadence_catalog`, does not expose Cadence
types, and does not own persistence, source-artifact governance, semantic
reference resolution, runtime compilation, algorithm execution, or commanding
policy.

`cadence_catalog` depends on `xtce`. Its XTCE importer remains a Cadence adapter
that supplies importer metadata, translates `XTCE.Document` values into Mission
Model declaration layers, preserves source provenance, and emits
Cadence-specific diagnostics. The Mission Model XTCE exporter also remains in
`cadence_catalog` because its input is a Cadence revision, not a neutral XTCE
document model.

Conceptually:

```text
XTCE XML
    -> packages/xtce: parse and schema-validate
    -> XTCE.Document
    -> packages/cadence_catalog: Cadence importer adapter
    -> Mission Model declarations and compiler targets
```

The library source is licensed under Apache-2.0 and carries the metadata,
documentation, changelog, and file manifest needed to build a standalone Hex
artifact. Building and inspecting an artifact is not publication.

The vendored OMG and W3C schemas are third-party standards assets and are not
relicensed under Apache-2.0. Their provenance and hashes are recorded in
`THIRD_PARTY_NOTICES.md`. An actual Hex publication containing those assets
requires confirmation that their redistribution and attribution terms are
satisfied.

Schema validation uses `xmllint --nonet`; parsing does not require `xmllint`.
The schema is never selected from an input document and validation does not
perform network access.

## Consequences

- Elixir consumers gain a neutral XTCE package without importing Cadence.
- Cadence retains its compiler and runtime boundaries from ADR-020.
- The project can add typed XTCE schema models, additional versions, and
  document generation behind versioned public APIs.
- The package's focused tests can run without starting Cadence.
- `cadence_catalog` becomes a consumer and adapter rather than the owner of XML
  parsing and schema assets.
- Schema validation retains an external `xmllint` runtime prerequisite.
- Hex publication remains gated on third-party schema redistribution review.

## Alternatives Considered

### Move the Cadence Mission Model into `xtce`

Rejected. The Mission Model incorporates Cadence compiler and runtime concerns
and deliberately is not the literal XTCE object model.

### Make `xtce` depend on `cadence_catalog`

Rejected. That would preserve the coupling under a neutral package name and
create the wrong dependency direction.

### Leave all XTCE code in `cadence_catalog`

Rejected. Parsing and standards validation are independently useful and do not
need Cadence's catalog abstractions.

## See Also

- [ADR-008: Multi-Format Catalog Import Architecture](008-multi-format-catalog-import-architecture.md)
- [ADR-020: XTCE-Informed Mission Model Intermediate Representation](020-xtce-informed-mission-model-intermediate-representation.md)
- [ADR-021: Monorepo Poncho Project and Package Layout](021-monorepo-poncho-project-and-package-layout.md)

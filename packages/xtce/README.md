# XTCE

`xtce` is an Elixir library for reading and validating XML Telemetric and
Command Exchange documents. It provides a bounded XML parser, a queryable
document tree, and offline validation against the pinned normative OMG XTCE
1.3 schema.

The package is independent of Cadence and does not impose a mission database,
runtime, persistence, or deployment model on consumers.

## Installation

Once published to Hex, add `xtce` to your dependencies:

```elixir
def deps do
  [
    {:xtce, "~> 0.1.0"}
  ]
end
```

From this monorepo, use the local package instead:

```elixir
def deps do
  [
    {:xtce, path: "../path/to/packages/xtce"}
  ]
end
```

## Parsing

```elixir
xml = File.read!("mission.xml")

{:ok, document} = XTCE.parse(xml)

document.version
#=> "1.3"

XTCE.Element.attr(document.root, "name")
#=> "MyMission"

XTCE.Element.descendants(document.root, "Parameter")
```

Parsing rejects XML document type and entity declarations before invoking the
XML parser. The default limits are 10 MiB, 128 levels, and 250,000 elements;
callers can lower them explicitly:

```elixir
XTCE.parse(xml, max_bytes: 1_000_000, max_depth: 64, max_nodes: 50_000)
```

## Schema validation

```elixir
:ok = XTCE.validate(xml)
{:ok, document} = XTCE.parse(xml, validate_schema: true)
```

Validation uses a content-addressed, vendored copy of the normative XTCE 1.3
schema with `xmllint --nonet`. It never follows schema locations supplied by an
input document. The `xmllint` executable must be installed for schema
validation; parsing does not require it.

The normative schema is third-party material and is not relicensed under
Apache-2.0. See `THIRD_PARTY_NOTICES.md`. Confirm its redistribution terms with
OMG before publishing a Hex release containing the vendored asset.

## Current scope

Version 0.1 provides:

- XTCE 1.3 namespace identification;
- bounded binary and file parsing;
- a small XML document and element model;
- source line metadata and tree query helpers;
- pinned, offline normative-schema validation; and
- explicit errors for unsupported versions, invalid roots, unsafe XML, and
  exceeded resource limits.

The current release does not yet provide a fully typed representation for every
XTCE schema type, document generation, older XTCE versions, semantic reference
resolution, or execution of algorithms and command verifiers. Those concerns
will be added behind versioned APIs without coupling the package to one ground
system's runtime model.

## Development

From `packages/xtce`:

```sh
mix deps.get
mix test
mix docs
mix hex.build --unpack
```

The repository-wide authoritative gate is run from the monorepo root with
`mix precommit`.

## License

The library source is governed by the Apache License 2.0. See `LICENSE` for the
complete terms. Vendored standards assets retain their respective ownership and
terms as recorded in `THIRD_PARTY_NOTICES.md`.

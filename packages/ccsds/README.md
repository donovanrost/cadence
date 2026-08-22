# CCSDS

`ccsds` is a dependency-free Elixir library for a tested subset of the
Consultative Committee for Space Data Systems protocol family. It provides
immutable protocol values, strict wire codecs, segmentation and reassembly
helpers, and pure state machines that can be embedded in applications without
bringing along persistence, networking, or runtime supervision.

The current surface includes:

- Space Packet and Encapsulation Packet protocols;
- TM, TC, AOS, and USLP transfer frames and service primitives;
- COP-1 FARM-1 and FOP-1 state machines;
- CFDP wire types and Class 1/Class 2 transfer procedures;
- Space Data Link Security orchestration;
- CUC and CDS time codes; and
- TC channel coding, CLTU, randomization, FECF, BCH, and LDPC helpers.

The library implements a useful subset of the cited CCSDS standards. It is not
a complete CCSDS protocol stack and is not flight-qualified software.

## Installation

Once published to Hex, add `ccsds` to your dependencies:

```elixir
def deps do
  [
    {:ccsds, "~> 0.1.0"}
  ]
end
```

From this monorepo, use the local package instead:

```elixir
def deps do
  [
    {:ccsds, path: "../path/to/packages/ccsds"}
  ]
end
```

## Example

```elixir
alias CCSDS.SpacePacket
alias CCSDS.SpacePacket.Codec

packet =
  SpacePacket.new(
    packet_type: :telemetry,
    apid: 42,
    sequence_count: 7,
    data: <<1, 2, 3>>
  )

{:ok, encoded} = Codec.encode(packet)
{:ok, ^packet} = Codec.decode(encoded)
```

## Design boundary

The package owns wire structures, validation, codecs, segmentation,
reassembly, and pure protocol transitions. Consuming applications retain
ownership of:

- sockets and other transports;
- files and persistent storage;
- timers and process lifecycle;
- mission configuration and catalog interpretation; and
- authorization, scheduling, telemetry, and operational policy.

This keeps the protocol implementation deterministic and usable outside
Cadence.

## Standards and conformance

The implementation identifies the relevant CCSDS publication and issue in its
module documentation. Maintained normative-vector provenance and optional
cross-implementation harnesses live in the repository's
[conformance directory](https://github.com/donovanrost/cadence/tree/main/packages/ccsds/conformance);
they are intentionally excluded from the Hex runtime artifact.

Conformance evidence is evidence for the implemented subset, not a claim of
complete standards coverage or flight qualification.

## Development

From `packages/ccsds`:

```sh
mix deps.get
mix test
mix docs
mix hex.build --unpack
```

The repository-wide authoritative gate is run from the monorepo root with
`mix precommit`.

## License

Copyright and use of this package are governed by the Apache License 2.0. See
`LICENSE` for the complete terms.

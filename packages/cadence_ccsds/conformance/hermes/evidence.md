# Maintained NASA Hermes interoperability run

- Status: PASS
- Run date: 2026-07-20
- Host: Darwin 24.6.0 arm64
- External implementation: NASA Hermes v4.0.11
- External commit: `433a8f9fc69a078eb430dab01285d7644e78eb07`
- Go runtime: go1.26.0
- Space Packet cases: 260
- Type-BD TC transfer-frame cases with FECF: 128
- TM transfer-frame cases: 128
- Concatenated wire-byte SHA-256:
  `a9e02e21288a66d91d2a052cf87b4dc915b2cc154f5d287b086ea30ba5c56f90`

Reproduction command, from `packages/cadence_ccsds`:

```sh
bash conformance/hermes/run.sh
```

For every case, Cadence first produces the wire bytes. The pinned Hermes codec
decodes those bytes, independently marshals the same semantic value, and
requires byte equality. Cadence then decodes the Hermes-produced bytes and
requires semantic equality. Generated cases cover boundary values and a stable
deterministic sweep of identifiers, counters, flags, data lengths, secondary
headers, and payload bytes.

Hermes v4.0.11 exposes only Type-BD TC frame generation and does not generate
TM OCF or TM FECF variants. Those features remain covered by the normative
corpus and seeded in-process properties; this external run does not claim they
were compared with Hermes.

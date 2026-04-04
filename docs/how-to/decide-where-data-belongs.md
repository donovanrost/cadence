---
title: Decide Where New Data Belongs
tags: [how-to, developer, architecture, persistence, storage]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Decide Where New Data Belongs

This guide describes how to decide whether a new piece of data belongs in:

- runtime state
- Postgres
- an archive backend
- an event stream or transient bus

This is one of the most important architectural decisions in Cadence. Getting
it wrong usually means putting too much work on the live ingress path.

## 1. Start with the question the data answers

Ask what kind of question this data exists to answer.

Common categories:

- "what is the latest value right now?"
- "what happened historically?"
- "what control-plane state governs the system?"
- "what needs to be visible live but not durably queried later?"

Those questions usually map to different storage tiers.

## 2. Use runtime state for latest operational values

Use runtime state when the main question is:

> what is the latest value right now?

Examples:

- latest telemetry point value
- current lane status
- in-flight backpressure state
- runtime counters that do not need durable history

The main current example is:

- [`Cadence.Telemetry.CurrentValueStore`](../../apps/cadence/lib/cadence/telemetry/current_value_store.ex)

The default backend is ETS, which is hot-path safe and optimized for latest
value reads.

Use runtime state when:

- the value is mutable
- only the latest version matters
- rebuilding it from durable sources is acceptable

Do not use runtime state as a durable history store.

## 3. Use Postgres for low-rate queryable control-plane facts

Use Postgres when the data is:

- low or moderate rate
- relational
- queryable by APIs or future UI surfaces
- important to keep durably and directly readable

Good Postgres candidates:

- missions
- identities and sessions
- contacts and activations
- approvals and command governance
- protocol anomalies
- lightweight archive index rows

Bad default Postgres candidates:

- one row per raw ingress message at high rate
- one row per packet or frame when the main need is archive or replay
- high-rate per-packet routing decisions with no live OLTP use case

## 4. Use an archive backend for high-rate append-only history

Use an archive when the data is:

- high rate
- append-only
- primarily useful for replay, forensics, or bulk history
- expensive to keep as always-on OLTP rows

Current examples:

- [`Cadence.IngressArchive`](../../apps/cadence/lib/cadence/ingress_archive.ex)
- [`Cadence.Protocol.RecordArchive`](../../apps/cadence/lib/cadence/protocol/record_archive.ex)

Good archive candidates:

- raw ingress evidence
- packet records
- transfer-frame records
- high-rate dispatch decision history, if retained at all

The working pattern is:

- archive the durable stream
- keep a lightweight index for discovery
- rebuild richer views from the archive when needed

## 5. Use a transient event stream for live visibility

Some data should be visible live without becoming durable OLTP state.

Use a transient event stream or PubSub-style fan-out when the question is:

> who needs to observe this right now?

Examples:

- live UI activity feeds
- recent dispatch activity
- live operator status panels
- debug observers

Do not make a transient bus the only durable persistence mechanism for
important data. It is for live fan-out, not primary archival truth.

## 6. Ask whether the data is primary truth or derived projection

This is the fastest architecture test.

If the data is primary truth:

- keep it in a durable authoritative store
- or archive it as the durable event source

If the data is derived:

- prefer recomputation or projection
- avoid persisting it as a first-class always-on row unless a real query need
  justifies it

Examples:

- raw evidence is primary durable input
- latest value is a derived runtime projection
- many dispatch work items are execution artifacts, not durable truth

## 7. Ask whether it belongs on the hot path

If the data must be recorded for correctness, ask whether it must be written
before the ordered ingress lane can move on.

In general:

- latest-value runtime updates may belong on the hot path
- archive and Postgres writes usually do not
- projections should prefer the async projector lane

If a new feature requires high-rate synchronous writes in the live executor,
assume the burden of proof is on that feature.

## 8. Use this rule of thumb

If you are unsure, use this default:

- latest mutable operational view -> runtime state
- high-rate historical stream -> archive
- low-rate operational fact or control-plane state -> Postgres
- live observation only -> event stream

That rule is better than "put it in Postgres because that is easy."

## 9. Examples from the current architecture

Good current placements:

- current telemetry values -> ETS
- telemetry sample history -> pluggable history store, default `Noop`
- raw ingress evidence -> ingress archive
- packet/frame records -> protocol archive
- protocol anomalies -> Postgres
- contact, mission, auth, and approval state -> Postgres

Recent decisions that moved data out of OLTP Postgres:

- raw ingress evidence
- packet and transfer-frame records
- dispatch decisions and work items from the live path

Those moves were driven by performance and by a better distinction between
control-plane data and archive data.

## 10. A quick review checklist

Before adding a new persisted record, ask:

- is this latest state, historical stream, or control-plane fact?
- is the data primary truth or derived?
- what user or system query requires it later?
- does it need durable retention, or just live visibility?
- does it have to be written on the hot path?
- if archived, what lightweight index or replay filter is needed?

If you cannot answer those questions clearly, the data model decision is not
ready yet.

---
title: Recording
aliases: [recordings, recording index]
tags: [glossary, event-sourcing, recordings]
related:
  - "[[recordable]]"
  - "[[aggregate]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Recording

A **Recording** is an index entry in the `recordings` table that links events to their [aggregates](aggregate.md).

## Purpose

The recordings table is a **pure index** - it contains metadata for querying and linking, not event details. The actual event data lives in [Recordable](recordable.md) tables.

## Key Fields

| Field | Purpose |
|-------|---------|
| `aggregate_type` / `aggregate_id` | What entity this event is about |
| `recordable_type` / `recordable_id` | Polymorphic reference to event details |
| `parent_id` / `root_id` | Causality chain (which event caused this one) |
| `actor_id` / `actor_type` | Who/what triggered this event |
| `timestamp` | When the event occurred (business time) |
| `target_id` | Optional filter for target-scoped queries |

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Recordings.Recording` | Ecto schema |
| `Cadence.Recordings` | Context module with query functions |

## Related Concepts

- [Recordable](recordable.md) - The event details a recording points to
- [Aggregate](aggregate.md) - The entity whose history recordings track

## See Also

- [Adding a Recordable](../patterns/adding-recordable.md) - Full pattern guide

---
title: Recordable
aliases: [recordables, event type]
tags: [glossary, event-sourcing, recordings]
related:
  - "[[recording]]"
  - "[[aggregate]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Recordable

A **Recordable** is a strongly-typed event stored in its own dedicated table.

## Purpose

Instead of one giant `events` table with a JSON blob, each event type gets its own table with proper columns. This provides:

- **Type safety** - Schema enforces required fields
- **Query efficiency** - Index on specific columns
- **Flexibility** - Rich events have many columns, minimal events have few

## Richness Levels

| Level | Description | Example |
|-------|-------------|---------|
| Rich | Many domain-specific columns | `CommandDispatched` (name, params, target, hazardous) |
| Medium | A few key columns | `CommandVerified` (result, stages) |
| Minimal | Just an ID and maybe one field | `CommandSent` (interface_id) |

## The Recordable Protocol

All recordables implement `Cadence.Recordings.Recordable`:

```elixir
defprotocol Cadence.Recordings.Recordable do
  def recording_type(recordable)  # e.g., "CommandDispatched"
  def aggregate_type(recordable)  # e.g., "Command"
  def title(recordable)           # Display title for timeline
  def status(recordable)          # Status string for display
  def severity(recordable)        # Severity level (alarms)
end
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Recordings.Recordable` | Protocol definition |
| `Cadence.Recordings.Recordables.*` | Individual recordable schemas |

## Related Concepts

- [Recording](recording.md) - Index entry that points to recordables
- [Aggregate](aggregate.md) - Entity whose state is derived from recordables

## See Also

- [Adding a Recordable](../patterns/adding-recordable.md) - How to create new recordable types

---
title: Design
tags: [design, index]
created: 2025-01-27
updated: 2026-01-29
status: active
---

# Design

Feature design documents describing how features should work.

For implementation plans and roadmaps, see [Plans](../plans/README.md).

## Procedures

The procedures system encompasses [sequences](../glossary/sequence.md), [automations](../glossary/automation.md), scripts, and campaigns.

> **Key Decision:** [ADR-002: Luerl for Procedure Execution](../decisions/002-luerl-for-procedures.md)

| Document | Description |
|----------|-------------|
| [Procedures](procedures.md) | Overview of the procedures system (current V2) |
| [Procedure Inputs](procedure-inputs.md) | Input handling design |
| [DAG Editor](dag-editor.md) | Visual editor design |
| [Procedures UI/UX](procedures-ui-ux-design.md) | User interface design |
| [Epsilon3-like Data Model](epsilon3-like-procedures-data-model.md) | Block-based data model design (~70% implemented) |

## Operational UI

| Document | Description |
|----------|-------------|
| [Timeline Mode](timeline-mode.md) | Unified chronological view of mission activity |
| [Configuration UI](configuration-ui-design.md) | Configuration interface design |

## UI Reference

For colors, components, and styling see the [Design System](../design-system/README.md).

> **Note:** Error handling patterns moved to [Patterns](../patterns/error-handling.md)

## See Also

- [Architecture](../architecture/_index.md) - System-level context
- [Patterns](../patterns/_index.md) - Implementation templates
- [Archive](../archive/) - Historical plans and superseded designs

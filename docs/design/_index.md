---
title: Design
tags: [design, index]
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Design

Feature design documents and implementation plans.

## Procedures

The procedures system encompasses [sequences](../glossary/sequence.md), [automations](../glossary/automation.md), scripts, and campaigns.

> **Key Decision:** [ADR-002: Luerl for Procedure Execution](../decisions/002-luerl-for-procedures.md)

| Document | Description |
|----------|-------------|
| [Procedures](procedures.md) | Overview of the procedures system |
| [Procedure Inputs](procedure-inputs.md) | Input handling design |
| [Procedure DAG and Inputs](procedure-dag-and-inputs.md) | DAG-based execution model |
| [DAG Editor](dag-editor.md) | Visual editor design |
| [Procedures UI/UX](procedures-ui-ux-design.md) | User interface design |
| [Procedures Refactor Plan](procedures-refactor-plan.md) | Refactoring roadmap |
| [Procedures Testing Plan](procedures-testing-plan.md) | Test strategy |
| [V2 Execution Layering](v2-execution-layering-refactor.md) | Execution architecture |
| [Epsilon3-like Data Model](epsilon3-like-procedures-data-model.md) | Data model design |

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

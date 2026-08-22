---
title: Cadence Documentation
tags: [index, entry-point]
created: 2025-01-27
updated: 2026-01-29
status: active
---

# Cadence Documentation

Cadence is a multi-tenant SaaS platform for managing constellation-scale spacecraft operations.

## Navigation

### By Topic

| Area | Description |
|------|-------------|
| [Glossary](glossary/_index.md) | Canonical terminology and definitions |
| [Concepts](concepts/_index.md) | Core concepts and mental models |
| [Architecture](architecture/_index.md) | System design and component interactions |
| [Design](design/_index.md) | Feature design documents and plans |
| [Patterns](patterns/_index.md) | Templates for extending the codebase |
| [Decisions](decisions/_index.md) | Architecture Decision Records (ADRs) |
| [Design System](design-system/README.md) | UI components, colors, and styling |
| [Research](research/_index.md) | Competitive analysis and feature research |
| [Plans](plans/README.md) | Active implementation plans and roadmaps |
| [Archive](archive/README.md) | Historical planning documents |

### Quick Links

- [Data Plane / Control Plane](architecture/data-plane-control-plane.md) - Core architectural separation
- [ADR-001: No DB in Data Plane](decisions/001-no-db-in-data-plane.md) - Key architectural decision
- [Adding a Recordable](patterns/adding-recordable.md) - Event sourcing pattern guide
- [Procedures](design/procedures.md) - Sequences, automations, and scripts

## For LLMs

1. Start with [Glossary](glossary/_index.md) to understand terminology
   - Core: [Mission](glossary/mission.md), [Target](glossary/target.md), [Interface](glossary/interface.md)
   - Architecture: [Data Plane](glossary/data-plane.md), [Control Plane](glossary/control-plane.md)
2. Check [Decisions](decisions/_index.md) before modifying architecture
3. Follow [Patterns](patterns/_index.md) when extending the codebase

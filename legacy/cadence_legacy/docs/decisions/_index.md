---
title: Architecture Decision Records
tags: [decisions, adr, index]
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Architecture Decision Records

ADRs capture significant architectural decisions and their rationale. Check here before modifying architecture to avoid undoing intentional choices.

## Accepted Decisions

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](001-no-db-in-data-plane.md) | No Database Calls in Data Plane | Accepted |
| [ADR-002](002-luerl-for-procedures.md) | Luerl for Procedure Execution | Accepted |

## Planned ADRs

Decisions embedded in existing docs that should be extracted:

- **Recordables Pattern for Event Sourcing** - From [Adding a Recordable](../patterns/adding-recordable.md)
- **Hexagonal Architecture** - From [Data Plane / Control Plane](../architecture/data-plane-control-plane.md)

## ADR Template

```markdown
---
title: "ADR-NNN: Title"
tags: [adr, topic]
status: proposed | accepted | deprecated | superseded
created: YYYY-MM-DD
---

# ADR-NNN: Title

## Status
Accepted

## Context
What's the situation? What forces are at play?

## Decision
What did we decide?

## Consequences
What are the trade-offs? What does this enable/prevent?
```

## See Also

- [Architecture](../architecture/_index.md) - Technical details
- [Glossary](../glossary/_index.md) - Terminology

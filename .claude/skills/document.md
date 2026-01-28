# /document - Obsidian-Style Documentation Skill

Write and maintain documentation as a well-organized vault with atomic, linked notes. This skill prevents the common LLM pattern of creating new monolithic files that make existing docs stale.

## Quick Checklist

Before writing any doc:
- [ ] Search for existing docs on the topic
- [ ] Check glossary for related terms
- [ ] Decide: update existing or create new?

When creating/updating:
- [ ] Add/update frontmatter (title, tags, status, dates)
- [ ] Add glossary quick links at top if referencing terms
- [ ] Link to related docs in body
- [ ] Update the directory's `_index.md`
- [ ] Update `updated:` date

---

## Core Principles

1. **Atomic notes** - One concept per file, linked together
2. **Update over create** - Modify existing docs, don't create parallel versions
3. **Glossary-first** - Define terms in glossary, link everywhere else
4. **Context-aware** - Keep files focused so LLMs can load just what they need
5. **Module references** - Reference modules, not file paths

---

## Directory Structure

```
docs/
├── index.md                    # Entry point, links to all sections
├── glossary/                   # Canonical terminology (check first!)
│   ├── _index.md              # Term list with brief definitions
│   └── *.md                   # One file per term
├── concepts/                   # Core mental models (often points to glossary)
│   └── _index.md
├── architecture/               # System design and implementation plans
│   ├── _index.md
│   └── *-plan.md              # Implementation plans
├── design/                     # Feature design documents
│   ├── _index.md
│   └── *.md
├── decisions/                  # Architecture Decision Records (ADRs)
│   ├── _index.md
│   └── NNN-*.md               # Numbered decisions
├── patterns/                   # Templates for extending the codebase
│   ├── _index.md
│   └── *.md
├── design-system/              # UI components, colors, styling
│   ├── README.md
│   └── *.md
└── research/                   # Competitive analysis, feature research
    ├── _index.md
    └── *.md
```

---

## Frontmatter

### Minimum Viable (for quick updates)

```yaml
---
title: Human Readable Title
tags: [category, topic]
status: active
updated: 2025-01-27
---
```

### Full (for new docs)

```yaml
---
title: Human Readable Title
aliases: [alternate name, abbreviation]
tags: [architecture, interfaces, runtime]
created: 2025-01-27
updated: 2025-01-27
status: active
---
```

**Status values:** `draft` | `active` | `deprecated`

**Common tags:**
- Categories: `architecture`, `design`, `pattern`, `adr`, `glossary`, `research`
- Topics: `procedures`, `telemetry`, `interfaces`, `commanding`, `runtime`
- Types: `implementation-plan`, `refactor`, `ui`

---

## Glossary Quick Links

Add at the top of docs that reference multiple glossary terms:

```markdown
---
(frontmatter)
---

# Document Title

> **Glossary:** [Data Plane](../glossary/data-plane.md) | [Interface](../glossary/interface.md) | [COP-1](../glossary/cop-1.md)

## Overview
...
```

This helps readers quickly access definitions without hunting.

---

## Document Types

### Glossary Terms (`docs/glossary/`)

The glossary is the backbone. Check here FIRST when encountering domain terms.

```markdown
---
title: Target
aliases: [spacecraft, satellite]
tags: [glossary, core]
status: active
---

# Target

A **Target** is a spacecraft, ground system, or simulator that Cadence communicates with.

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Targets` | Context facade |
| `Cadence.Domain.Targets.Entities.Target` | Domain entity |

## Related Concepts

- [Interface](interface.md) - How we connect to targets
- [Mission](mission.md) - Operational context containing targets

## Common Confusion

> **Target vs Interface**: A target is the *logical* endpoint (the spacecraft). An interface is the *physical* connection (TCP socket).
```

### Architecture Decision Records (`docs/decisions/`)

ADRs capture WHY decisions were made. Check before modifying architecture.

```markdown
---
title: "ADR-001: No Database Calls in Data Plane"
tags: [adr, architecture, data-plane]
status: accepted
created: 2024-12-21
---

# ADR-001: No Database Calls in Data Plane

## Status
Accepted

## Context
What problem were we solving?

## Decision
What did we decide?

## Consequences
**Positive:** ...
**Negative:** ...

## Key Modules
- `Cadence.Runtime.Missions.MissionInstance`
```

### Implementation Plans (`docs/architecture/*-plan.md`)

For tracking implementation progress:

```markdown
---
title: Feature X Implementation Plan
tags: [architecture, implementation-plan, feature-x]
status: active
---

# Feature X Implementation Plan

> **Glossary:** [Relevant Term](../glossary/term.md)

## Goals
...

## Implementation Phases
- [ ] Phase 1: ...
- [ ] Phase 2: ...

## Key Modules
...
```

### Pattern Templates (`docs/patterns/`)

Show how to extend the codebase:

```markdown
---
title: Adding a New X
tags: [pattern, topic]
status: active
---

# Adding a New X

Follow this pattern when adding a new X.

## Steps

### 1. Create the Module
...

### 2. Register It
...

### 3. Add Tests
...

## Example
See PR #123 or `Cadence.Existing.Example`
```

---

## Map of Content (MOC) Files

Every directory needs an `_index.md`:

```markdown
---
title: Section Name
tags: [index, section]
status: active
---

# Section Name

Brief description of this section.

## Documents

| Document | Description |
|----------|-------------|
| [Doc One](doc-one.md) | Brief description |
| [Doc Two](doc-two.md) | Brief description |

## See Also

- [Related Section](../other/_index.md)
```

---

## Workflow

### When Asked to Document Something

1. **Search first**: `grep -r -l "CONCEPT" docs/`
2. **Check glossary**: Does this term need defining?
3. **Read related docs**: Understand current state
4. **Update or create**: Prefer updates
5. **Add links**: Both inline and in MOCs
6. **Update dates**: Set `updated:` in frontmatter

### Batch Frontmatter Updates

When migrating many docs, batch similar operations:

```bash
# Find docs without frontmatter
for f in $(find docs -name "*.md"); do
  if ! head -1 "$f" | grep -q "^---$"; then
    echo "$f"
  fi
done
```

Then edit in groups by directory/type.

---

## Anti-Patterns

### DON'T: Create Parallel Versions
```
docs/procedures.md           # Original
docs/procedures-v2.md        # NO - update the original
```

### DON'T: Create Monolithic Files
If a file exceeds ~300 lines, consider splitting. Large files waste context.

### DON'T: Create Orphan Docs
Every doc must be:
- Linked FROM at least one other doc
- Listed in a MOC (`_index.md`)

### DON'T: Use File Paths for Code
```markdown
# Bad
See `lib/cadence/interfaces/tcp_client_interface.ex`

# Good
See `Cadence.Interfaces.TcpClientInterface`
```

### DON'T: Duplicate Content
Link instead:
```markdown
For details, see [Existing Doc](../path/to/doc.md).
```

---

## LLM Navigation

### Entry Points

1. `docs/index.md` - Overview and quick links
2. `docs/glossary/_index.md` - Understand terminology first
3. `docs/decisions/_index.md` - Check before modifying architecture
4. `docs/patterns/_index.md` - Follow when extending codebase

### Context Loading Strategy

1. Start with the glossary index (small, gives vocabulary)
2. Load specific term files only as needed
3. Load MOC (`_index.md`) to find relevant docs
4. Load individual docs for deep dives

### Before Modifying Architecture

ALWAYS check `docs/decisions/` for relevant ADRs. This prevents undoing intentional decisions.

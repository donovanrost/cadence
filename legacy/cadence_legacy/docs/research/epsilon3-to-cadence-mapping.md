---
title: Epsilon3 to Cadence Feature Mapping
tags: [research, epsilon3, feature-mapping]
related:
  - "[[procedure]]"
  - "[[sequence]]"
created: 2025-01-01
updated: 2025-01-27
status: active
---

# Epsilon3 to Cadence Feature Mapping

> Analysis of how Epsilon3's procedure features map to Cadence's current implementation

## Executive Summary

Cadence has a **strong technical foundation** for procedures with DAG execution, approval workflows, and telemetry integration. However, Epsilon3's appeal lies primarily in its **user experience and collaborative features** rather than raw execution capability.

**Cadence Strengths:**
- Parallel DAG execution with dependency resolution
- Lua scripting for advanced procedures
- Telemetry integration and condition evaluation
- Approval workflow with audit trail
- Pause/resume with checkpointing

**Key Gaps (what makes Epsilon3 feel different):**
- Rich, block-based step editor (not JSON/code)
- Real-time collaborative execution UI
- Visual progress tracking with modern UX
- Redlines/suggested edits during runs
- Field inputs with inline validation
- Snippets and reusable blocks

---

## Detailed Feature Mapping

### 1. Procedure Structure

| Epsilon3 Feature | Cadence Status | Gap Analysis |
|-----------------|----------------|--------------|
| Steps with headers | Partial - steps have names/descriptions | Need richer metadata (notes, cautions, warnings) |
| Content blocks (text, tables, etc.) | Missing | Major gap - steps are code/config only |
| Field inputs (text, number, dropdown) | Partial - parameters exist | Parameters are at procedure level, not step level |
| Role-based signoffs per step | Missing | Steps execute automatically, no human signoff |
| Step dependencies | ✅ Complete | `depends_on` array in DAG |
| Conditional branching | Partial | `condition` field, but not pass/fail branching |
| Timing/duration metadata | Partial | `started_at`, `completed_at` tracked |

**Recommendation:** The biggest UX gap is that Cadence steps are **execution units**, while Epsilon3 steps are **rich documents with embedded execution**. Consider a hybrid model.

---

### 2. Step/Block Types

| Epsilon3 Block Type | Cadence Equivalent | Notes |
|--------------------|-------------------|-------|
| Text (rich markdown) | Missing | Steps have description only |
| Field Input (text) | `params.*` | At procedure level, not step level |
| Field Input (number) | `params.*` | Missing inline validation UI |
| Field Input (dropdown) | `params.*` with `enum` type | ✅ Exists |
| Field Input (checkbox) | `params.*` with `boolean` type | ✅ Exists |
| Tables | Missing | Could add as content block type |
| Telemetry display | Partial | Can read via `telemetry.*` but no display block |
| Commands | ✅ `command` step type | Works well |
| Attachments | Missing | No file attachment support |
| Sketches | Missing | Low priority for ops |
| Input References | Partial | `vars.*` but only within execution |
| Kitting/Inventory | Missing | Out of scope for C2 |

**Recommendation:** Add concept of **content blocks** that are display-only vs **execution blocks** that perform actions.

---

### 3. Execution Model

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Step-by-step manual execution | Missing | DAG runs automatically |
| Parallel execution | ✅ Complete | DAG executor handles this well |
| Pause/resume | ✅ Complete | Checkpoint-based |
| Skip step | Partial | Via conditions, not operator choice |
| Repeat step | Missing | Would need UI + execution support |
| Role-based step filtering | Missing | All steps visible to all users |
| Real-time progress sync | Partial | PubSub exists, UI needs work |

**Key Insight:** Epsilon3 procedures are **operator-paced** with optional automation. Cadence procedures are **automation-first** with optional pausing. This is a fundamental model difference.

**Recommendation:** Consider a new execution mode: `manual` vs `automatic` at procedure or step level.

---

### 4. Collaboration Features

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Multiple simultaneous operators | Missing | Single execution owner |
| @mentions | Missing | No in-app messaging |
| Real-time sync | Partial | PubSub broadcasts status |
| Comments on steps | Missing | Only execution logs |
| Redlines (suggested edits) | Missing | Major gap |
| Bluelines (approved changes) | Missing | Version control exists but no inline edits |
| Approval for suggested edits | Missing | Approval is version-level only |

**Recommendation:** Add **execution comments** and **step-level notes** as first step. Redlines are a larger architectural change.

---

### 5. Version Control & Approval

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Draft → Review → Approved | ✅ Complete | Well implemented |
| Multiple approvers | ✅ Complete | Configurable |
| Rejection with reason | ✅ Complete | `rejection_reason` field |
| Procedure diffs | Missing | Would be very valuable |
| Track changes UI | Missing | No visual diff |
| Persistent redlines | Missing | No inline edit suggestions |

**Recommendation:** Add **procedure diff view** comparing versions. This is high-value, moderate effort.

---

### 6. Variables & Parameters

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Procedure variables | ✅ Complete | `parameters_schema` + `parameters` |
| Text/number/checkbox types | ✅ Complete | Plus more (target, telemetry_item, etc.) |
| Variables in telemetry/commands | ✅ Complete | Template interpolation works |
| Variables passed to API | Partial | Used internally, not exposed |
| Step-level inputs | Missing | All inputs are procedure-level |

**Recommendation:** Cadence's parameter system is actually more powerful. The gap is **UI for collecting inputs during execution** (step-level prompts).

---

### 7. Snippets & Reusability

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Save step as snippet | Missing | No snippet library |
| Save section as snippet | Missing | No sections concept |
| Insert snippet into procedure | Missing | Would need snippet schema |
| Snippet library in settings | Missing | Could be org-level |

**Recommendation:** Implement **procedure templates** as a lighter-weight alternative. Full snippets require block-based editing.

---

### 8. Linked/Child Procedures

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Launch child procedure from step | Missing | No nested execution |
| Parent/child visibility | Missing | Executions are independent |
| Block parent until child completes | Missing | Would need execution linking |

**Recommendation:** Add a `call_procedure` step type that spawns child execution and optionally waits.

---

### 9. Telemetry Integration

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Live telemetry in steps | ✅ Complete | `telemetry.*` access |
| 1-second refresh | ✅ Complete | CVT is real-time |
| Stale indicator | Missing | CVT has timestamps, UI doesn't show staleness |
| Math expressions | Partial | Basic comparisons, not full Math.js |
| Range validation | ✅ Complete | `>=`, `<=`, etc. in conditions |
| Telemetry-based conditionals | ✅ Complete | `wait_for` step type |
| COSMOS integration | N/A | Cadence is the C2 system |

**Recommendation:** Cadence's telemetry integration is strong. Add **telemetry display blocks** for human-readable presentation.

---

### 10. Offline Capabilities

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| View procedures offline | Missing | Web-only |
| Sign off steps offline | Missing | No offline mode |
| Auto-sync on reconnect | Missing | Would need service worker |

**Recommendation:** Low priority for constellation ops (always connected). Could use PWA for basic offline viewing.

---

### 11. Shift Logs & Handover

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Shift logs | Missing | No shift concept |
| Event linking | Partial | Recordings exist |
| @mentions | Missing | No messaging |
| Handover workflow | Missing | No shift management |

**Recommendation:** This is a separate feature domain. Consider as future module, not part of procedures.

---

### 12. AI Features

| Epsilon3 Feature | Cadence Status | Notes |
|-----------------|----------------|-------|
| Procedure generation | Missing | Could add with LLM |
| Document transformation | Missing | Low priority |
| Anomaly detection | Missing | Could leverage telemetry data |
| Natural language queries | Missing | Future consideration |

**Recommendation:** AI generation could be valuable for large constellations. Defer until core UX is solid.

---

## Prioritized Recommendations

### Phase 1: Core UX Improvements (High Impact, Achievable)

1. **Rich Step Editor**
   - Add content blocks: text, note, caution, warning
   - Display-only vs execution blocks
   - Markdown support in descriptions

2. **Execution UI Overhaul**
   - Visual step progress (green/gray/blue borders like Epsilon3)
   - Real-time status updates
   - Expandable step details

3. **Step-Level Manual Control**
   - Add `manual: true` step option requiring operator signoff
   - "Execute" button per step
   - Skip/repeat controls

4. **Procedure Diff View**
   - Compare versions side-by-side
   - Highlight added/removed/changed steps

### Phase 2: Collaboration Features (Medium Effort)

5. **Execution Comments**
   - Comments on running/completed executions
   - Step-level notes
   - Timestamp and user attribution

6. **Suggested Edits (Redlines)**
   - During execution, suggest changes to steps
   - Review queue for procedure owners
   - Auto-include in next draft

7. **Role-Based Step Signoffs**
   - Require specific role to complete step
   - AND/OR logic for multiple roles
   - Strict mode blocking progression

### Phase 3: Advanced Features (Higher Effort)

8. **Nested Procedures**
   - `call_procedure` step type
   - Child execution tracking
   - Optional blocking

9. **Snippets/Templates**
   - Reusable step groups
   - Organization-level library
   - Insert into any procedure

10. **Step-Level Field Inputs**
    - Collect data during execution (not just at start)
    - Input validation and pass/fail criteria
    - Reference inputs in later steps

---

## Architectural Considerations

### Current Cadence Model
```
Procedure (definition)
  └── Version (immutable snapshot)
        └── source: %{steps: %{...}}  # JSON blob
              └── Execution (runtime)
                    └── step_results: %{...}  # JSON blob
```

### Suggested Evolution
```
Procedure (definition)
  └── Version (immutable snapshot)
        └── Sections (ordered)
              └── Steps (ordered within section)
                    └── Blocks (content/execution)
                          └── Field Inputs (data collection)
        └── Execution (runtime)
              └── StepRun (per step instance)
                    └── BlockResult (per block)
                    └── FieldInputValue (collected data)
                    └── Comments
                    └── Signoffs
```

This normalized model enables:
- Richer step editing UI
- Step-level state tracking
- Field input collection during execution
- Comments and signoffs per step
- Proper diff generation between versions

### Migration Path
1. Keep current JSON-blob model working
2. Add new normalized tables alongside
3. Build new UI against normalized model
4. Migrate existing procedures lazily or via script
5. Deprecate JSON-blob approach

---

## Summary

Cadence has **excellent execution infrastructure** (DAG, parallel, pause/resume, telemetry). The gap is primarily **user experience**:

| Aspect | Cadence | Epsilon3 |
|--------|---------|----------|
| Execution engine | Strong | Similar |
| Step authoring | JSON/code | Rich blocks |
| Runtime UX | Basic | Polished |
| Collaboration | Minimal | Extensive |
| Version control | Good | Better diffs |

**The goal isn't to copy Epsilon3** - it's to bring Cadence's powerful execution model into a user experience that operators love. Focus on:

1. **Visual step editing** (blocks, not JSON)
2. **Operator-paced execution** (manual signoffs)
3. **Real-time collaboration** (comments, redlines)
4. **Progress visibility** (modern execution UI)

These changes would make Cadence competitive with Epsilon3 while retaining its technical advantages (Lua scripting, parallel DAG, deep telemetry integration).

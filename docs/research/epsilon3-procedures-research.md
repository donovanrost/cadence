# Epsilon3 Procedures - Deep Research Summary

> Research conducted December 2025 to inform Cadence procedures redesign

## Overview

Epsilon3 is purpose-built procedure execution software founded in 2021 by engineers from SpaceX, Google, and Stanford. It's used by NASA, Blue Origin, Axiom, Sierra Space, Firefly Aerospace, and other major aerospace organizations.

---

## Core Procedure Architecture

### Step Structure
Each step contains:
- **Headers** - formatted content blocks with rich text
- **Content blocks** - text, alerts, inputs, telemetry, commands, tables
- **Signoffs** - role-based operator requirements with AND/OR logic
- **Dependencies** - prerequisite steps that must complete first
- **Conditionals** - branching logic based on pass/fail outcomes
- **Timing/duration metadata**

### Content Block Types
| Block Type | Description |
|------------|-------------|
| **Text** | Rich text with markdown, bulleted/numbered lists, code blocks |
| **Field Inputs** | Text, number, checkbox, dropdown with pass/fail criteria |
| **Tables** | CSV import support, up to 10 columns, dropdown cells |
| **Telemetry** | Live telemetry with 1-second refresh, range checks, Math.js expressions |
| **Commands** | Typed arguments (float, int, string, enum, file), two-step confirmation |
| **Attachments** | Files, images, sketches (handwritten drawings) |
| **Input References** | Display values from other steps anywhere in procedure |
| **Kitting/Inventory** | Part tracking, check-in/out, usage blocks |

---

## Key UI/UX Features

### Visual Cues During Execution
- **Green border** - step complete
- **Gray background** - step skipped
- **Blue border** - step incomplete
- **Left borders** on comments and redlines for visibility
- **Progress bars** per section
- **Real-time table of contents** showing status

### Editor Views
- **Linear view** - traditional step-by-step list
- **Flowchart view** - visualize conditional branching logic
- Switch between views while editing

### Version Control & Diffs
- Dedicated versions panel showing all revisions
- **Procedure Diffs** - see added/modified/removed variables, headers, sections, steps
- Navigation arrows between changes
- Track changes with redlines preserved across versions

---

## Procedure Execution Features

### Conditional Logic & Dependencies
- **Step conditionals** - branch based on pass/fail outcomes
- **Step dependencies** - AND/OR logic for prerequisite completion
- **If/then branching** on field inputs and telemetry values
- System enforces execution order based on combined conditionals + dependencies

### Role-Based Sign-offs
- Assign specific roles required to sign off each step
- Multiple roles with AND/OR logic (e.g., "Mission Commander AND Quality")
- **Strict Signoff Mode** - blocks completion until:
  - All field inputs finished
  - Number fields pass validation rules
  - Linked procedures completed

### Real-Time Collaboration
- Multiple operators work simultaneously
- @mentions for notifications
- Live sync across all participants
- Role-based filtering (see only your steps)

### Redlines & Bluelines (Suggested Edits)
- Suggest edits during live procedure runs
- Add new steps on-the-fly
- **Persistent redlines** - appear in draft immediately after run ends
- Approval workflow for suggested edits
- Permission controls on who can suggest edits
- End procedure permissions (e.g., only Mission Commander can finalize)

---

## Procedure Variables

Define configuration variables that change per run without editing the procedure:
- **Types**: text, number, checkbox
- Use case: run same procedure for different vehicles/test stands
- Variables available to telemetry/commanding integrations
- Passed to external API calls

---

## Snippets (Reusable Blocks)

- Save common steps as reusable snippets
- Save entire sections as snippets
- Library in workspace Settings
- Insert into any procedure
- Deleting snippet converts to normal steps

---

## Linked/Parent-Child Procedures

- Launch child procedures from parent
- Parent/child relationships visible on dashboard
- Linked procedure status visible at a glance
- Strict signoff can block parent until children complete

---

## Batch Steps

New feature for repeated execution:
- Designate steps for multiple iterations in single run
- Specify repetition count at runtime
- Each iteration as separate tab
- Supports conditionals, dependencies, references between iterations

---

## Offline Capabilities

- View procedures offline
- Sign off steps
- Skip and repeat steps
- Add comments
- Suggest edits offline
- Auto-sync when connection restored
- Per-procedure offline mode enablement

---

## Telemetry Integration

- **COSMOS v4** - Docker middleware container proxies requests
- **Yamcs** - Native plugin syncs parameters
- 1-second refresh rate (configurable)
- Stale telemetry visual indicator
- Math.js expressions for calculations
- Range check validation (e.g., `5 < telemetry < 10`)
- Telemetry-based step conditionals

---

## AI Features

| Feature | Description |
|---------|-------------|
| **Procedure Generation** | Create from natural language prompts (e.g., "Create a 20-step procedure to test a rocket propulsion system") |
| **Document Transformation** | Convert PDFs, spreadsheets, docs into role-based workflows |
| **Anomaly Detection** | Identify unusual patterns in operational data |
| **Insights & Summaries** | AI-generated performance analysis |
| **Natural Language Queries** (coming) | Ask questions like "Are there NCRs with our latest solar array builds?" |

Security: Uses AWS GovCloud LLMs, opt-in policy, data never used for training.

---

## Planning & Scheduling (Operations)

- **Interactive Gantt view** with filtering/editing
- **Event dependencies** - intuitive builder for complex relationships
- **Sub-events/milestones** - trees of interconnected operations
- Queue procedures with deadlines
- Recurring task management
- Real-time deviation monitoring
- Calendar integrations

---

## Shift Logs & Handovers

- Log critical events in real-time
- Rich text editor for entries
- Link to runs, procedures, issues
- @mention notifications
- Role-based access
- Searchable/filterable history
- Seamless shift transitions

---

## Test Management

- Reusable test cases with flexible plans
- Test conditions matrices (X/Y axes)
- Requirements linkage and gap analysis
- Results comparison across runs
- End-to-end traceability
- ISO QMS compliance
- Risk assessment matrices

---

## API & Integrations

- REST API with JSON payloads
- Start/pause/resume/end procedures via API
- External triggers from CI/CD, anomaly detection, etc.
- Real-time SocketIO for commands/telemetry
- External data dictionaries
- Integrations: Jira, PLM, ERP, Duro (hardware), COSMOS, Yamcs

---

## Key Differentiators from Traditional Procedures

1. **Live collaborative execution** - not static documents
2. **Real-time telemetry integration** - auto-evaluate pass/fail
3. **Conditional branching** - decision trees within procedures
4. **Suggested edits during runs** - redlines without changing released version
5. **Version control built-in** - diffs, approval workflows
6. **Offline-first** - works in remote test sites
7. **AI-powered generation** - 10x faster procedure creation
8. **Role-based everything** - signoffs, permissions, filtering

---

## Sources

- [Epsilon3 Main Site](https://www.epsilon3.io)
- [Execute: Procedure Management](https://www.epsilon3.io/execute-electronic-procedures)
- [Products Overview](https://www.epsilon3.io/products)
- [AI Features](https://www.epsilon3.io/artificial-intelligence)
- [Plan: Scheduling](https://www.epsilon3.io/plan-schedule-timeline-track-dependencies)
- [Shift Logs](https://www.epsilon3.io/shift-logs-critical-operations-events-handover)
- [Test Management](https://www.epsilon3.io/test-management)
- [API Documentation](https://docs.epsilon3.io/)
- [Changelog #27: Step Conditionals](https://www.epsilon3.io/behind-the-console/epsilon3-changelog27-step-conditionals-offline-suggested-edits)
- [Changelog #50: COSMOS/Yamcs Integration](https://www.epsilon3.io/behind-the-console/epsilon3-changelog50-insight-into-anomalies-multiple-review-types-sketch-field-input-cosmos-and-yamcs)
- [Changelog #75: AI Procedure Generation](https://www.epsilon3.io/behind-the-console/changelog-75-ai-procedure-generation-batch-steps)
- [Satsearch: Spacecraft Builds 2025](https://blog.satsearch.co/2025-05-20-spacecraft-builds-and-missionops-a-2025-perspective-with-epsilon3)
- [SourceForge Article](https://sourceforge.net/articles/epsilon3-a-new-breed-of-process-resource-management-software/)

# Cadence design-system charter

## Status

Product principles for the production design system. This document defines
the design system's purpose and operational principles. It does not select a
visual style or establish a finished component catalog. The production baseline
and package ownership are defined in [architecture](architecture.md).

## Purpose

The Cadence design system exists to help an operator understand the system,
make a sound decision, and act with confidence. It is a product language, a set
of interaction rules, an implementation toolkit, and a feedback loop. A shared
component library is one output of the system, not the system itself.

Cadence should express **calm precision**: dense enough for continuous
operations, quiet enough for sustained attention, and explicit enough that an
operator can trust every state and action. It should feel like a modern
operational instrument, not generic enterprise software or decorative
mission-control theater.

The north-star test is:

> Can an operator glance at a complex screen, understand its condition,
> identify uncertainty, inspect the supporting evidence, and take the correct
> action without fighting the interface or mistrusting what it shows?

## Source material and scope

[Astro UXDS](https://www.astrouxds.com/) is an important research input because
it was developed with space-operations users and treats foundations,
components, interaction patterns, compliance, case studies, and releases as
parts of one living system. Cadence is not adopting Astro's styling, tokens,
component code, or compliance regime.

The durable idea distilled from Astro is **attention management under
operational risk**:

> Context, state, time, consequence, and evidence must remain consistently
> understandable during continuous operations.

That idea informs this charter. Cadence will validate and evolve it against its
own users, workflows, technical constraints, and product boundaries.

## Principles

### 1. Context is persistent

Context that changes the meaning or consequence of an action must not disappear
as the user navigates or scrolls. Depending on the workflow, persistent context
may include:

- organization and mission;
- target, spacecraft, or other operational scope;
- live, archive, simulation, exercise, or development mode;
- selected time range and time reference;
- connection, ingestion, and synchronization condition;
- authenticated identity and current authority; and
- a pending or active consequential operation.

The presentation does not need to resemble Astro's Global Status Bar. The
invariant is that an operator cannot reasonably mistake the environment, scope,
time mode, or authority under which an action will occur.

### 2. Attention is scarce

Color, motion, banners, sound, elevation, and interruption consume attention.
Cadence will spend them deliberately.

- Reserve the strongest signals for conditions that require timely action.
- Do not use alarm colors decoratively.
- Do not animate steady-state information.
- Do not let routine success feedback compete with operational exceptions.
- Make the normal state calm enough that a meaningful change is obvious.
- Match presentation intensity to urgency and required response.

Repeated or indiscriminate urgency trains users to ignore the interface. The
system must protect the meaning of its strongest signals.

### 3. State has precise semantics

Cadence will not compress unrelated concepts into one generic status ladder.
The design system will define separate semantic dimensions for at least:

| Dimension    | Example states                                    |
| ------------ | ------------------------------------------------- |
| Health       | nominal, degraded, failed                         |
| Availability | online, standby, offline                          |
| Data quality | valid, suspect, invalid, unknown                  |
| Freshness    | live, delayed, stale                              |
| Workflow     | pending, approved, executing, completed, rejected |
| Urgency      | informational, attention, immediate               |
| Authority    | permitted, approval required, prohibited          |

These vocabularies will be finite, documented, and mapped to domain contracts.
A state will never depend on color alone: text, iconography or shape, and
accessible semantics must preserve its meaning.

An aggregate may surface the condition that most demands attention, but it must
also provide a path to the underlying states and evidence. Aggregation must not
erase uncertainty.

### 4. Time is part of the evidence

Time is a first-class interaction primitive throughout Cadence, not a formatting
detail owned by charts. Shared behavior must distinguish:

- now from the user's selected time;
- live data from archived data;
- mission time from wall-clock time;
- planned, predicted, and realized intervals;
- event time from receipt, processing, and presentation time;
- data freshness and transport latency;
- comparison windows; and
- the provenance of time-derived facts.

Time zones, precision, range boundaries, and freshness must be explicit wherever
ambiguity could change an interpretation or action.

### 5. Live updates never steal the user's place

The system may update underneath an operator, but it may not interrupt an
investigation or silently change the object being inspected.

- Follow new events while the user is following now.
- Preserve the viewport when the user moves into history.
- Keep selections, expanded rows, inspectors, and comparisons stable across
  refreshes whenever the underlying object still exists.
- Make return-to-live an explicit, visible action after the user leaves the live
  edge.
- Never discard an in-progress input because background data changed.

This principle applies to logs, timelines, charts, tables, trees, tooltips, and
detail inspectors.

### 6. Interruption scales with consequence

Feedback patterns are chosen by locality, urgency, traceability, and whether a
response is required:

| Surface                   | Use                                                                |
| ------------------------- | ------------------------------------------------------------------ |
| Inline feedback           | Local validation or the result of a nearby action                  |
| Toast                     | Brief, non-critical confirmation that does not need later evidence |
| Activity or log entry     | Traceable events available for later inspection                    |
| Badge or attention center | Asynchronous follow-up without immediate interruption              |
| Contextual banner         | An important condition affecting the current workflow              |
| Modal                     | A decision that must be resolved before continuing safely          |

Anything that affects operational history cannot exist only as transient
feedback. Banners and modals are escalation mechanisms, not default containers.

### 7. Preserve context during inspection and preparation

Prefer modeless interaction when the user benefits from seeing the surrounding
system while inspecting or preparing a change. Suitable forms include inline
expansion, inspectors, drawers, and split panes.

- Selecting telemetry should not cover the chart that gave it meaning.
- Inspecting an event should preserve its place in the timeline.
- Preparing a command should show parameters, validation, authority, expected
  effect, and relevant evidence together.
- Preparation and commitment must be separate for consequential actions.
- A modal is appropriate when continuing elsewhere would be unsafe, not merely
  because an interaction is temporary.

### 8. Evidence is reachable from every conclusion

Operational summaries should reduce cognitive load without becoming dead ends.
A user must be able to move from an aggregate status, alert, chart mark, or
workflow result to the facts that produced it.

Evidence paths should preserve scope and time context. They should identify
source, freshness, quality, assumptions, lineage, and relevant audit history
without forcing every detail into the primary display.

### 9. Operational patterns are the heart of the system

Buttons, fields, and dialogs are necessary foundations. The differentiating
layer is the set of Cadence patterns that compose them:

- telemetry values with units, limits, quality, and freshness;
- live and archive time navigation;
- command preparation, approval, release, and execution;
- contact and event annotations;
- mission timelines and activity logs;
- provenance and evidence trails;
- alert triage and recovery;
- consequential actions; and
- workflow handoffs between monitoring, investigation, and management.

Patterns must preserve product ownership. A dashboard may expose a problem and
launch the owning workflow without duplicating that workflow's state and
behavior.

### 10. The design system is a governed product

Every public artifact needs an owner, intended use, accessibility contract,
stability level, verification evidence, and release history. The system should
make the correct implementation easy and misuse difficult.

Documentation for a component or pattern should include, as applicable:

- purpose and user outcome;
- usage and non-usage guidance;
- anatomy and composition;
- states and state transitions;
- behavior, including keyboard and live-update behavior;
- accessibility requirements;
- content and terminology guidance;
- representative operational examples;
- edge, empty, loading, partial, failure, and unauthorized states;
- implementation API;
- test expectations; and
- maturity and release status.

## Design-system layers

The frontend design system will develop through distinct layers:

1. **Experience principles** define what must remain true for the operator.
2. **Semantic models** define shared state, time, feedback, action, and evidence
   vocabularies.
3. **Foundations** define themeable typography, spacing, color roles, motion,
   layering, density, and accessibility constraints.
4. **Primitives** provide small, composable Vue components with strong defaults.
5. **Operational patterns** combine primitives into repeatable domain behavior.
6. **Reference experiences** test the system in realistic, high-pressure flows.
7. **Governance and tooling** keep design assets, Vue APIs, documentation,
   accessibility, tests, and releases coherent.

Storybook is the implementation workshop and executable reference for tokens
and components. It does not replace written principles, domain semantics, or
workflow guidance.

## Specifications

- [Operational state model](operational-state-model.md) defines the shared state
  axes, aggregation and presentation rules, current contract mappings, and the
  live-monitoring scenario matrix.
- [Symbology](symbology.md) defines icon classes, invariant status shapes,
  state-to-symbol policy, monitoring-symbol anatomy, accessibility, and the
  starter mission glyph vocabulary.
- [Visual foundations](visual-foundations.md) defines the production baseline,
  semantic tokens, typography, geometry, motion, and accessible theme evolution.

## Explicit non-goals

This charter does not authorize or prescribe:

- Astro's visual style, typography, palettes, spacing, component geometry, icon
  artwork, or icon implementation packages;
- Astro Web Components or its framework architecture;
- a dark-theme-first product;
- one linear severity scale for all state;
- a literal global status bar;
- a particular charting library;
- a large generic component catalog built ahead of demonstrated need;
- military compliance requirements as a substitute for Cadence research; or
- the existing experimental files in `packages/design-tokens` as the new visual
  source of truth.

## Initial reference experiences

The system should be pressure-tested with complete experiences before its visual
language or component catalog is considered stable:

1. **Live monitoring:** understand mission condition, data quality, freshness,
   and anomalies while new data arrives.
2. **Investigation:** leave the live edge, compare evidence across time, inspect
   provenance, and return to live without losing context.
3. **Consequential action:** prepare, validate, authorize, approve, execute, and
   audit an action with clear commitment boundaries.

These reference experiences should drive the first semantic models and
operational patterns. Components are promoted into the shared UI package only
when their contracts are understood and reuse is demonstrated.

## Astro references

- [Getting Started](https://www.astrouxds.com/getting-started/)
- [Research](https://www.astrouxds.com/resources/research/)
- [UI Design](https://www.astrouxds.com/resources/ui-design/)
- [Status System](https://www.astrouxds.com/patterns/status-system/)
- [Application State](https://www.astrouxds.com/components/application-state/)
- [Global Status Bar](https://www.astrouxds.com/components/global-status-bar/)
- [Notifications](https://www.astrouxds.com/patterns/notifications/)
- [Modeless Panes](https://www.astrouxds.com/patterns/modeless-panes/)
- [Log](https://www.astrouxds.com/components/log/)
- [Timeline](https://www.astrouxds.com/components/timeline/)
- [Data Visualization](https://www.astrouxds.com/patterns/data-visualization/)
- [Releases](https://www.astrouxds.com/releases/)

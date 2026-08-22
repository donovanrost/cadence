# Design: Application APID Selection

- Status: draft
- Created: 2026-04-23
- Scope: explicit per-application APID ownership for spacecraft-scoped catalog-backed application configuration
- Related ADRs: [001](../../decisions/001-mission-scoped-runtime-and-selector-model.md), [008](../../decisions/008-multi-format-catalog-import-architecture.md), [009](../../decisions/009-canonical-telemetry-catalog-model.md)
- Related specs: [2026-04-20 Packet Model and Application Binding](./2026-04-20-packet-model-and-application-binding-design.md), [2026-04-20 Catalog Database and Revision Library](./2026-04-20-catalog-database-revision-library-design.md)

## Summary

Cadence now has the beginnings of an application-oriented configuration model.
That is the right direction, but "application + catalog revision" is still too
implicit once more than one application can consume packetized mission data.

The next built-in application after Telemetry Decom is expected to be Event
Reporting. Event report packets are real mission packets described by the same
catalog, but they are not operator telemetry and should not be handled by
Telemetry Decom. If Cadence only asks users to choose a catalog revision for an
application, the system behavior remains ambiguous:

- does the application receive the whole revision?
- only definitions it knows how to compile?
- only packets of a certain family?
- how do multiple applications divide ownership?

This design makes packet routing explicit:

> Application configuration must explicitly declare the APIDs it handles for a
> spacecraft.

For the first version, APID selection is the primary routing primitive. Packet
groups, classes, and richer semantic selection are deferred.

## Problem

The current shape is acceptable for a single built-in consumer, but it becomes
unclear as soon as multiple applications exist.

Concrete examples:

- Telemetry Decom should handle engineering telemetry APIDs.
- Event Reporting should handle event-report APIDs.
- A future payload application may handle payload APIDs that are valid packet
  definitions but not telemetry in the built-in sense.

Without explicit assignment, Cadence has to infer routing from implementation
details:

- compiler support
- application capability assumptions
- implicit "whole catalog revision" semantics

That creates several problems:

1. Users cannot easily tell which packets an application owns.
2. Multiple applications using the same catalog revision become ambiguous.
3. Unsupported definitions can be misread as "unused" rather than "not claimed
   by this application."
4. The UI cannot clearly explain why a packet did or did not flow to a given
   application.
5. Future validation such as overlap detection and unassigned-packet warnings
   has no explicit configuration basis.

## Goals

- Make application packet ownership explicit and operator-visible.
- Keep application configuration spacecraft-scoped.
- Keep catalog revisions as the source library for packet definitions.
- Use APIDs as the first explicit selection primitive.
- Allow multiple applications to consume different parts of the same catalog
  revision for the same spacecraft.
- Enable first-class validation of overlap, missing APIDs, and unsupported
  selections.
- Keep the first version simple enough to support early built-in applications
  without requiring users to author packet taxonomy metadata.

## Non-goals

- Designing packet groups or packet classes as the primary first-pass routing
  primitive.
- Requiring users to annotate catalogs with application categories.
- Designing the full transport/contact/connection UI.
- Designing access-control policy around packet groups or APID visibility.
- Designing plugin packaging or arbitrary custom application execution.
- Solving every future packet-selection mode in this document.

## Design Rule

Cadence should adopt the following rule:

> Application configuration must explicitly declare the APIDs it handles for a
> spacecraft.

That means a first-pass application configuration has these user-facing parts:

- spacecraft
- application
- catalog revision
- handled APIDs
- enabled or disabled state

Example:

```text
Telemetry Decom
- spacecraft: SC-1
- catalog revision: Bus Rev 4
- handled APIDs: 1, 2, 3, 10
- enabled: true

Event Reporting
- spacecraft: SC-1
- catalog revision: Bus Rev 4
- handled APIDs: 77
- enabled: true
```

## Why APIDs First

APIDs are the right first-step routing primitive because they are:

- already present in the catalog model
- already familiar to operators and mission engineers
- low ceremony compared with packet groups/classes
- sufficient to disambiguate initial built-in application ownership
- easy to validate for overlap and omission

Packet groups/classes may become valuable later, especially for:

- large long-lived missions
- reusable organizational taxonomy
- access-control stories
- dashboard filtering and reporting

But they require additional user-authored structure and should not be the
foundation for the first explicit routing model.

## Core Model

Cadence should treat the catalog revision as the packet-definition library and
the application configuration as the ownership claim over a subset of that
library.

Conceptually:

```text
Catalog Revision
  -> Packet Definitions
     -> APID ownership claimed by applications
        -> runtime routing and application dispatch
```

This keeps the responsibilities clear:

- catalog revision answers "what packet definitions exist?"
- application config answers "which APIDs does this application handle?"
- runtime answers "where should incoming packets be routed?"

## Proposed Behavior

When an application configuration is saved:

1. Cadence records the spacecraft, application, catalog revision, and selected
   APIDs.
2. Cadence compiles the chosen catalog revision for that application.
3. Cadence materializes runtime rules only for the selected APIDs.
4. Incoming packets for that spacecraft are routed to the application only when
   their APIDs match the application's configured selection.

Important nuance:

- selecting an APID means the application claims packets with that APID
- it does not guarantee the application can fully interpret every definition
  under that APID
- unsupported compiled content should surface as diagnostics on that
  application's config, not as silent drop or implicit rerouting

## Telemetry Decom

For Telemetry Decom, explicit APID selection means:

- the selected catalog revision is used as the packet-definition source
- only the configured APIDs are compiled into the Telemetry Decom application
  binding
- unsupported telemetry-specific content within those APIDs remains diagnostic
  information for Telemetry Decom
- unselected APIDs are not routed to Telemetry Decom

This is clearer than "Telemetry Decom receives the whole supported revision."

## Event Reporting

Event Reporting is the clearest motivating example.

A mission may extend the catalog with an APID carrying event report packets.
Those packets are valid packet definitions and may be perfectly representable in
the generic packet model, but they are not part of Telemetry Decom's ownership.

Under this design:

- Telemetry Decom does not claim the event-report APID unless explicitly
  selected
- Event Reporting claims the event-report APID explicitly
- the UI can show this ownership directly

That gives operators a much clearer explanation of system behavior.

## Validation

Explicit APID ownership enables first-class validation rules.

Cadence should support, at minimum:

### Hard validation

- reject APID overlap for the same spacecraft when two enabled application
  configs claim the same APID and overlap is not explicitly allowed
- reject APIDs that do not exist in the selected catalog revision

### Warnings

- warn when catalog APIDs are left unassigned
- warn when selected APIDs compile into definitions the target application
  cannot fully consume
- warn when a catalog revision changes the meaning or structure of an APID
  already assigned to an application

The exact hard-vs-warning boundary can evolve, but overlap detection should be a
first-class design constraint.

## UI Shape

The user-facing model should remain application-centered and simple.

A first-pass application page should be shaped like:

1. application name
2. status
3. catalog revision selector
4. handled APIDs
5. preview
6. apply changes

Example for Telemetry Decom:

```text
Telemetry Decom
- Catalog Revision: Bus Rev 4
- Handled APIDs: 1, 2, 3, 10
- Preview:
  - selected APIDs
  - compiled packet count
  - diagnostics
- Apply Mission Changes
```

The UI should not force users to think in terms of:

- runtime binding sets
- materialization internals
- transport connections
- source endpoint mechanics

Those remain implementation details behind the application config.

## Future Evolution

This design intentionally leaves room for richer selection later.

Possible later additions:

- packet groups
- packet classes
- saved APID sets
- semantic packet tags
- access-control integration such as "user can view payload APIDs"

But those should be layered on top of explicit APID ownership, not used to
avoid defining the initial routing contract.

## Suggested First Implementation Slice

For the next iteration of built-in application UX and backend behavior:

1. extend application config to store handled APIDs
2. update Telemetry Decom materialization to bind only selected APIDs
3. add overlap validation across enabled application configs per spacecraft
4. build Event Reporting on the same model
5. defer packet groups/classes until real pressure exists

## Open Questions

- Should APID selection be free-form entry, multi-select from the catalog, or
  both?
- Should overlap be always forbidden, or should Cadence later allow explicit
  shared ownership for special cases?
- Should warnings for unassigned APIDs appear on each application page, on a
  spacecraft "application coverage" page, or both?
- Should command-oriented applications eventually use the same selection model,
  or should command routing remain separate from packet/APID ownership?

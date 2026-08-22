---
title: "ADR-002: Organization, Mission, and Identity Scope Model"
aliases: [multi org model, tenant scope model, organization scope model]
tags: [adr, architecture, tenancy, authorization, identity, mission]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-002: Organization, Mission, and Identity Scope Model

## Status

Accepted

## Context

Cadence must support multiple organizations while allowing individual users to
participate in more than one organization.

The tenant model therefore cannot assume:

- one deployment per organization
- one user account per organization
- one mission namespace shared across all organizations

Cadence also needs a scope model that aligns with the runtime model from
[ADR-001](001-mission-scoped-runtime-and-selector-model.md):

- the runtime root is `mission`
- semantic interpretation is mission-scoped
- selectors and activations must not cross mission boundaries

At the same time, authorization and operational isolation require a harder
boundary above mission.

The intended direction is a multi-organization shared-schema strategy similar in
shape to the Phoenix shared-schema organization-membership model described in
the ZenHive multi-organization authorization guide:

- one global user table
- one organization table
- a membership join table connecting users to organizations
- organization-scoped roles and authorization

Reference:

- <https://github.com/ZenHive/OrgsDocs/blob/main/multi_org/authorization_strategy.md>

We also need to decide whether spacecraft are mission-owned or organization-
owned, and whether service identities exist only at one scope or at multiple
scopes.

## Decision

Cadence will use an organization-owned mission model with global user
identities, organization memberships, mission-owned spacecraft, and both
organization-scoped and mission-scoped service identities.

### 1. Organization Is The Tenant Boundary

Cadence will treat `organization` as the top-level tenant boundary.

Organizations own:

- missions
- organization-scoped service identities
- organization membership and authorization state
- organization-level provider integrations and credentials where applicable
- organization-level quotas, audit scope, and policy scope

No runtime configuration, mission state, or operational data crosses
organization boundaries by default.

### 2. Users Are Global Identities

Users are global Cadence identities, not organization-local records.

A user may belong to multiple organizations simultaneously.

User participation in an organization is represented through an
`organization_membership` record that carries organization-scoped role and
authorization context.

This allows one user to hold different roles in different organizations.

### 3. Authorization Is Organization-Scoped First

Authorization decisions must always be evaluated in organization context.

At minimum, authorization must consider:

- authenticated actor identity
- organization scope
- membership or service identity scope
- requested action
- resource scope

Mission-scoped authorization is subordinate to organization-scoped
authorization, not a replacement for it.

### 4. Mission Belongs To One Organization

Each mission belongs to exactly one organization.

Mission is:

- the root runtime scope
- the semantic namespace for protocol and application meaning
- the boundary for selectors, activations, replay bases, and managed runtime
  instances

`mission.slug` is unique within an organization, not globally across Cadence.

This means route and API identity should assume organization context plus
mission-local identity, rather than depending on globally unique mission names.

### 5. Spacecraft Are Mission-Owned

`spacecraft` is a mission-owned object.

Cadence will not model spacecraft as first-class organization-wide assets in
release one.

This means:

- spacecraft belong to one mission
- spacecraft identity does not implicitly carry across missions
- creating a corresponding spacecraft in another mission is allowed and expected
  to be straightforward

This keeps the release-one model aligned with mission-scoped runtime behavior
and avoids introducing cross-mission coupling too early.

### 6. Source Endpoints Are Mission-Owned And Distinct From Spacecraft

`source_endpoint` is a mission-owned routing identity.

It remains distinct from `spacecraft` even when a mission chooses a one-to-one
mapping between them.

This preserves room for:

- relay topologies
- provider-specific source resolution
- future non-spacecraft semantic sources

### 7. Contact, Link, And Transport Scopes Are Mission-Owned

Contacts, links, transport sessions, and related operational scopes belong to a
mission.

They do not cross organization boundaries and they do not redefine the mission
semantic namespace.

### 8. Service Identities Exist At Two Scopes

Cadence supports both:

- organization-scoped service identities
- mission-scoped service identities

Organization-scoped service identities are appropriate for:

- provider integrations
- inbound webhooks
- organization-wide automation or administrative tooling
- organization-level config pipelines

Mission-scoped service identities are appropriate for:

- mission automation
- replay and simulation actors
- mission-local adapters
- procedure execution and verification actors

Service identities must never inherit unrestricted human privileges by
convenience.

### 9. Required Keys On Mission-Owned Records

Mission-owned records must carry both:

- `organization_id`
- `mission_id`

This applies to canonical mission-domain records and projections unless the
record is explicitly global or organization-scoped.

Mission-local IDs alone are not sufficient for authorization or safe data
partitioning in a shared-schema multi-organization deployment.

### 10. Deferred Cross-Mission Spacecraft Lineage

Cadence will not make cross-mission spacecraft lineage a first-class release-one
concept.

If later needed, Cadence may add an optional organization-scoped lineage or
fleet-asset reference for correlating mission-owned spacecraft records that
represent the same real-world vehicle across lifecycle phases.

That concern is explicitly deferred rather than solved prematurely now.

## Consequences

### Positive

- The tenant boundary is explicit and compatible with users belonging to
  multiple organizations.
- Mission runtime remains the semantic and operational root without taking on
  tenancy responsibilities it should not own.
- The data model stays simple for release one because spacecraft remain
  mission-owned.
- Organization-scoped and mission-scoped service automation can coexist without
  forcing everything into one scope.
- A shared-schema strategy remains viable because every mission-owned record can
  be safely partitioned by `organization_id` and `mission_id`.

### Negative

- Most queries and authorization checks must carry organization context
  explicitly.
- Shared-schema multi-organization safety depends on disciplined scoping across
  the entire codebase.
- Some future cross-mission asset features will require an additive lineage
  model because spacecraft are not organization-owned from the start.
- Service identity policy becomes more complex because it must distinguish org-
  and mission-scoped actors.

### Constraints Introduced

- `mission.slug` cannot be assumed globally unique.
- Mission-owned records should not be modeled with only `mission_id`.
- Cross-organization sharing of missions or runtime state is out of scope.
- Spacecraft reuse across missions is operationally allowed, but semantic
  linkage is not automatic.

## Open Questions

1. Should provider credentials and provider account records be fully
   organization-owned, or do some providers require mission-scoped credentials?
2. What should the authorization context object look like in application and web
   code for:
   - user plus organization membership
   - user plus organization plus mission
   - service identity plus organization
   - service identity plus organization plus mission
3. Which service-identity capabilities are allowed only at organization scope
   versus mission scope?
4. Do any read-only cross-organization support workflows need to exist for
   Cadence operators or SREs?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)

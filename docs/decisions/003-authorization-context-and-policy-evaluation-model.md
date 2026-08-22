---
title: "ADR-003: Authorization Context and Policy Evaluation Model"
aliases: [current scope model, auth scope model, policy evaluation model]
tags: [adr, architecture, authorization, authentication, phoenix, current_scope]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-003: Authorization Context and Policy Evaluation Model

## Status

Accepted

## Context

Cadence now has two accepted architectural baselines:

- [ADR-001](001-mission-scoped-runtime-and-selector-model.md), which makes
  `mission` the runtime and semantic root
- [ADR-002](002-organization-mission-scope-and-identity-model.md), which makes
  `organization` the tenant boundary and allows both user and service actors

We need an authorization model that works consistently across:

- Phoenix browser requests
- API requests
- internal service and automation actions
- organization-scoped workflows
- mission-scoped workflows

The main risks are:

- passing `current_user`, `organization_id`, and `mission_id` separately and
  inconsistently
- allowing service actors to impersonate human users by convenience
- evaluating authorization after broad queries instead of constraining reads and
  writes up front
- coupling policy logic to one specific web or library implementation

Cadence therefore needs one explicit authorization context model that can be
constructed at the boundary and passed into application code consistently.

## Decision

Cadence will use a single explicit `current_scope` authorization context for
both user and service actors, with policy evaluation performed in application
code against organization and optional mission scope.

### 1. One Canonical Authorization Context

Cadence will use a single scope object named `current_scope`.

`current_scope` is the canonical authenticated and authorized actor context used
by:

- Phoenix controllers and LiveViews
- API handlers
- application context modules
- internal effectful service operations

Cadence will not treat `current_user`, `current_organization`, and
`current_mission` as separate primary inputs in application code.

### 2. Scope Shape

`current_scope` should be modeled as one struct with this shape:

```elixir
%Cadence.Auth.Scope{
  actor_kind: :user | :service,
  organization_id: binary(),
  organization: %Organization{},
  mission_id: binary() | nil,
  mission: %Mission{} | nil,
  user: %User{} | nil,
  organization_membership: %OrganizationMembership{} | nil,
  service_identity: %ServiceIdentity{} | nil,
  role: atom() | nil,
  capabilities: MapSet.t()
}
```

Invariants:

- exactly one of `user` or `service_identity` is present
- `organization_id` is always present
- `mission_id` is optional
- if `mission_id` is present, the mission must belong to `organization_id`
- if `organization_membership` is present, it must belong to the same user and
  organization
- if `service_identity` is mission-scoped, it must align with both
  `organization_id` and `mission_id`

### 3. Two Scope Depths

Cadence supports two scope depths:

- organization scope
- mission scope

Organization scope is used for:

- organization settings
- mission creation and listing
- organization-scoped provider integrations
- organization membership and access management

Mission scope is used for:

- mission configuration authoring and activation
- mission data access
- replay, simulation, and operational workflows
- command, telemetry, and contact-related actions

Mission scope extends organization scope. It does not replace it.

### 4. Actor Kinds

Cadence recognizes two actor kinds:

- `:user`
- `:service`

#### User Actor

A user-backed scope contains:

- `user`
- `organization_membership`
- organization context
- optional mission context

User authorization is derived from organization membership role plus resource
scope.

#### Service Actor

A service-backed scope contains:

- `service_identity`
- organization context
- optional mission context

Service identities use explicit capabilities rather than borrowing human
membership semantics.

Service identities must never be represented as synthetic users by convenience.

### 5. Phoenix Boundary Contract

For Phoenix web code, `@current_scope` is the canonical template assign.

Cadence should follow Phoenix 1.8 scoped-auth conventions:

- routes and plugs resolve authenticated actor plus organization context
- routes that operate on one mission also resolve mission context
- the router or boundary layer builds `current_scope`
- downstream code receives `current_scope`, not parallel actor and scope values

Templates should derive actor information from `@current_scope`, not from
separate assigns such as `@current_user`.

### 6. Application Context Contract

Application context functions must accept `current_scope` as the first argument
for scoped operations.

Examples:

```elixir
Cadence.Missions.list_missions(current_scope)
Cadence.Governance.activate_configuration(current_scope, mission_slug, attrs)
Cadence.Telemetry.read_history(current_scope, point_id, opts)
```

This ensures reads and writes are constrained by authorization context at the
application boundary rather than after broad data access.

### 7. Policy Evaluation Model

Cadence policies should evaluate these inputs:

- `current_scope`
- action
- target resource or resource type
- optional operation metadata

Policy evaluation must consider:

- actor kind
- organization membership role or service capabilities
- organization ownership of the target
- mission ownership of the target where applicable
- action type
- any additional approval or environmental constraints

Specific role and capability matrices are intentionally deferred, but the policy
model must support both membership-based and capability-based decisions.

### 8. Query Scoping Rule

Shared-schema safety requires scope-first access patterns.

Cadence code must prefer:

- querying within `organization_id`
- and within `mission_id` when the resource is mission-owned

instead of:

- fetching a record globally
- then checking whether the actor should have been allowed to see it

Authorization should constrain the candidate dataset as early as possible.

### 9. Internal Operations Must Also Run Under Scope

Internal effectful operations must also carry `current_scope`.

This includes actions initiated by:

- replay jobs
- mission automation
- provider adapters
- internal operational services

Internal services should run under service-identity-backed scopes, not under
implicit superuser access.

### 10. Policy Result Contract

Cadence policy checks should return explicit allow or deny results with enough
structure for caller behavior and audit explanation.

The exact function shape is an implementation detail, but the model should
support outcomes equivalent to:

- `:ok`
- `{:error, :forbidden}`
- `{:error, {:forbidden, reason}}`
- `{:error, :scope_mismatch}`

Silent boolean-only authorization decisions are discouraged for effectful
operations because they lose denial reason and audit clarity.

### 11. Deferred Decisions

This ADR does not decide:

- the concrete role catalog for organization memberships
- the concrete service capability catalog
- the concrete authentication mechanism for user or service actors
- the specific policy library to use

Those remain implementation choices or later ADRs, provided they preserve this
authorization context model.

## Consequences

### Positive

- Cadence gets one consistent authorization contract across web, API, and
  internal services.
- Phoenix `current_scope` usage aligns with the platform tenancy model instead
  of being a thin user-only wrapper.
- Service identities remain explicit and auditable instead of being hidden as
  fake users.
- Shared-schema data access is safer because context functions are forced to
  accept scope explicitly.
- The model supports both organization-wide and mission-local workflows without
  requiring separate authorization systems.

### Negative

- More application functions must take `current_scope`, even when this feels
  verbose.
- Boundary code must resolve organization and mission context correctly before
  application logic runs.
- The model requires careful test coverage for scope construction and scope
  mismatch handling.
- Service identity provisioning and capability management become first-class
  platform concerns.

### Constraints Introduced

- New scoped features should not invent parallel auth parameter patterns.
- User-backed and service-backed operations must share the same policy surface.
- Mission-scoped operations cannot assume user-backed actors.
- Web templates and handlers should not depend on `current_user` as the primary
  auth context.

## Open Questions

1. What initial organization membership roles should release one support?
2. What initial service capabilities should release one support?
3. Which operations require approval state in addition to basic policy allow or
   deny?
4. Do support or SRE actors need a separate break-glass scope model, or should
   that be represented through ordinary service identities and audited
   elevation?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-002: Organization, Mission, and Identity Scope Model](002-organization-mission-scope-and-identity-model.md)

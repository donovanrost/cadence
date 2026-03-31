---
title: "ADR-004: Activation Authorization and Approval Policy"
aliases: [activation approval policy, config activation policy, governed activation]
tags: [adr, architecture, activation, authorization, approval, governance]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-004: Activation Authorization and Approval Policy

## Status

Accepted

## Context

Cadence is intended to support runtime reconfiguration without redeploy.

From prior decisions:

- [ADR-001](001-mission-scoped-runtime-and-selector-model.md) requires explicit
  activation and says configuration changes affect future traffic only
- [ADR-002](002-organization-mission-scope-and-identity-model.md) defines
  organization as the tenant boundary and mission as the runtime boundary
- [ADR-003](003-authorization-context-and-policy-evaluation-model.md) defines a
  single `current_scope` model for user and service actors

Cadence therefore needs a governed answer to these questions:

- who may request activation of a configuration basis
- when approval is required before activation
- who may approve or reject an activation request
- who actually executes activation
- how activation actions are attributed and audited

Without this, runtime reconfiguration becomes either unsafe or inconsistent:

- writing config could accidentally make it live
- service automation could gain implicit superuser power
- there would be no clear approval trail for operationally significant changes
- replay and investigation would lose the config-activation basis that explains
  what the system knew and when

## Decision

Cadence will use an explicit, governed activation workflow with separate request,
approval, and execution stages. Approval requirements are policy-driven, but
release one defaults to a conservative human-approval model in operational
environments.

### 1. Activation Is A Separate Effectful Operation

Writing or updating configuration does not make it live.

Cadence separates:

- authoring configuration
- validating configuration
- requesting activation
- approving activation
- executing activation

Activation is an explicit effectful operation against a validated configuration
basis.

### 2. Activation Applies To Future Traffic Only

Activation changes live handling only for future traffic and future runtime
behavior.

Activation must not silently reinterpret historical evidence or historical
canonical records.

If historical processing under a new basis is needed, Cadence uses replay or
reprocessing workflows rather than activation.

### 3. Activation Lifecycle States

Cadence should model activation workflow with states equivalent to:

- `draft`
- `validated`
- `activation_requested`
- `approval_pending`
- `approved`
- `rejected`
- `activation_in_progress`
- `active`
- `activation_failed`
- `superseded`

The exact storage schema may vary, but the domain workflow must preserve these
distinct steps.

### 4. Actor Roles In The Workflow

Cadence recognizes three workflow roles:

- requester
- approver
- executor

#### Requester

The actor that asks Cadence to make a validated basis live.

The requester may be:

- a user-backed scope
- a service-identity-backed scope

provided policy allows that actor to request activation for the target
organization and optional mission.

#### Approver

The actor that supplies required approval before activation may proceed.

In release one, approvers must be user-backed scopes when approval is required.
Service identities must not satisfy human approval requirements.

#### Executor

The actor that performs the state transition into live activation.

Execution may be performed by:

- the requesting user when no additional approval is required
- a Cadence internal service after approval requirements are satisfied

Execution remains attributable to both the requesting scope and the executing
scope.

### 5. Authorization And Approval Are Separate Gates

Cadence distinguishes:

- authorization to request activation
- approval requirement for a requested activation
- authorization to approve
- authorization to execute

An actor authorized to author configuration is not automatically authorized to
request activation.

An actor authorized to request activation is not automatically allowed to
self-approve.

### 6. Release-One Default Policy

Release one uses a conservative default policy:

- in operational shared environments, any runtime-affecting activation requires
  at least one human approver distinct from the requester
- local development or explicitly designated non-operational environments may
  allow simplified activation without separate approval

This default applies even if the underlying change appears operationally small.

Cadence may later support finer-grained approval classes, but release one should
bias toward safety and clear auditability rather than aggressive auto-activation.

### 7. Separation Of Duties

For activation requests that require approval:

- the requester must not satisfy the required distinct human approval slot
- service identities must not satisfy human approval slots

If an environment or policy later permits self-approval for low-risk cases, that
must be an explicit policy exception rather than the default behavior.

### 8. Policy Inputs

Activation policy evaluation must consider at minimum:

- `current_scope`
- target `organization_id`
- optional target `mission_id`
- activation target type
- change class
- environment or operational mode
- whether the actor is a user or service identity

The exact policy engine is not decided here, but policy outcomes must determine:

- whether activation request is allowed
- whether approval is required
- how many approvals are required
- which actor kinds or roles may approve
- whether execution may proceed

### 9. Change Classes

Cadence should classify activation requests by operational impact.

Release one does not need a fully mature classification matrix, but the model
must support classes such as:

- observational or read-side changes
- mission data-plane semantic changes
- transport, provider, or contact-path changes
- command or command-safety changes
- identity, policy, or security changes

The initial default policy may treat all runtime-affecting changes conservatively
in operational environments, but the classification hook must exist so policy
can become more precise later.

### 10. Activation Records

Cadence should retain distinct durable records for:

- the configuration basis being activated
- the activation request
- each approval or rejection action
- the activation execution result

These records must preserve:

- requesting actor
- approving actor or actors
- executing actor
- timestamps
- target organization and mission scope
- policy basis or rule outcome
- resulting active basis

This is required for audit, replay explanation, and incident review.

### 11. Runtime Convergence After Activation

Successful activation does not itself directly mutate runtime worker state.

Instead:

1. activation makes a configuration basis active
2. mission runtime reconcilers observe the active basis
3. runtime instances converge to that basis

This keeps activation and runtime reconciliation separate and consistent with the
reconciled-runtime model from ADR-001.

### 12. Internal Services Must Use Ordinary Policy Paths

Internal services and automation must request activation using service-backed
`current_scope` values and ordinary policy checks.

Cadence must not rely on hidden bypass paths that skip approval or authorization
by virtue of running inside the same system.

### 13. Failure Behavior

If validation fails, approval is not requested.

If approval is denied, activation does not proceed.

If execution fails after approval, Cadence must record activation failure
explicitly and leave the prior active basis unchanged unless a separate
transactional design later proves a safe partial-transition model.

### 14. Deferred Flexibility

This ADR intentionally leaves room for later additions such as:

- per-change-class approval matrices
- multi-approver or quorum policies
- time-limited approvals
- emergency break-glass activation workflows
- service-triggered activations that still require asynchronous human approval

Those are later extensions, not release-one defaults.

## Consequences

### Positive

- Runtime reconfiguration remains explicit and attributable.
- Cadence can support automation without giving internal services implicit
  superuser power.
- The approval trail becomes part of operational truth instead of being an
  out-of-band human process.
- Reconciler-driven runtime behavior stays clean because activation changes the
  active basis rather than manually poking running workers.
- The model leaves room for more granular policy later without weakening the
  release-one safety posture.

### Negative

- Operational changes take more workflow steps than a simple config write.
- Release-one approval may feel conservative for some low-risk changes.
- The system must model and persist more governance records before runtime
  activation is considered complete.
- Users and operators must understand the difference between validated config and
  active config.

### Constraints Introduced

- Config authoring and activation must remain separate operations.
- Approval requirements cannot be silently bypassed by internal services.
- Service identities cannot satisfy human approval slots in release one.
- Activation should not be modeled as historical reprocessing.

## Open Questions

1. What exact change classes should release one distinguish in policy?
2. Which non-operational environments may permit simplified activation?
3. Which human roles should be allowed to approve activation for:
   - ordinary mission data-plane changes
   - transport or provider changes
   - command-safety-related changes
   - org-wide security or identity changes
4. Does release one need a break-glass emergency activation mode, or is ordinary
   approval workflow sufficient?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-002: Organization, Mission, and Identity Scope Model](002-organization-mission-scope-and-identity-model.md)
- [ADR-003: Authorization Context and Policy Evaluation Model](003-authorization-context-and-policy-evaluation-model.md)

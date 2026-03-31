---
title: "ADR-011: Command Staging, Queueing, and Release Lifecycle"
aliases:
  [command stage, command queue lifecycle, command release lifecycle]
tags: [adr, architecture, commanding, staging, queueing, approval, release]
status: accepted
created: 2026-03-30
updated: 2026-03-30
---

# ADR-011: Command Staging, Queueing, and Release Lifecycle

## Status

Accepted

## Context

ADR-004 established Cadence's governed request, approval, and execution model
for runtime-affecting actions.

ADR-006 established that contact, path, and transport runtime are separate
operational layers.

ADR-010 established that the canonical command catalog is the imported source of
truth for command definitions, but does not own request, approval, release, or
queue state.

Cadence now needs an explicit lifecycle model for commanding that supports two
real operational requirements:

- operators need to prepare commands, edit parameters, and hand work to another
  operator for review before anything is queued for dispatch
- once commands are ready, operators need durable queueing with priorities that
  influence dispatch order

Legacy Cadence had both ideas:

- a mission-scoped staging workbench for collaborative command preparation
- target-scoped queued-command runtime with priority ordering

Those ideas are still useful, but the new architecture has different boundaries:

- `source_endpoint_ref`, not legacy target identity, is the default mission data
  and command routing scope
- approval and policy must follow the explicit workflow model from ADR-004
- contacts, paths, transports, and future `COP-1` live in the ADR-006 runtime
- command definitions compile from ADR-010 command catalogs into narrower
  runtime command artifacts

Cadence therefore needs a model that preserves the good parts of staging and
priority queueing without collapsing draft preparation, approval, queue order,
and live release into one object.

## Decision

Cadence will use a **separated command lifecycle**:

1. `CommandStage`
2. `StagedCommandItem`
3. `CommandRequest`
4. `CommandApproval`
5. `CommandQueueEntry`
6. `CommandReleaseAttempt`

Staging is collaborative draft state.
Queueing is durable dispatch ordering for ready commands.
Release is the effectful execution of a queued command through a specific
contact/path/transport context.

These are related, but they are not the same lifecycle object.

## Model

### 1. CommandStage

Cadence will support one or more explicit command stages per mission.

`CommandStage` is a mission-scoped container used to prepare and review command
work before queue submission.

It should record:

- `organization_id`
- `mission_id`
- stage ID, name, and description
- owner actor
- visibility or collaboration mode
- stage status
- audit metadata

Cadence should support at least these collaboration shapes:

- private or personal draft stages
- shared or reviewable stages

Cadence will not treat the entire mission as one implicit shared command stage.

### 2. StagedCommandItem

`StagedCommandItem` is the editable draft entry inside a stage.

It should record:

- `organization_id`
- `mission_id`
- `command_stage_id`
- target `source_endpoint_ref`
- compiled command source references:
  - `command_snapshot_id`
  - `command_id`
- operator-supplied argument values
- optional notes and review metadata
- desired priority
- optional `not_before`
- optional expiration metadata
- item ordering within the stage

`StagedCommandItem` is draft state.
It is allowed to be edited, reordered, reviewed, or removed while it remains in
the stage.

### 3. Staging Is Not Approval

Cadence will explicitly distinguish:

- collaborative review of staged commands
- formal approval required for command release

Stage review may indicate that a staged item is ready for submission, but it
does not satisfy governed approval requirements by itself.

Submitting a staged item into the formal command lifecycle must still run
authorization and policy evaluation under ADR-004 and ADR-003.

### 4. CommandRequest

`CommandRequest` is the durable formal command intent record.

It may be created:

- directly from a user or service actor for one-off commanding
- from one or more staged items when an operator submits a stage

`CommandRequest` should snapshot the command intent at submission time,
including:

- organization and mission scope
- target `source_endpoint_ref`
- command snapshot and command definition references
- resolved argument values and defaults
- validation result and encoded preview when available
- requester actor
- risk or significance metadata
- provenance back to the source staged item when applicable

Once a staged item is submitted into a `CommandRequest`, further edits should
occur through a new staged revision or a new request, not by mutating the
meaning of the already-submitted request.

### 5. CommandApproval

`CommandApproval` is a durable approval or rejection action attached to one
`CommandRequest`.

Approval policy must consider at minimum:

- `current_scope`
- mission and organization scope
- compiled command operational metadata such as significance or hazardous flags
- environment and policy context
- actor separation requirements

If approval is required, a stage reviewer does not automatically satisfy it.
Human approval requirements remain distinct from stage collaboration.

### 6. CommandQueueEntry

`CommandQueueEntry` is a durable queue record created only when a
`CommandRequest` is ready to await dispatch.

Queue entry creation occurs:

- immediately after validation for low-risk or policy-exempt flows, or
- after required approvals are satisfied

The queue entry should record:

- organization and mission scope
- target `source_endpoint_ref`
- `command_request_id`
- queue lane
- priority
- queue sequence
- `not_before`
- expiration metadata
- queue status and audit metadata

`CommandQueueEntry` is the object whose ordering influences dispatch.

### 7. Default Queue Lane

Cadence will serialize queued commands by default queue lane of
`source_endpoint_ref`.

That means:

- commands for the same `source_endpoint_ref` are ordered and released
  sequentially
- commands for different source endpoints may progress independently

This is the new-system successor to legacy per-target serialization and matches
the mission/runtime partition model more cleanly than a mission-global command
queue.

Future releases may define optional sub-lanes such as preferred uplink service
or transport class, but the release-one default lane is `source_endpoint_ref`.

### 8. Priority Semantics

Cadence will support explicit command priorities on both staged items and queue
entries.

The product surface should expose named priority classes.
Cadence may store a numeric sort rank internally.

Priority only influences order among commands that are:

- in the same queue lane
- not already released or in flight
- eligible by time window
- not expired
- otherwise ready for dispatch

Default ordering within a lane is:

1. eligible commands only
2. highest priority first
3. FIFO by queue sequence within the same priority

Priority does not:

- bypass approval requirements
- bypass command-safety checks
- bypass transmission constraints
- preempt a command already in release or transport execution

If a higher-priority command is currently ineligible because of timing or
constraint evaluation, Cadence may dispatch the next lower-priority eligible
command in that lane.

### 9. Stage Submission Semantics

Cadence should support batch submission from one stage.

When multiple staged items are submitted together:

- each staged item becomes its own `CommandRequest`
- resulting queue entries preserve stage item order within the same queue lane
  and same priority class
- staged items should move to a submitted terminal state or retain explicit
  linkage to the resulting requests

This preserves the useful legacy workflow of preparing a large batch of
commands, checking them, and then enqueuing them in one action.

### 10. CommandReleaseAttempt

`CommandReleaseAttempt` is the operational execution record created when Cadence
tries to release a queued command into the live uplink path.

It should record:

- organization and mission scope
- `command_queue_entry_id`
- selected `realized_contact_id`, `path_id`, or transport runtime reference
- executor actor or service identity
- release timestamps and status
- emitted `uplink_request` reference
- verifier and completion linkage

Queueing and release remain separate because queue state expresses ordering,
while release state expresses actual operational execution.

### 11. Relationship To Contacts And Transport Runtime

Queue entries do not permanently own contact, path, or transport routing.

At queue time, a command may carry hints such as:

- preferred uplink service
- release policy hints
- optional contact affinity

But actual routing and transport execution are resolved at release time against
the live ADR-006 contact/path/transport runtime.

### 12. Direct Commanding Without Staging

Cadence must support direct command flows that skip staging.

Direct flow still uses the same formal lifecycle after creation:

`CommandRequest -> CommandApproval -> CommandQueueEntry -> CommandReleaseAttempt`

Staging is optional preparation workflow, not a mandatory prerequisite for all
commands.

## Lifecycle Summary

The canonical lifecycle is:

`CommandStage -> StagedCommandItem -> CommandRequest -> CommandApproval -> CommandQueueEntry -> CommandReleaseAttempt`

With direct commanding:

`CommandRequest -> CommandApproval -> CommandQueueEntry -> CommandReleaseAttempt`

## Explicit Non-Goals

This decision does not:

- define the final UI for command staging or queue management
- define the full role or capability matrix for command approvals
- define transport-specific release details such as `COP-1` behavior
- define the full command verification state machine
- require all commands to pass through staging before queueing
- create one mission-global total ordering across every source endpoint

## Consequences

This decision gives Cadence a command workflow that:

- preserves the useful legacy distinction between staging and queueing
- fits the explicit approval model from ADR-004
- fits the mission/runtime and transport boundaries from ADR-006
- uses `source_endpoint_ref` as the clean default dispatch lane
- supports large reviewed command batches without turning the queue itself into
  a draft workbench
- keeps direct one-off commanding possible

The next step is to implement the domain model and API around:

- command stages and staged items
- command requests and approvals
- queue entries with per-lane priority ordering
- release attempts that emit typed `uplink_request` actions

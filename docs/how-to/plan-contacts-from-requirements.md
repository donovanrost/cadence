---
title: Plan Contacts from Requirements
tags: [how-to, operations, contact-planning, providers]
status: active
created: 2026-07-16
updated: 2026-07-17
---

# Plan Contacts from Requirements

Use a Contact Requirement when the mission has an operational outcome to
satisfy and wants to compare one or more provider routes before committing
capacity. Use **Ops → Contacts** for a one-off direct reservation that does not
need a Requirement or Plan.

## Before planning

The spacecraft needs at least one ready provider-managed downlink route:

1. an organization Provider Account with a valid credential and active mission
   grant;
2. a validated and synchronized Mission Provider;
3. an active Service Profile and ready Delivery Profile;
4. a provider-managed Transport derived from those exact profile versions;
5. a provider spacecraft mapping and enabled inbound Routing Rule.

The provider also needs usable orbital data. Cadence does not upload or
propagate ephemeris during Stage 4. It asks the provider for opportunities and
stores bounded readiness evidence such as source, ephemeris reference/version,
epoch, validity interval, and validation state.

## Describe the need

Open **Ops → Requirements** and select **Plan a contact**. Choose the spacecraft,
operational intent, earliest acceptable start, latest acceptable end, and
success measure. Add duration, volume, count, separation, provider/station, or
policy constraints only when the mission needs them.

Saving creates a stable Requirement identity and immutable version 1. Editing
content creates the next immutable version. Closing or canceling the Requirement
prevents new planning without deleting its history.

## Search provider routes

Run planning from the Requirement detail. Cadence resolves every eligible exact
route and stores one outcome for each:

- `succeeded_with_results`: the provider evaluated the horizon and returned
  opportunities;
- `succeeded_without_results`: the provider evaluated the horizon and returned
  no matching availability;
- `not_ready`: local setup or provider orbital data prevented evaluation;
- `failed`: the provider request or response failed;
- `excluded_by_requirement`: an explicit Requirement constraint omitted the
  route without calling it.

A partial planning run preserves usable results alongside unavailable providers.
Do not interpret `not_ready` or `failed` as proof that no contact is possible.
Correct the provider mapping, credential, route, or orbital data and start a new
planning run; prior runs remain immutable evidence.

## Build and review a Plan

Select eligible opportunity snapshots and create a draft Plan. The Plan freezes
the exact Requirement version, planning runs, provider windows, route/profile
versions, policy, coverage, conflicts, warnings, rejected alternatives, and
content hash.

Submit the draft when the manifest is ready. An organization administrator must
review and approve the exact current version with a reason. Approval fails if
the Requirement changed, the opportunity expired, a grant was revoked, the
route binding changed, or Requirement policy would widen provider policy.
Rejection is append-only evidence and requires a new Plan version before another
submission.

## Execute and recover

Execution creates one durable item and stable idempotency key per selected
opportunity before any provider mutation. The resulting Provider Reservation
links back to the exact Requirement, Plan, and opportunity snapshot. Confirmed
capacity materializes the ordinary Scheduled Contact and enters the existing
contact/TCP/CCSDS runtime.

Multiple selections execute independently. Some can reserve while others fail
or remain uncertain; Cadence does not cancel successful provider commitments
automatically. If a response is lost after provider commit, the item stays
uncertain. Stage 3 reconciliation recovers the Provider Reservation by its
declared provider correlation mechanism, and the Plan executor converges the
linked item without blindly sending another reservation.

Use the Plan manifest for intent, approval, and execution-item state. Use the
linked **Ops → Contacts** detail for requested, provider-confirmed,
Cadence-accepted, and realized Contact truth.

## Plan a fleet horizon

Open **Ops → Planning** when the mission needs to reason over many active
Requirements together. Mission members can start and inspect runs. Organization
administrators manage the policy, recurring templates, and automation grants
because those objects can authorize repeated or unattended provider mutations.

Before the first run, an organization administrator:

1. creates a Fleet Planning Policy;
2. reviews and approves its exact immutable version;
3. optionally creates and activates recurring Requirement Templates;
4. optionally issues an Automation Grant to one named mission-scoped service
   identity.

The active policy defines the maximum horizon, bounded Requirement and provider
search concurrency, hard resource capacity, quota and budget ceilings,
redundancy rules, deterministic score weights, execution concurrency, and repair
bounds. Score can rank only feasible opportunities; it never overrides a hard
constraint.

Select **Plan horizon**, choose a bounded UTC interval, and start the run.
Cadence persists the Fleet Planning Run and exact Requirement/policy inputs
before work begins. The run then checkpoints materialization, Stage 4 searches,
optimization, and candidate-Plan creation. A restart resumes the durable phase
rather than starting another run.

The run page emphasizes:

- the phase strip and persisted progress counts;
- the horizon rail and spacecraft coverage matrix;
- exclusive provider/station/service-pool pressure;
- unsatisfied, not-ready, failed, quota, budget, and expiry exceptions;
- one selected, displaced, ineligible, or locked decision for each considered
  opportunity snapshot;
- the exact candidate Contact Plan.

The candidate remains an ordinary Stage 4 Plan. In advisory mode, submit,
approve, and execute it manually. Bounded automation may cross only the
contiguous actions named by an active exact-policy grant and records the service
identity, grant hash, approving administrator, and reason. Revoked, expired,
stale-policy, or over-cap grants stop closed.

If provider execution is partial or uncertain, select **Plan repair** from the
run. The repair run locks successful and uncertain commitments, searches only
unmet work, and creates a new ordinary candidate Plan containing only new
bookable selections. It never treats an ambiguous provider mutation as free
capacity.

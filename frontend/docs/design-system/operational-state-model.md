# Cadence operational state model

## Status

Working semantic contract for the Vue frontend proof of concept. This document
turns the [design-system charter](charter.md) into a testable state language for
the first reference experience: live monitoring.

This model is intentionally independent of color, typography, component APIs,
and layout. It does not replace domain state machines or authorize changes to
the current Phoenix application contracts. It defines how frontend experiences
must preserve and present the meaning of those contracts. The
[symbology specification](symbology.md) defines how explicit presentation
policy may encode that meaning without collapsing these axes.

## The problem this model solves

An operational screen often receives several true facts at once:

- a source answered its health probe;
- the newest complete data is six minutes old;
- most samples are good, but one is suspect;
- the requested interval begins before retention;
- a workflow is awaiting approval; and
- the current operator is not permitted to approve it.

Calling all of that `warning`, `offline`, or `error` destroys information. It
also makes aggregation unpredictable and encourages presentation choices to
leak back into domain logic.

Cadence therefore represents operational condition as a **state vector**, not
one universal severity:

> A subject has independently assessed health, availability, data quality,
> freshness, coverage, support, workflow, urgency, and authority within an
> explicit scope, time context, and policy.

Not every subject uses every axis. An omitted axis means **not applicable**. It
must not be interpreted as nominal, false, or unknown.

## Semantic pipeline

Every operational presentation follows the same direction of travel:

1. **Facts** report what was observed without UI interpretation.
2. **Assessments** evaluate facts against an identified policy or contract.
3. **Presentation** decides how much attention and interruption the assessment
   warrants in the current workflow.

For example:

| Layer        | Example                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| Fact         | The source watermark is complete through `14:22:08 UTC`.                                                                              |
| Assessment   | At `14:28:08 UTC`, policy `telemetry-live-v1` classifies it as `stale`.                                                               |
| Presentation | Keep the last known series visible, label it `Stale · 6 min`, and expose source evidence without moving the chart or opening a modal. |

Facts must remain recoverable from assessments, and assessments from
presentations. A component must not infer domain health from a CSS tone, icon,
or message string.

## Semantic state envelope

The design system expects operational state to arrive in, or be adapted into,
an envelope with these concepts. This is a conceptual contract, not yet a
TypeScript interface:

| Field             | Meaning                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------ |
| Subject           | Stable identity and type of the thing being described.                                           |
| Context           | Organization, mission, spacecraft, source, dataset, realm, and other scope that changes meaning. |
| Time context      | Live, archive, replay, simulation, or another explicit mode; selected range and reference clock. |
| Axes              | Applicable semantic values defined below.                                                        |
| Reason codes      | Stable, machine-readable explanations for each non-nominal or unknown value.                     |
| Observed at       | When the underlying fact was observed.                                                           |
| Assessed at       | When policy interpreted the fact.                                                                |
| Policy            | Identity and version of any threshold, limit, readiness, or urgency policy used.                 |
| Evidence          | Links or identifiers that lead to source facts, provenance, and relevant history.                |
| Available actions | Context-valid recovery, investigation, or workflow actions.                                      |

The envelope must retain source-native values when an adapter maps them into
the shared vocabulary. This makes the mapping inspectable and prevents a UI
normalization from masquerading as the original evidence.

## Shared axes

### Health

Health describes whether a subject is behaving within its intended operating
condition. It does not describe whether Cadence can currently communicate with
the subject.

| State      | Meaning                                                                  | Must not imply                                            |
| ---------- | ------------------------------------------------------------------------ | --------------------------------------------------------- |
| `nominal`  | Evidence supports expected behavior.                                     | That data is fresh, complete, or available.               |
| `degraded` | The subject is functioning with a known impairment.                      | That it is unusable or requires immediate action.         |
| `failed`   | Evidence supports that the subject cannot perform its intended function. | That every dependent surface has no usable retained data. |
| `unknown`  | Available evidence cannot support a health assessment.                   | Nominal behavior or failure.                              |

Use `failed` only when evidence describes the subject's function. A connection
failure usually establishes `availability: unavailable`, not `health: failed`.

### Availability

Availability describes whether the subject or capability can be used in the
current context.

| State         | Meaning                                                 | Must not imply                 |
| ------------- | ------------------------------------------------------- | ------------------------------ |
| `available`   | The capability can be used as intended now.             | Nominal health or fresh data.  |
| `limited`     | The capability remains usable with a known restriction. | Failure.                       |
| `standby`     | The capability is intentionally ready but not active.   | Degradation or unavailability. |
| `unavailable` | The capability cannot currently be used.                | Why it is unavailable.         |
| `unknown`     | Availability has not been established.                  | Unavailable or available.      |

### Data quality

Data quality describes confidence in an individual observation or a
well-defined set of observations. It must stay scoped to the data it assesses.

| State     | Meaning                                                                                             | Must not imply                              |
| --------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `good`    | The observation passed its applicable quality checks.                                               | Freshness, nominal limits, or completeness. |
| `suspect` | The observation may be usable but has a known reason for doubt.                                     | That the value must be discarded.           |
| `bad`     | The observation failed an applicable quality check and must not be treated as trustworthy evidence. | Source failure.                             |
| `unknown` | No usable quality assessment is available.                                                          | Bad data or good data.                      |

When a set contains mixed quality, preserve counts and the affected members.
Do not relabel every member with the worst state.

### Freshness

Freshness describes the age of available evidence relative to the active time
context and an identified policy.

| State     | Meaning                                                                                    | Must not imply                                                       |
| --------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------- |
| `fresh`   | The freshness cursor is within policy for the active time context.                         | Good quality, complete coverage, or source health.                   |
| `stale`   | The cursor is older than policy permits.                                                   | That the source is unavailable or that retained values are unusable. |
| `unknown` | Cadence cannot establish a cursor, policy, or confidence sufficient to classify freshness. | Stale data.                                                          |

Freshness is always relative. In live mode it is commonly assessed against
now; in archive mode it is assessed against the requested interval. A source
can be healthy while its data is stale, and unavailable while its retained
data remains fresh enough for an investigation.

### Coverage

Coverage describes whether available evidence spans the requested subject and
time interval. It is separate from freshness because recent data can still be
incomplete.

| State               | Meaning                                                                                    | Must not imply                                   |
| ------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| `complete`          | Available evidence covers the requested scope and interval according to source confidence. | Good quality or fresh data.                      |
| `partial`           | Some requested evidence is available and some is known to be missing.                      | That the available portion is unsafe to inspect. |
| `none`              | The source responded successfully but no evidence matched the request.                     | Source failure or unsupported scope.             |
| `outside_retention` | Some or all of the requested interval predates available retention.                        | Staleness or source failure.                     |
| `unknown`           | Cadence cannot establish coverage.                                                         | Complete or empty coverage.                      |

### Support

Support describes whether the requested operation can be expressed by the
selected source, adapter, contract, and scope.

| State         | Meaning                                                       | Must not imply                             |
| ------------- | ------------------------------------------------------------- | ------------------------------------------ |
| `supported`   | The request is valid for the selected capability and context. | That execution succeeded or returned data. |
| `unsupported` | A known contract or capability cannot satisfy the request.    | Source failure.                            |
| `unknown`     | Compatibility has not been established.                       | Unsupported behavior.                      |

Unsupported is a configuration or capability result. It should lead to a
different recovery path than an execution failure.

### Workflow

Workflow describes progress through a domain-owned process. Domain state
machines remain authoritative; this shared vocabulary is for cross-surface
summaries and interaction patterns.

| State                 | Meaning                                                    |
| --------------------- | ---------------------------------------------------------- |
| `idle`                | No instance is in progress.                                |
| `preparing`           | Input is being assembled or validated before submission.   |
| `pending`             | Submitted and waiting for processing or another party.     |
| `approved`            | Required approval is recorded but execution has not begun. |
| `executing`           | Work is actively in progress.                              |
| `succeeded`           | The intended workflow outcome completed.                   |
| `partially_succeeded` | Some intended outcomes completed and some did not.         |
| `failed`              | The workflow ended without its intended outcome.           |
| `rejected`            | An authorized decision explicitly declined the request.    |
| `canceled`            | The workflow was intentionally ended before completion.    |
| `unknown`             | Current workflow state cannot be established.              |

Do not translate every domain lifecycle into this list and discard the source
state. A booking in `uncertain` or a planning run in `partial` must keep that
native state and evidence even when it is summarized for a shared pattern.

### Urgency

Urgency describes the required response, not the condition itself. It is
derived from consequence, time, scope, and policy.

| State           | Meaning                                              | Default presentation                                                    |
| --------------- | ---------------------------------------------------- | ----------------------------------------------------------------------- |
| `none`          | No response is requested.                            | Remain quiet; expose details on demand.                                 |
| `informational` | Awareness is useful; no timely response is required. | Local text, activity, or a quiet indicator.                             |
| `attention`     | A response or investigation is required soon.        | Persistent contextual emphasis with a clear next step.                  |
| `immediate`     | Delay materially increases operational consequence.  | Persistent high-salience signal and the safest available response path. |

`critical`, `red`, `failed`, and `bad` do not automatically mean
`urgency: immediate`. The owning policy makes that assessment. Likewise,
unknown evidence may warrant immediate action in one workflow and only
informational treatment in another.

### Authority

Authority describes what the authenticated actor may do for one action in the
current scope. It is server-owned and action-specific.

| State               | Meaning                                                                                                    |
| ------------------- | ---------------------------------------------------------------------------------------------------------- |
| `permitted`         | The actor may commit the action now.                                                                       |
| `approval_required` | The actor may prepare or request the action, but another authorization step is required before commitment. |
| `prohibited`        | Policy explicitly denies the action in this scope.                                                         |
| `unknown`           | Authority cannot be established; commitment must fail closed.                                              |

Disabling a button is not a complete authority presentation. The interface
must explain the restriction, identify any available request or handoff path,
and still rely on server enforcement.

## Context that must accompany state

Some concepts change the meaning of every axis but are not themselves status:

| Context       | Required behavior                                                                                                           |
| ------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Scope         | Show the organization, mission, spacecraft, source, dataset, or other subject boundary needed to prevent mistaken identity. |
| Realm         | Distinguish production/live evidence from simulation, replay, exercise, or development evidence.                            |
| Time mode     | Distinguish following live, paused from live, archive/range, and replay.                                                    |
| Selected time | Show the active range and reference clock when it changes interpretation.                                                   |
| Policy        | Identify thresholds or rules when they create an assessment or block an action.                                             |
| Actor         | Show identity and relevant role or authority near consequential commitment.                                                 |

`live` is a time mode, not a synonym for fresh, connected, healthy, or
nominal. A user can be following the live window while the newest source data
is stale.

## Mapping current Cadence contracts

The current backend contracts already contain much of the required evidence.
The Vue semantic adapter should preserve these values and map them as follows:

| Existing contract                                                                                                                   | Shared interpretation                                                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| [`SourceHealthEvent.source_health`](../../../apps/cadence/lib/cadence/data_sources/source_health_event.ex) `healthy`                | `health: nominal`; establish `availability: available` only when the evidence also proves reachability.                            |
| `degraded`                                                                                                                          | `health: degraded`; availability remains independently assessed.                                                                   |
| `unavailable`                                                                                                                       | `availability: unavailable`; do not claim `health: failed` without evidence of functional failure.                                 |
| `unknown`                                                                                                                           | `health: unknown` and, unless other evidence exists, `availability: unknown`.                                                      |
| [`SourceWatermark.freshness_state`](../../../apps/cadence/lib/cadence/data_sources/source_watermark.ex) `fresh`, `stale`, `unknown` | Map directly to the freshness axis with cursor, confidence, checked time, and policy.                                              |
| `retention_gap`                                                                                                                     | `coverage: outside_retention`; freshness must be assessed separately.                                                              |
| [`Telemetry.Sample.quality_state`](../../../apps/cadence/lib/cadence/telemetry/sample.ex) `good`, `suspect`, `bad`                  | Map directly to data quality at sample scope.                                                                                      |
| [`FrameLifecycle`](../../../apps/cadence/lib/cadence/dashboards/frame_lifecycle.ex)                                                 | Treat as a compatibility presentation summary, not an authoritative universal status. Decompose it using reason and warning codes. |
| `ready`                                                                                                                             | No blocking lifecycle condition was found; do not infer that all axes are nominal.                                                 |
| `no_data`                                                                                                                           | Usually `coverage: none` after a successful supported query. Preserve the empty reason.                                            |
| `stale`                                                                                                                             | Map the underlying stale or unknown-watermark reason to freshness; do not infer source failure.                                    |
| `partial`                                                                                                                           | `coverage: partial`; retain the partial-data reason and available evidence.                                                        |
| `retention_gap`                                                                                                                     | `coverage: outside_retention`; block only the affected request or action.                                                          |
| `error`                                                                                                                             | Derive health or availability from the reason code; never map the label alone.                                                     |
| `unsupported`                                                                                                                       | `support: unsupported`.                                                                                                            |
| [`Limits.Evaluator.limit_state`](../../../apps/cadence/lib/cadence/limits/evaluator.ex)                                             | Preserve the directional limit condition. Legacy color names are compatibility codes, not design-token or urgency names.           |
| [`HostContext.actor.permissions`](../../packages/plugin-sdk/src/bridge.ts)                                                          | Input to action-specific authority presentation; the server response remains authoritative.                                        |
| `HostActivityEvent.status`                                                                                                          | Map `started`, `completed`, and `failed` into the owning query/action workflow without treating query failure as mission health.   |

This mapping deliberately does not turn the current UI components, tokens, or
message strings into sources of semantic truth.

## Aggregation rules

### Aggregate one axis at a time

There is no universal ordering across axes. `bad` quality cannot be compared to
`stale` freshness, and `unsupported` cannot be ranked against `degraded`.

An aggregate must therefore:

1. declare its subject set, scope, time context, and policy;
2. aggregate each applicable axis independently;
3. retain counts for every non-empty state;
4. preserve unknown and not-applicable as different concepts;
5. expose the members and evidence behind the summary; and
6. state whether any action is blocked and why.

A useful summary says `2 sources unavailable · 1 dataset stale`, not `System
warning`.

### Unknown is first-class

Unknown never collapses into nominal. It also does not automatically outrank a
known failure. Presentation priority depends on consequence: a known failed
redundant source may matter less than unknown authority for an imminent
command.

### Nominal may be silent only when it is known

Routine nominal state should not consume persistent attention. It may be
omitted from a dense surface when:

- the assessed subject set is explicit;
- completeness of the assessment is known;
- exceptions and unknowns remain visible; and
- the evidence can be inspected nearby.

Silence must never turn missing assessment into an implied all-clear.

### Presentation priority is not semantic severity

When space is constrained, choose what to surface using this order of
questions:

1. Does a condition require immediate action?
2. Is the current task blocked or unsafe to commit?
3. Is the user looking at uncertain, stale, partial, or bad evidence?
4. Is a capability degraded or unavailable?
5. Is there useful informational context?

This order selects attention; it does not overwrite the underlying axes.

## Presentation contract

Every visible non-nominal or unknown state must provide, directly or through a
reachable disclosure:

- a specific text label;
- affected subject and scope;
- reason, without relying on color;
- observed and assessed time where age matters;
- policy or threshold when it caused the assessment;
- evidence or provenance;
- impact on the current task;
- available recovery or investigation action; and
- an accessible name and semantic role.

Additional rules:

- A **status symbol** is an explicit output of presentation policy. Components
  must not derive a symbol role from one axis, a CSS tone, or a message string.
- A **blocking** state prevents only the unsafe or impossible interaction. It
  does not disable unrelated inspection.
- A **persistent** state remains until newer evidence resolves it or the user
  leaves its scope. A toast cannot be the only record of an operational state.
- Use a full state panel for local absence or failure only when the primary
  content cannot remain useful. Stale and partial data should normally remain
  visible with an adjacent qualification.
- Do not use indefinite animation to mean `live`, `nominal`, or `connected`.
  Motion is reserved for a meaningful transition or bounded in-progress work.
- Announce background changes to assistive technology according to urgency.
  Routine live updates should not continuously interrupt reading.
- Keep source-native language available in evidence details, but use the shared
  vocabulary for cross-product labels.

## Live-monitoring scenario matrix

These fixtures are the acceptance surface for the first low-fidelity Storybook
reference experience. They describe semantics and behavior, not visual style.

| Scenario                              | Semantic state                                                                                                                                                     | Required behavior                                                                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nominal live monitoring               | Health `nominal`; availability `available`; quality `good`; freshness `fresh`; coverage `complete`; support `supported`; urgency `none`.                           | Keep the canvas quiet. Show scope, live mode, and latest evidence time without a celebratory banner or continuous animation.                       |
| Healthy source, quiet stream          | Health `nominal`; availability `available`; freshness `fresh` if the watermark supports it; coverage reflects the request.                                         | Advance the live time window even when no new sample changes the value. Do not infer staleness from a visually quiet series.                       |
| Stale data from a reachable source    | Health may remain `nominal`; availability `available`; freshness `stale`; retained quality and coverage remain independently visible; urgency usually `attention`. | Keep last known data inspectable, label its age and policy, and provide source evidence. Do not call the source offline.                           |
| Freshness unknown                     | Freshness `unknown`; watermark confidence or cursor is missing.                                                                                                    | Say `Freshness unknown`, not `Stale`. Preserve data with an uncertainty qualification and an evidence path.                                        |
| Partial interval                      | Coverage `partial`; freshness may be `fresh`; available samples retain their own quality.                                                                          | Keep the available series chartable, mark the missing span, and explain the coverage boundary. Do not replace useful data with a full error panel. |
| Outside retention                     | Coverage `outside_retention`; support `supported`; source may be healthy and available.                                                                            | Block only the unavailable range, show the retention start, and offer a valid range adjustment. Do not blame source execution.                     |
| Source unavailable with retained data | Availability `unavailable`; freshness reflects retained evidence or becomes `unknown`; health is not automatically `failed`.                                       | Preserve last known values when safe, mark them as frozen or aged, and expose the source incident and recovery path.                               |
| Degraded source still delivering      | Health `degraded`; availability `available` or `limited`; freshness may be `fresh`; urgency follows policy.                                                        | Continue monitoring, qualify the impairment, and avoid a blocking takeover unless the current action is unsafe.                                    |
| Suspect or bad sample                 | Affected observations are quality `suspect` or `bad`; other axes remain independent.                                                                               | Mark the affected value and downstream conclusions, retain raw/provenance evidence, and do not label the entire source unhealthy.                  |
| No matching data                      | Support `supported`; availability `available`; coverage `none` for the explicit scope and range.                                                                   | Show an actionable empty state with the request context. Do not present a source error or operational alarm.                                       |
| Unsupported request                   | Support `unsupported`; other axes are not applicable unless separately known.                                                                                      | Explain the unsupported capability or scope and offer configuration or source-selection recovery. Do not retry it as an execution failure.         |
| Archive range                         | Time mode `archive`; freshness is evaluated against the selected interval rather than wall-clock now.                                                              | Display the selected range and clock, suppress live affordances, and never label historical data stale merely because it is old.                   |
| User leaves the live edge             | Time mode remains live-capable but follow-live is false; selected time is historical.                                                                              | Freeze the viewport, preserve selection and inspectors, indicate `Paused from live`, and provide an explicit return-to-live action.                |
| New urgent limit condition            | Preserve the directional limit fact; derive urgency from policy, potentially `immediate`; freshness and quality remain visible.                                    | Add durable activity/evidence, signal without moving the user's viewport, and provide the safest response path. Never rely on a transient toast.   |
| Approval or permission boundary       | Workflow reflects preparation or pending approval; authority is `approval_required`, `prohibited`, or `unknown`.                                                   | Explain who can do what, retain prepared input, and fail closed at commitment. Do not present lack of authority as system unavailability.          |

## Reference-experience acceptance criteria

The live-monitoring specimen is semantically successful when:

- every rendered exception maps to a specific axis and reason code;
- no label, icon, or tone silently combines two axes;
- nominal silence never hides unknown assessment coverage;
- partial, stale, and retained evidence remain usable when safe;
- blocking behavior is local and justified by consequence;
- time mode, evidence age, and selected range cannot be mistaken for one
  another;
- every aggregate can be expanded to affected subjects and evidence;
- live updates preserve viewport, selection, expanded content, and in-progress
  input;
- state remains understandable without color or motion;
- every status symbol maps through an identified presentation policy and never
  replaces the underlying axis labels or evidence;
- authority is action-specific and server-enforced; and
- scenario fixtures can be rendered deterministically in Storybook.

## Implementation sequence

1. Define typed fixture objects for every scenario in this matrix without
   importing the experimental design tokens.
2. Build a low-fidelity live-monitoring composition that can switch among the
   fixtures while preserving scope and time context.
3. Identify the smallest repeated presentation contracts. Candidate primitives
   include `StatusSymbol`, `MonitoringSymbol`, `DataValue`, `TimeContext`,
   `EvidenceDisclosure`, and `StatePanel`; these names and APIs are not approved
   by this document.
4. Add automated assertions for labels, accessible roles, evidence access,
   local blocking, and live-update stability.
5. Promote only demonstrated reusable contracts into `packages/ui`.
6. Explore visual language and tokens after the semantic fixtures expose the
   required roles and attention hierarchy.

## Open decisions

The reference experience should resolve, rather than assume:

- freshness policies and how operators inspect them;
- which limit conditions create `attention` or `immediate` urgency;
- the minimum evidence required before an aggregate may imply nominal state;
- how mixed-quality and mixed-freshness counts collapse at each scale;
- vocabulary for paused-from-live versus archive and replay;
- how authority reasons and approval routes are represented by the production
  host bridge; and
- which state transitions warrant an assistive announcement, activity entry,
  or explicit acknowledgement.

Until those decisions are backed by domain contracts and scenario evidence,
components and tokens must not invent answers locally.

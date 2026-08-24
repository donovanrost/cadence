# Cadence symbology

## Status

Working semantic and construction specification for the Vue frontend proof of
concept. This document is subordinate to the
[design-system charter](charter.md), the
[operational state model](operational-state-model.md), and the
[visual foundations](visual-foundations.md).

It defines a stable visual language for operational subjects, status, actions,
tools, component behavior, and notifications. It does not make icons or colors
sources of domain truth, approve a finished asset library, or adopt Astro's
visual styling or component implementation.

## Decision

Cadence will retain the durable part of Astro UXDS symbology:

- icon classes have distinct responsibilities;
- a monitored subject combines a recognizable subject glyph, a stable label,
  and a separate status symbol;
- operational status uses an invariant combination of shape and color;
- status remains understandable without color;
- notifications remain distinct from the condition of the monitored subject;
  and
- symbol usage is governed as a learned operator language, not chosen locally
  for decoration.

Cadence will redraw the glyphs and apply its own operational-monochrome visual
language. It will not import Astro Web Components, icon packages, palettes,
typography, spacing, or compliance claims.

The central rule is:

> Color is informative, but never sufficient. Operational state uses a stable
> combination of symbol, color, label, and accessible text.

## Research basis

This specification distills the semantic separation and redundant status
encoding documented by Astro rather than its appearance:

- [Icons and Symbols](https://www.astrouxds.com/components/icons-and-symbols/)
  separates monitoring, action, utility, component, status, and notification
  roles.
- [Status System](https://www.astrouxds.com/patterns/status-system/) describes
  status as a consistent color-and-shape vocabulary and reserves the strongest
  signal for conditions requiring immediate attention.
- [Status Symbol](https://www.astrouxds.com/components/status-symbol/) specifies
  the six learned status geometries that Cadence retains below.
- [Icon Library](https://www.astrouxds.com/components/icon-library/) provides a
  useful survey of space-domain subject concepts without becoming Cadence's
  asset source.

Astro treats its six statuses as a general scale. Cadence does not. Cadence's
[operational state model](operational-state-model.md) preserves health,
availability, quality, freshness, coverage, support, workflow, urgency, and
authority as independent axes. A status symbol is an explicit presentation
decision derived from those assessments and an identified policy; it never
replaces the underlying state vector.

## Semantic pipeline

Symbology appears only at the final stage of the established semantic pipeline:

1. **Facts** describe what was observed.
2. **Assessments** interpret facts on independent state axes.
3. **Presentation policy** selects whether a status symbol is warranted and
   assigns one status role.
4. **Components** render the supplied role without deriving or escalating it.

A presentation status must retain:

| Field         | Requirement                                                                    |
| ------------- | ------------------------------------------------------------------------------ |
| `role`        | One invariant role from the status vocabulary below.                           |
| `label`       | Specific operator-facing state, such as `Telemetry stale`, not only `Caution`. |
| `subject`     | Stable identity of the affected subject.                                       |
| `axis`        | Axis or declared aggregate policy that produced the role.                      |
| `reason_code` | Stable explanation for non-normal and unknown states.                          |
| `assessed_at` | Time at which the presentation role was derived.                               |
| `policy`      | Identity and version of the policy that selected the role.                     |
| `evidence`    | Reachable underlying facts, affected members, or provenance.                   |
| `impact`      | Effect on the current task, including whether a specific action is blocked.    |

CSS classes, token names, glyph names, and component variants must not infer or
mutate these fields.

## Symbol classes

### Subject glyph

A subject glyph identifies a monitored object, capability, or operational
concept. Its geometry answers **what is this?**, not **how is it doing?**

The glyph remains stable when the subject's status changes. A spacecraft does
not become a warning triangle, and a data source does not become a red plug.
Status is composed beside the subject glyph through a status symbol.

### Monitoring symbol

A monitoring symbol is the complete compact representation of a monitored
subject. It consists of:

1. subject glyph;
2. status symbol, when a presentation status applies;
3. stable subject label; and
4. optional dynamic sub-label.

Monitoring symbols are informative and may open inspection. They must not look
like action controls merely because they are selectable.

### Status symbol

A status symbol answers **what condition currently warrants attention?** It is
an immutable pairing of geometry and semantic color. It never stands alone
when the affected subject or specific state could be ambiguous.

### Action glyph

An action glyph initiates an operation or state change. Its name describes a
verb or commitment, such as `open`, `acknowledge`, `transmit`, `abort`, or
`return to live`.

An action glyph must not be used as the persistent representation of a subject.
Destructive or consequential actions require visible text at the commitment
boundary; a glyph alone is insufficient.

### Utility glyph

A utility glyph opens a tool or configuration surface, such as search, filter,
settings, measurement, or help. It does not directly communicate monitored
status and must not borrow status color in its resting state.

### Component glyph

A component glyph describes local interface behavior, such as expand,
collapse, close, resize, reveal, or sort. It describes what will happen to the
interface, not what will happen to an operational subject.

### Notification symbol

A notification symbol communicates that events or follow-up items exist. It may
include a count and link to a log or attention center. The notification count
does not imply subject health, urgency, or acknowledgement state.

### Dedicated state glyph

Some binary concepts have a learned, single-purpose glyph pair, such as locked
and unlocked, visible and hidden, or follow-live and paused-from-live. These
glyphs remain outside the status vocabulary and must include an explicit text
label wherever a wrong interpretation could affect an action.

## Monitoring-symbol anatomy

The default composition is:

```text
+---------------------------+
| [subject glyph] [status]   |
| Stable subject label       |
| Optional dynamic sub-label|
+---------------------------+
```

- The subject glyph owns the primary visual area.
- The status symbol occupies one consistent attachment position, initially the
  lower-right corner, without obscuring identifying geometry.
- The stable label names the subject and does not change with status.
- The sub-label may show a dynamic mode, value, identifier, or evidence age.
  It must not silently replace the status label.
- Grouped monitoring symbols use one subject-glyph box, status-symbol size,
  attachment position, and label alignment.
- Dense tabular presentations may separate the subject and status into columns,
  but they retain the same glyphs, labels, and accessible name.

## Status-symbol vocabulary

The first six geometries retain Astro's learned status shapes. Their styling,
color values, borders, and rendering implementation are Cadence-owned. Cadence
adds `unknown` because unknown assessment is a first-class state and must never
collapse into nominal silence.

| Role       | Immutable geometry                 | Color intent       | Meaning in Cadence                                                                | Must not imply                                                 |
| ---------- | ---------------------------------- | ------------------ | --------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `critical` | Downward-pointing filled triangle  | Immediate / red    | Immediate response is required to avoid or limit consequential harm.              | That the subject is failed unless health evidence says so.     |
| `serious`  | Filled diamond                     | Strong attention   | Prompt intervention is required for a substantial impairment or unsafe condition. | Immediate danger, failure, or unavailability by itself.        |
| `caution`  | Filled square                      | Attention / yellow | Awareness, investigation, or monitoring is required; work may remain safe.        | Failure, urgency, or a blocked action by itself.               |
| `normal`   | Large filled circle                | Nominal / green    | Evidence positively supports the declared normal assessment.                      | Freshness, completeness, availability, or universal all-clear. |
| `standby`  | Ring                               | Signal / cyan      | The subject is intentionally available or ready but not active.                   | Degradation, uncertainty, or unavailability.                   |
| `off`      | Small filled circle                | Neutral / gray     | The subject is established as inactive, disabled, or unavailable in this context. | Failure, emergency, or an unassessed condition.                |
| `unknown`  | Outlined square with question mark | Neutral / gray     | Evidence cannot support the declared assessment.                                  | Caution, off, failure, or not applicable.                      |

`not_applicable` has no status symbol. Absence is valid only when the axis is
explicitly not applicable or when a known nominal status is intentionally
silent under the operational state model's rules.

The geometries are breaking semantic contracts. They must not be swapped,
rotated, stretched, replaced by arbitrary icons, or restyled into containers.
The `critical` triangle always points downward. The relative distinction
between the large `normal` circle and small `off` circle must remain visible at
every supported size.

## Mapping state to status

There is no automatic one-to-one mapping from most assessment values to status
roles. Presentation policy considers the affected subject, current task,
consequence, redundancy, time, and evidence.

| Assessment                                             | Allowed presentation treatment                                                                                                            |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `urgency: immediate`                                   | Maps to `critical`. This is the only unconditional status-role mapping.                                                                   |
| `urgency: attention`                                   | Maps to `caution` or `serious` according to the identified response policy.                                                               |
| `health: nominal`                                      | May map to `normal` when positive confirmation is useful; otherwise it may remain silent.                                                 |
| `health: degraded`                                     | May map to `caution` or `serious`; impact and required response decide.                                                                   |
| `health: failed`                                       | Does not automatically map to `critical`. Use `serious` or `critical` according to consequence and required response.                     |
| `availability: standby`                                | Maps to `standby` when availability is the declared status dimension.                                                                     |
| `availability: unavailable`                            | Maps to `off` only when inactive or unavailable is the intended message. Do not use `off` for unknown reachability or functional failure. |
| Quality `suspect` or freshness `stale`                 | Usually `caution`; policy may select `serious` when the current decision or action is unsafe.                                             |
| Quality, freshness, availability, or authority unknown | Maps to `unknown` when the unknown assessment must be surfaced.                                                                           |
| `authority: prohibited` or `approval_required`         | Uses action-specific authority text and a dedicated lock/prohibition glyph; it is not equipment status.                                   |
| Workflow `executing`, `completed`, or `rejected`       | Uses workflow-specific progress/result symbology unless an independently assessed operational status also applies.                        |

When a monitoring symbol needs to show more than one independent condition,
it must not stack multiple status symbols onto the subject glyph. Show the
policy-selected status at the compact level and expose axis-specific labels,
counts, and evidence in the adjacent summary or disclosure.

## Aggregation

Astro's highest-status rule is useful only inside a declared, comparable status
family. Cadence must not rank unrelated state axes into one hidden ladder.

An aggregate status symbol is allowed only when:

1. the subject set, axis, scope, time context, and policy are explicit;
2. every member was assessed or unknown members are retained;
3. the policy defines how member conditions select the aggregate role;
4. the summary includes counts for every non-empty exception;
5. the operator can reach the affected members and evidence; and
6. the accessible name states both the selected role and the summarized
   condition.

Prefer `2 sources unavailable · 1 dataset stale` with separate axis evidence
over a lone diamond labeled `System serious`.

## Color and theme behavior

- Status color is applied to the status symbol, not automatically to the entire
  subject glyph, label, panel, or row.
- Critical red is reserved for immediate response or destructive commitment.
- Serious and caution may use distinct accessible attention colors, but shape
  remains the primary invariant between them.
- Normal green is visible only when positive nominal confirmation is useful.
- Standby cyan does not mean live telemetry; the label and semantic contract
  disambiguate those concepts.
- Off and unknown use neutral treatments with distinct geometry.
- Dark and light themes preserve the same role, shape, label, and hierarchy.
- Filled status symbols render as uninterrupted silhouettes without an
  internal or external border. Strokes remain only where they constitute the
  symbol itself, including the standby ring and outlined unknown mark.
- Status-role colors must maintain non-text contrast against the local surface;
  a contrasting outline must not be used to repair an unsuitable color or
  surface pairing.
- Status colors must not be reused decoratively or as arbitrary series colors.

Exact theme values remain token-level implementation decisions and require
contrast verification against every supported surface.

## Glyph construction

Cadence subject and interface glyphs use a common construction system:

- canonical `24 × 24` view box;
- a square, optical alignment grid with a protected one-unit perimeter;
- strokes and corners consistent with the zero-radius interface language;
- no enclosing circle, lozenge, tile, or rounded container by default;
- no decorative gradients, shadows, glow, or perspective;
- fills only when silhouette recognition or established symbology requires
  them;
- sufficient differentiation at `16`, `20`, and `24` CSS pixels;
- no embedded words, abbreviations, or variable data in the subject glyph;
- directional variants only when direction is part of the meaning, such as
  transmit versus receive; and
- one canonical name and meaning for every glyph.

Curved geometry is permitted when it carries learned meaning, including the
circle and ring in the status vocabulary, orbital geometry, radio propagation,
or a celestial body. It is not a component-surface treatment.

## Starter mission glyph vocabulary

The initial vocabulary is intentionally small. It covers the subjects needed
to test monitoring, investigation, contact, telemetry, and commanding flows
without pretending to be a complete aerospace ontology.

| Canonical name             | Identifies                                    | Required distinction                                               |
| -------------------------- | --------------------------------------------- | ------------------------------------------------------------------ |
| `subject.spacecraft`       | An operated spacecraft or satellite           | Distinct from payload, ground station, and generic tracked object. |
| `subject.payload`          | Mission payload or instrument                 | Must not reuse the spacecraft silhouette.                          |
| `subject.ground-station`   | A ground site or station                      | Site identity, not an individual antenna.                          |
| `subject.antenna`          | An antenna or antenna system                  | Optional receive and transmit variants may express direction.      |
| `subject.processor`        | A processing node or flight/ground computer   | Distinct from storage and transport.                               |
| `subject.power`            | Power subsystem or service                    | Identity only; charge and health are separate evidence.            |
| `subject.thermal`          | Thermal subsystem or service                  | Identity only; temperature is not encoded into the glyph.          |
| `subject.propulsion`       | Propulsion subsystem                          | Must not imply firing or readiness.                                |
| `subject.data-source`      | A configured source of operational data       | Distinct from the data stream it supplies.                         |
| `subject.transport`        | A transport path, connector, or protocol link | Direction and availability remain separate state.                  |
| `subject.telemetry-stream` | A telemetry stream or channel family          | Distinct from archive, source, and individual parameter.           |
| `subject.command-path`     | The command delivery path                     | Must not be used as the transmit action glyph.                     |
| `subject.archive`          | Retained operational evidence                 | Distinct from live stream and generic file.                        |
| `subject.contact`          | A planned, active, or completed contact       | Contact workflow is separate from antenna or spacecraft status.    |
| `subject.event`            | An operational event or activity record       | Urgency and acknowledgement are separate symbols or labels.        |
| `subject.limit`            | A limit definition or evaluated limit subject | Directional high/low condition remains explicit text or evidence.  |

New glyphs are added from demonstrated product needs. Synonyms should alias a
canonical glyph name rather than duplicate artwork. A new visual variant
requires a new semantic distinction, not merely a different screen context.

## Labels and content

- A monitoring label identifies the subject and remains stable across state
  changes.
- A status label names the actual condition, not only the presentation role:
  `Telemetry stale`, not `Caution`.
- A sub-label may show dynamic evidence such as `18 s old`, `Receiving`, or
  `DSS-24`, but it must remain secondary and must not be the only status
  disclosure.
- Labels use sentence case unless a canonical identifier requires otherwise.
- Abbreviations require a documented domain meaning and an expanded accessible
  name where the audience cannot be assumed to know them.
- Counts identify their object: `5 unacknowledged events`, not an unexplained
  badge containing `5`.

## Accessibility

- Status is never communicated by color alone.
- Monitoring symbols include a visible stable label and a programmatic name.
- When visible text already names the status, decorative SVG paths are hidden
  from assistive technology to avoid duplicate announcements.
- When a symbol is the only compact representation, its accessible name includes
  subject, state, and material consequence.
- Status changes are announced according to urgency. Routine nominal refreshes
  do not repeatedly interrupt reading.
- Tooltips supplement labels; they never supply the only name or state.
- Light and dark status colors satisfy non-text contrast against their local
  surface without relying on a contrasting symbol border.
- Shape distinctions remain legible in monochrome, grayscale, high contrast,
  and common color-vision simulations.
- Pointer targets may be larger than the drawn glyph. Enlarging a target must
  not scale or distort the glyph itself.

## Component boundary

The first implementation proves the status vocabulary in Storybook before a
large asset package is created:

- `CStatusSymbol` renders only a supplied status role and accessible contract.
  Its operational-vocabulary story shows the six retained shapes together;
  separate stories verify supported sizes, monochrome recognition, and the
  Cadence `unknown` extension.
- `SubjectGlyph` renders a canonical subject name and optional decorative mode.
- `MonitoringSymbol` composes subject, status, label, sub-label, and inspection
  behavior.
- `NotificationSymbol` owns event count and acknowledgement presentation,
  separate from monitored status.

Names and APIs remain provisional until scenario stories prove them. Status
geometry and role meaning are not provisional. Domain-specific glyphs remain
with their owning application until repeated use justifies promotion.

The current proof keeps that boundary explicit:

- `frontend/apps/storybook/src/SubjectGlyph.vue` owns the provisional spacecraft,
  ground-station, telemetry-stream, and command-path artwork.
- `frontend/apps/storybook/src/MonitoringSymbol.vue` composes one subject with a
  `CStatusSymbol`, visible state text, observed time, and keyboard-operable
  evidence disclosure.
- `frontend/apps/storybook/src/MissionMonitoringRail.vue` provides mission scope
  and UTC context without collapsing the subject assessments into an aggregate
  health claim.
- `frontend/apps/storybook/src/monitoring-fixtures.ts` defines deterministic
  nominal, standby, caution, serious, critical, off, and unknown situations.

These application-owned components must not be exported from `@cadence/ui`
until a second real composition demonstrates the same contract. The status
geometry remains the only shared primitive in this slice.

## Verification

Every public status symbol and monitoring symbol must be tested in:

- dark and light themes;
- monochrome and grayscale;
- all supported sizes;
- every status role, including unknown and intentional status absence;
- stable and changing sub-labels;
- long labels and canonical identifiers;
- grouped, tabular, and standalone composition;
- keyboard and pointer inspection paths;
- accessible-name and live-announcement behavior; and
- aggregation with mixed, unknown, and not-applicable members.

Visual review must reject:

- a subject glyph that changes identity to communicate status;
- status color applied to a whole panel without a specific policy;
- arbitrary replacement of an invariant status shape;
- red used for off, unavailable, destructive action, and emergency without
  distinction;
- multiple status badges hiding independent axes;
- notifications presented as health status;
- icon-only consequential actions;
- unknown rendered as normal, off, or silence; and
- decorative aerospace imagery masquerading as operational symbology.

## Open decisions

The reference experience and domain contracts still need to resolve:

- exact accessible dark/light color tokens for serious, caution, normal,
  standby, off, and unknown;
- which policies distinguish `serious` from `caution`;
- the minimum assessment completeness required before `normal` may be shown;
- canonical artwork for the starter mission glyph vocabulary;
- which subject variants represent identity or mode rather than status;
- percentage-monitoring symbology and whether an arc is appropriate for each
  bounded quantity;
- notification acknowledgement and count-overflow behavior; and
- whether a dedicated asset package becomes justified after the first shared
  implementation.

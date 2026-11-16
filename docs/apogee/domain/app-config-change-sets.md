# App configuration through change sets (DECISIONS #77): plan

domain, 2026-11-13, for the director (cc lead, api, fe-setup). Status: proposed; nothing built.

The user's ruling: limits, derived telemetry and decom bindings are staged, previewed and applied
through Changes, like ground stations, transports, spacecraft and profiles
(`Cadence.Platform.ConfigKind`). This is how each works today, what a kind for it looks like, and
the decisions this needs.

## Today (read 2026-11-13)

| | Limits | Derived telemetry | Decom bindings |
|---|---|---|---|
| Written by | Limits action provider `save_limit_definition` → `Limits.Definitions.append/5` | DerivedTelemetry action provider `save_definition` → `Governance.DerivedDefinitions.append/4` | (a) legacy TelemetryDecom actions (`configure`, `PacketBindings.replace`, `disable`, `request_activation`); (b) Spacecraft Configuration drafts → review → activation |
| Concurrency | review token `{definition_id, version, activation_event_id}`; immutable version rows | `expected_version` + `expected_definition_id`; immutable version rows | `expected_review` token (a); draft token + `ConfigurationLock` (b) |
| Goes live | **immediately**, in the write transaction: lifecycle event, `limit_definition_activated` operational event, `active_limit_definitions` projection; `Facts.publish` after commit drives dashboard invalidation | **immediately**: each evaluation run snapshots the latest versions | **only via an approved activation** (binding set → `ControlActivations.execute` → runtime generation + `activation_applied` stamps) |
| Lifecycle | registered / activated only (superseded, disabled, retired exist in the enum but are never emitted) | none (no delete, no disable) | `status` not_configured / configured / applied / outdated / disabled |
| Checks | threshold order, identity bounds | `Definition.validate`, expression parse | `PacketBindings.preview`, `Review.ready/1`, CatalogAuthority, Catalog/Switch/Apid compatibility kinds |

Nothing here is reachable from the console today except through the ops-console action bridge.

## Proposal

Three kinds, built and shipped in this order (each one stage: shapes to api/fe-setup first, any
migration through qa, then the console's Changes screens gain the kind):

### 1. `derived_telemetry` (simplest: no runtime coupling)
- Entity: one derived definition (id = definition id). Ops: create, update, retire.
- `load/3`: the latest version per id. `write`: append version+1 (create = version 1); **retire** is
  new: a `retired` lifecycle row (migration: `retired_at`/`retired_by` on the definition table),
  dropped from `list_derived_definitions`.
- Concurrency: the change set's captured base replaces `expected_version` (stale → the change set's
  existing rebase/stale handling).
- `runtime_impact`: `:none` (each evaluation run snapshots definitions; the apply commits atomically).
- HOLDs (blocking): an expression references a point the mission's active catalog doesn't define;
  the output collides with a catalog point; another definition still depending on one being retired
  (or on its output) after the change set.
- Preview: the definition's parse and, cheaply, an evaluation against the latest sample (optional).

### 2. `limit_definition`
- Entity: one governed limit definition (point + limit set). Ops: create, update, retire (and
  disable/enable if the console wants it; the lifecycle already has the states).
- `write`: `Definitions.append` inside the apply transaction. **Change needed**: today append
  publishes `Facts` after its own commit; inside a change set (and in preview, which rolls back)
  that would announce changes that never commit. Append returns its facts; the kind publishes them
  in `finalize/3` after the change set commits. Retire emits the existing `retired` lifecycle and
  removes the row from `active_limit_definitions`.
- Concurrency: the change set's base replaces the review token.
- `runtime_impact`: `:none` (evaluation reads the active projection; dashboards invalidate on the
  published facts).
- HOLDs: blocking for a point not in the active catalog, or thresholds out of order (today's checks,
  as field errors); acknowledge when a retire or change affects a dashboard limit widget or an alarm
  that's currently raised on that point ("Changing Battery voltage limits clears its current Warning").

### 3. `telemetry_decom` (per spacecraft)
- What's left that's decom-specific: L22 already made catalog (profile/override), handled APIDs and
  the telemetry switch change-set fields. This kind covers the rest per spacecraft: the packet
  selection (`PacketBindings` inputs) and the telemetry source endpoint.
- `write`: the desired inputs, as `ApplicationInputs.persist` does for a draft;
  `runtime_impact: :generation`, so `ConfigurationGeneration` derives the configuration revision,
  binding set and activation exactly as it does for catalog, switch and APID changes today.
- HOLDs: the existing ApidCompatibility/CatalogCompatibility sentences apply; new: a selection naming
  packets outside the catalog (blocking), a source endpoint that isn't the spacecraft's (blocking).
- Retires the legacy direct path (a): its actions go read-only once the console Changes flow ships,
  then are deleted with the legacy pages (parity inventory).

## Decisions needed (director, with the user where noted)
1. **Direct writes after this ships.** Limits and derived telemetry go live on save today. Once
   their kinds exist, do the ops-console save actions stay (quick operational tweaks), or does every
   change go through a change set? *Recommendation: change sets only; the legacy actions go
   read-only when the console screens land, then are deleted.* This is a behaviour change for
   operators (user's call).
2. **Approval.** Change sets follow the mission's "Applying a change set" policy, so limits and
   derived telemetry would become governed (two-person where the mission says so). Intended?
   *Recommendation: yes, one policy for all configuration.*
3. **Order.** derived_telemetry → limit_definition → telemetry_decom, one at a time.
4. **Retire semantics** for derived definitions and limits: retire keeps history (versions stay for
   audit and old dashboards), like the library's Q10 rule. *Recommendation: yes.*

## Not in this plan
Alarm definitions (roadmap), WASM apps (deferred), and console screen design (ux/fe-setup), beyond
naming the HOLD sentences ux will word.

## Phase 3 scope notes (#92 phase 3 / #93; 2026-11-16)
Carried into phase 3's design, where limits and derived telemetry become change-set layers:
- **An unchanged edit is an empty change set** (lead, 11-16). Today a direct save of unchanged
  content mints the next version (both stores' `append` always does); that stays as is while the
  stores are feature-frozen (#92 phase 0). In phase 3 an edit that changes nothing stages nothing;
  ux words what the operator sees.
- **Cutover of the direct saves.** Phase 0 is a work freeze, so nothing refuses a save yet. The
  recommendation (domain, sweep row 3): refuse `save_limit_definition` / `save_definition` at their
  providers, which covers the console and the legacy host with one test, in the same batch that
  adds the change-set path, so there's never a window with no way to fix a limit (#93 (b)(c)).
  Lead and the director confirm the timing.
- **The save trail is already uniform** (row 3, 358b31d1b + 7db8b68d7 with api's W1): every
  version records `saved_by` and `via` (`console`, `legacy_host`, `change_set`), stripped from
  content comparisons. Phase 3's layers keep it.

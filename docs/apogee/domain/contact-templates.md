# Targeted contact requirement templates (DECISIONS #37)

Author: **api**. Reviewer: **domain**. Status: **approved with notes** (domain, 2026-11-09;
folded in below). **Implemented** (api); console contract in `api/scheduling.md` § Templates.

## Problem

A `ContactRequirementTemplate` targets exactly one spacecraft (`version.spacecraft_id`, NOT NULL)
and has no name. "Every Block 1 spacecraft needs one downlink every 6 h" therefore means N
identical templates that drift as the fleet changes. That's the same identical-rows problem
DECISIONS #3 fixed for routing.

## Model

A template version gains:

- `name`: text, 1–120 characters. It is versioned, so renames are audited.
- `target_document`: one of
  - `{"kind": "profile", "spacecraft_type_id": id}`: every spacecraft pinned to that profile (any
    version) **when materializing**;
  - `{"kind": "plane", "plane": n}`: spacecraft whose `metadata.plane == n`. **Interim:**
    `metadata.plane` is free-form and unvalidated until plane is first-class. So `n` must be a
    positive integer (anything else is rejected), and a spacecraft whose `metadata.plane` is
    missing or not an integer is never matched;
  - `{"kind": "spacecraft_ids", "spacecraft_ids": [id, …]}` (1–10,000, unique),

  plus an optional `"exclude_spacecraft_ids": [id, …]` for profile and plane.
- `spacecraft_id` becomes nullable and **legacy-only**. It is set only when the target is a
  one-spacecraft list, so older readers (LiveView surfaces, review projection) keep working, and is
  `NULL` otherwise.

Membership **resolves at materialization time** (it follows pins, metadata and new spacecraft),
not when the template is saved. `ContactRequirementTemplates.resolve_targets/3` →
`[spacecraft_id]` (pure over the spacecraft list, so preview and the console can count without
writing). Profile targets read `SpacecraftStore.list_pinned_to_profile/4`.

## Materialization

Today one occurrence row is generated per `(template, version, occurrence_at)`, with one generated
requirement. It becomes one row per `(template, version, occurrence_at, spacecraft_id)`:

- `contact_requirement_occurrences` gains `spacecraft_id` (NOT NULL after backfill). The identity
  unique index becomes `(org, mission, template_id, template_version, occurrence_at,
  spacecraft_id)`.
- `materialize/6` and `materialize_active/5` iterate occurrence × resolved spacecraft. Each
  generated requirement records the template id and version (as today, plus its spacecraft), so
  "superseded by template change" can name the template version.
- **Membership changes:** on each materialization, future occurrences that aren't planned yet, for
  spacecraft the template no longer targets (they left the profile, or are now excluded), are
  superseded with cause `left_template_target`; otherwise they linger. Tested.
- **New versions:** the same applies across versions. Not-yet-planned future requirements
  generated from an older template version are superseded (cause `template_versioned`) when a
  newer version materializes, so a re-seed doesn't leave the old rule active next to the new
  one (qa, 2026-11-11).
- **When superseding runs** (domain review 2026-11-09, findings 2–4, 8):
  - A fleet start (console draft or ops console) supersedes **inside its claim transaction,
    after every template has materialized**. A failed materialization rolls the cancels back, so
    a v2 that fails (for example over the cap) never cancels v1's coverage.
  - The reviewed inputs (`FleetStartInputs`) already leave out the requirements that will be
    superseded, so preview and create agree and v1 and v2 never plan the same slot.
  - Materialization in a start uses exactly the reviewed spacecraft (`targets:`), not a fresh
    resolve.
  - Outside starts (scheduler `materialize_active`), each template supersedes after its own
    materialization.
- **Taken up by a plan** means referenced by a plan in `pending_approval` or later
  (`ContactPlans.requirements_taken_up/4`). Each cancel first share-locks **every** plan that
  references the requirement, with no state filter in the query (so an in-flight submit, which
  holds its plan `FOR UPDATE`, is waited for), filters the states afterwards, and only then locks
  the requirement. **Lock order is plans, then requirements, everywhere**: the fleet start's
  claim share-locks the plans referencing generated requirements before it locks the requirements
  (re-review A, B).
- **Only what v2 replaced:** supersession cancels only requirements whose occurrence is one the
  new version just generated (the run's occurrences after its lookback and per-run cap, not its
  requested range), so no slot is left without a replacement (re-review E). Until 11-14 it used
  the requested range, so a run that generated less than its range (a short lookback, or the
  cap) cancelled days it didn't replace (qa's #86 live check). The fleet start's review and its
  claim use the same occurrences.
- **Read rule = cancel rule (U27, re-review C):** a draft reads as `superseded` by a template only
  for a future requirement of an active template that no plan has taken up. A plan that is
  `pending_approval` keeps its own requirements. The superseded check runs inside
  `ContactPlans.submit` under the plan lock, so every caller gets it: console, ops console and
  automation (D). Approval keeps its own fail-safe (`contact_plan_requirement_not_active`). List
  reads check all plans in one batch (F).
- **Decision (review 11): kept, planned requirements are not deduplicated.** If v1's requirement
  for a slot is kept because a plan took it up, v2 still generates its own requirement for the same
  slot, so that slot is demanded twice until the planned one completes. That's rare (it needs a
  template edit while a plan is pending or booked), and the planner treats them as two
  requirements. Revisit if it shows up in practice.
- **The cause** is free text in `lifecycle_reason` (`template_versioned: …`,
  `left_template_target: …`). The console doesn't filter on it; make it a field if one does.
- **Which occurrences a run generates** (lead, 11-14): those in `[effective_from, until]`,
  earliest first, at most `catch_up_policy.maximum_occurrences_per_run`, where
  `effective_from = max(from, now − maximum_lookback_seconds)`. The lookback bounds only how far
  into the PAST a catch-up reaches; the future part of the range is always in scope, up to the
  cap. (Until 11-14 it was measured back from `until`, so a horizon longer than the lookback
  generated only its last part.) Already-generated occurrences count toward the cap, so
  re-running the same range regenerates the same first ones; days past the cap come from a later
  run whose range starts past them (U52: "aren't generated by this start", never "later runs
  generate the rest"). `ContactRequirementTemplates.capped_occurrences/4` returns the
  occurrences and, when the cap cut the range, `%{limit, last_at}`.
- Bounds: a cap on spacecraft × occurrences fails the materialization with
  `{:template_fan_out_exceeded, n}` instead of silently truncating; the fleet start review
  applies the same cap summed over its templates and refuses with
  `{:fleet_planning_occurrence_limit_exceeded, count, limit}`, the whole count (U52). It's
  `:cadence, :template_fan_out_limit`, default **50,000**, sized for the 2,000-spacecraft runtime
  target × 3 contacts/day × the default 7-day horizon (42,000). Console drafts materialize one
  day. `Control.Scheduling.draft_template_estimate/3` gives the Start screen the same count for
  a day before anything runs: `{count, limit, capped: [%{template_id, limit, last_at}]}`, reading
  no requirement or occurrence rows. The count is gross (days that already exist included), so
  the words say "counts toward", never "would create".

## Migration

1. Add `name` (text) and `target_document` (map) to `contact_requirement_template_versions`.
   Make `spacecraft_id` nullable.
   The migration is irreversible (`down/0` raises): fanned-out occurrences can't fold back.
2. Backfill every existing version: `target_document = {"kind": "spacecraft_ids",
   "spacecraft_ids": [spacecraft_id]}`, `name = "<spacecraft display name> recurring"` (falling
   back to the id).
3. Add `spacecraft_id` to `contact_requirement_occurrences`, backfilled from the template version
   (all existing templates are single-spacecraft), then swap the identity unique index. The new
   unique index is built **before** the old one is dropped, in the same migration, so uniqueness
   is never missing.

Existing behavior is unchanged: a migrated template is an explicit one-spacecraft list.

## API (console CP1/CP3)

- `create/4`, `version/6` accept `name` and `target_document`, validated:
  - kind is known;
  - the profile exists in the mission;
  - the plane is a positive integer;
  - the ids exist in the mission;
  - excludes are only allowed with profile and plane, and must be mission spacecraft. An exclude
    outside the target is allowed, and preview reports it (`excluded_outside_target`).
- `preview(scope, mission, attrs, from, until)` → `{spacecraft_count, occurrences, contacts,
  warnings}`; nothing is written. Warnings: `applies_to_nobody` (count 0) and
  `excluded_outside_target`.
- Reads: list with `{id, name, target, applies_to_count, version, rule_summary}`, where the
  `rule_summary` sentence is built on the server.

## Not in scope

- Profile-level demand (templates owned by the profile document).
- Moving plane to a first-class field.
- Change sets for template edits. Templates are planning policy, not mission configuration, so
  edits are versioned and audited on the template itself rather than reviewed in a change set.
  This is a conscious choice for now (domain, 2026-11-09).

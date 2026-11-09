# Targeted contact requirement templates (DECISIONS #37)

Author: **api**. Reviewer: **domain**. Status: **design for review**.

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
  - `{"kind": "plane", "plane": n}`: spacecraft whose `metadata.plane == n` (until plane is
    first-class);
  - `{"kind": "spacecraft_ids", "spacecraft_ids": [id, …]}` (1–10,000, unique),

  plus an optional `"exclude_spacecraft_ids": [id, …]` for profile and plane.
- `spacecraft_id` becomes nullable and **legacy-only**. New versions write `target_document`
  and leave it `NULL`.

Membership **resolves at materialization time** (it follows pins, metadata and new spacecraft),
not when the template is saved. `ContactRequirementTemplates.resolve_targets/3` →
`[spacecraft_id]` (pure over the spacecraft list, so preview and the console can count without
writing).

## Materialization

Today one occurrence row is generated per `(template, version, occurrence_at)`, with one generated
requirement. It becomes one row per `(template, version, occurrence_at, spacecraft_id)`:

- `contact_requirement_occurrences` gains `spacecraft_id` (NOT NULL after backfill). The identity
  unique index becomes `(org, mission, template_id, template_version, occurrence_at,
  spacecraft_id)`.
- `materialize/6` and `materialize_active/5` iterate occurrence × resolved spacecraft. Each
  generated requirement records the template id and version (as today, plus its spacecraft), so
  "superseded by template change" can name the template version.
- Bounds: `catch_up_policy.maximum_occurrences_per_run` still limits occurrences. A new
  per-template cap of 10,000 spacecraft × occurrences per run fails the materialization with
  `{:template_fan_out_exceeded, n}` instead of silently truncating.

## Migration

1. Add `name` (text) and `target_document` (map) to `contact_requirement_template_versions`.
   Make `spacecraft_id` nullable.
2. Backfill every existing version: `target_document = {"kind": "spacecraft_ids",
   "spacecraft_ids": [spacecraft_id]}`, `name = "<spacecraft display name> recurring"` (falling
   back to the id).
3. Add `spacecraft_id` to `contact_requirement_occurrences`, backfilled from the template version
   (all existing templates are single-spacecraft), then swap the identity unique index.

Existing behavior is unchanged: a migrated template is an explicit one-spacecraft list.

## API (console CP1/CP3)

- `create/4`, `version/6` accept `name` and `target_document`, validated:
  - kind is known;
  - the profile exists in the mission;
  - the plane is a positive integer;
  - the ids exist in the mission;
  - excludes are only allowed with profile and plane.
- `preview(scope, mission, attrs, from, until)` → `{spacecraft_count, occurrences, contacts}`;
  nothing is written.
- Reads: list with `{id, name, target, applies_to_count, version, rule_summary}`, where the
  `rule_summary` sentence is built on the server.

## Not in scope

Profile-level demand (templates owned by the profile document), and moving plane to a
first-class field.

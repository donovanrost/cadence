# Approval policies per kind: design note (domain and api)

For board #201 and its sub-stories #221-#225 (DECISIONS #111). Status: DRAFT; questions 2 and 3 ruled by the director, 1, 4, 5 and 6 with the user. No build until
they're answered. The settings authz finding is #233 (M2, ahead of this build).
Breaking changes are fine (DECISIONS #112): no compatibility reads are kept for dev data.

## Today

- **One governance setting** (`cadence.governance`, a ScopedSettings section: an organization default, an
  optional mission override, and `allow_override`), with `approval_requirement` set to `direct` or
  `independent`. `ActivationPolicy.evidence/2` turns it into the recorded evidence
  (`policy: scoped_activation_approvals_v1`, `settings_token`, `approval_required`, `separation_of_duties`).
  It's read by:
  - activations (the evidence is stored on the request and checked equal at decide, preflight and apply);
  - change sets (stored on the change set at submit, checked equal at apply);
  - contact plans (whether the author or submitter may approve; whether an admin's own submit also approves);
  - model revisions (whether an importer may approve).
  Since M2, plans, plan submissions, fleet-policy approvals and model decisions record that evidence.
- **Fleet planning policies:** the author never decides, whatever the setting says.
- **Commands:** `Commanding.CommandPolicy` is CODE, not a setting (policy_version 1). A second operator's GO
  is required when any command is critical, hazardous or carries an approval hint, or when a group reaches
  10 or more targets. Routine commands need no second GO. Self-approval is refused unconditionally.
- **Provider changes** record a `policy_version` only.
- **Locks:** the governance section's lock is the policy lock, taken shared by approvals, applies and
  executes, and exclusive only by a save (`Governance.ActivationLocks`).

## Proposal

1. **One settings section, per-kind entries:** `cadence.approvals`, holding
   `kinds: %{commands, change_sets, activations, model_revisions, contact_plans, provider_changes}`
   (contact_plans covers fleet planning policies too; rulings 2 and 3). Each kind has
   `mode: one_person | independent` plus its own options. ScopedSettings already stores per-path mission
   overrides, so an organization sets each kind's default and a mission overrides only the kinds it changes.
   Keeping ONE section keeps ONE policy lock: the lock order and the shared-reader behaviour are unchanged.
2. **Commands' options** (the kind that adds its own): `second_go_for`, a list of
   `critical | hazardous | policy_hint | routine` (today: the first three), `fleet_reach_threshold`
   (today 10), and `armed_runs: one_person | independent`. CommandPolicy becomes the commands kind's
   evaluator, reading those options instead of constants.
3. **Evidence per decision:** `ApprovalPolicies.evidence(org, mission, kind)` returns
   `%{policy: "approvals_v2", kind, mode, options, settings_token}`. Every path that reads
   `ActivationPolicy.evidence` today calls it with its kind; M2's columns and documents carry it unchanged.
   Old rows keep their v1 evidence as written (no rewrite, no dual read).
4. **Self-approval is refused in every mode** (the user's rule): the actor is never one of the content's
   author, submitter, importer or requester. 'One person' then means one approver who isn't the author;
   'independent' adds whatever second-person rule the kind defines. This CHANGES today's `direct` mode, where
   the same admin may write and approve (see question 1).
5. **Migration:** a plain one: create `cadence.approvals` with each kind's mode copied from the
   organization's current `approval_requirement` (and the mission override where one exists), commands'
   options set to today's constants, then drop `cadence.governance`. No compatibility read. Under
   DECISIONS #112 it could equally start from defaults; copying is the same amount of code and surprises
   no one.

## API and console (api)

**The settings API needs no new routes.** `GET` and `PUT /missions/:m/settings` (and the organization's)
already serve registry sections with per-path mission overrides, per-field `source` and `inherited_value`,
an organization `allow_override` per section, and a per-section `version` (setup.md, Settings ST1).
`cadence.approvals` is one more registry section; `cadence.governance` leaves the registry. A breaking
change, readers first.

- **Fields** (paths inside the section; the console form renders them as it does Governance today):
  - `kinds.<kind>.mode` for each of `commands`, `change_sets`, `activations`, `model_revisions`,
    `contact_plans` (with fleet planning policies), `provider_changes`: enum `one_person` / `independent`, labelled per kind ("Change sets: one person
    approves" / "...a second person approves"), with ux's help text. Each field carries its kind as the
    form's `section`, so the console groups them by kind.
  - commands' options, using field types the console already renders (no new type): booleans
    `kinds.commands.second_go.critical`, `.hazardous`, `.policy_hint`, `.routine` (so proposal 2's
    `second_go_for` list is stored as four booleans: each is then its own overridable path); number
    `kinds.commands.fleet_reach_threshold` (1..1000); enum `kinds.commands.armed_runs`.
- **Defaults and overrides:** an organization sets every kind; a mission overrides any single path, and
  `null` hands that path back to the organization. That is exactly today's per-field behaviour.
  `allow_override` stays per SECTION (lock all kinds or none). A per-kind lock would need a new field
  shape; I'd leave it out of v1 unless the user asks (question 5).
- **Saving** goes through the same `PUT` with `expected_version`; it takes the policy lock exclusively, as
  a Governance save does today, so an approval never decides under a policy that changed mid-way.
- **Who may change it (a finding, question 6):** `manage_settings` resolves to `operate_mission`, so any
  mission operator can weaken a mission's approvals today (Governance `independent` to `direct`) unless the
  organization locks the section. The approvals section should need a stronger action than other
  settings: at least an organization admin, recorded in the settings audit with who, when, old and new
  value per path. Marked `todo(authz)` until Cedar.
- **Decisions name their policy:** every kind's approve refusal names the kind and mode in
  `details: {kind, mode}`. One code replaces today's per-kind self-approval codes
  (`self_approval_forbidden`, `command_group_self_approval_not_allowed`,
  `mission_model_self_approval_forbidden`): `approval_by_author_refused` (403), with ux's words per kind.
  `activation_policy_changed` becomes `approval_policy_changed` (409, `details.kind`) for every kind that
  checks the recorded evidence at decide or apply.
- **Reads:** the evidence each decision records is exposed with #117's decision records, not before. Until
  then, the readers that show 'needs a second person' (change sets' `viewer`, Activations, the command
  group's `second_go_required`, plan approval) keep their fields; they now come from the kind's policy.
- **Docs:** setup.md (the section and its fields, the stricter edit rule), changes.md, activations.md,
  commanding.md, scheduling.md (the codes). Readers first: fe-setup (the settings form), fe-ops (the
  approve refusals), dashboards (change sets' viewer).

## Questions for the user (before building)

1. **'One person' and self-approval:** today's `direct` lets one admin write AND approve their own plan,
   change set or model (DECISIONS #92 (a)'s single-operator path). With self-approval always refused,
   a mission can't be run by one person alone. Is that intended, or should 'one person' still allow
   self-approval while 'independent' refuses it?
2. ~~**Fleet planning policies:** their own kind, or part of contact plans?~~ RULED (director 11-18, unless the user
   objects): they fold into `contact_plans`, one planning kind.
3. ~~**Provider changes:** a sixth kind, or out of scope?~~ RULED (director 11-18, unless the user objects): their
   own kind, `provider_changes`, since credentials and provider bindings are sensitive (ties in #117).
4. **Commands:** confirm the option set, especially a second GO for ROUTINE commands and armed runs.
5. **Per-kind lock:** should an organization lock individual kinds (for example commands) while missions
   choose others, or is one lock for the whole Approvals section enough?
6. **Who may change approval policies:** organization admins only, any mission admin, or should changing
   a mission's approval policy itself need a second person?

Context: board #201, #221-#225; DECISIONS #92 (a), #107, #109, #111, #112; Governance.ActivationLocks;
Commanding.CommandPolicy; M2 policy evidence (#226).

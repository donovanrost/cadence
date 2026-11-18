# Approval policies per kind: design note (domain; api adds the API and console part)

For board #201 and its sub-stories #221-#225 (DECISIONS #111). Status: DRAFT for lead and the director.
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
   `kinds: %{commands, change_sets, activations, model_revisions, contact_plans}`. Each kind has
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

## Questions for the user (before building)

1. **'One person' and self-approval:** today's `direct` lets one admin write AND approve their own plan,
   change set or model (DECISIONS #92 (a)'s single-operator path). With self-approval always refused,
   a mission can't be run by one person alone. Is that intended, or should 'one person' still allow
   self-approval while 'independent' refuses it?
2. **Fleet planning policies:** their own kind, or part of contact plans? Today they're always 'independent'.
3. **Provider changes:** a sixth kind, or out of scope?
4. **Commands:** confirm the option set, especially a second GO for ROUTINE commands and armed runs.

Context: board #201, #221-#225; DECISIONS #92 (a), #107, #109, #111, #112; Governance.ActivationLocks;
Commanding.CommandPolicy; M2 policy evidence (#226).

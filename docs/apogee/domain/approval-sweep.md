# Approval-path sweep: who may approve their own work

domain, 2026-11-15, for the plan self-approval PR (143a016ac on domain/day-plan-lifecycle; the
director's 11-15 order: fix contact plans, then sweep every approval path the same way, bring the
rulings, and only report activations). Read from the code on the team branch. Each row was checked
at the cited place, not taken from the earlier draft sweep.

The governance setting is `cadence.governance` → `approval_requirement`:
- 'independent' is the default (`approval_required: true`), and means a second person approves;
- 'direct' means a qualified person's own action stands.

`ActivationPolicy.evidence/2` turns it into `separation_of_duties`.

| Path | Reads the setting? | Separation enforced | Where | Gap | Proposed |
|---|---|---|---|---|---|
| **Contact plans** | Yes, after 143a016ac | Under 'independent': the writer or submitter of a version can't approve it, and an admin's own Submit waits | `contact_plan_approvals.ex` `separate_approver/4`; `control/scheduling.ex` `decide/5` | Fixed in this PR (a user actor only; see automation below) | This PR |
| **Configuration change sets** | Yes (`submission.ex:47`; 'direct' applies on submit) | Under review: the reviewer is none of the authors and not the submitter (`:reviewer_is_author`) | `configuration/submission.ex:346` `independent/2` | None found | - |
| **Activations** (incl. spacecraft configuration reviews, `Review.request_many`) | Yes (`management/activations.ex:226/262`, `current_policy` at decision) | Always: the requester can't approve (`:activation_self_approval_forbidden`); a human approver is required | `management/activations.ex:530` `distinct_approver/2` | None found. Report only, no change (director's order). | - |
| **Command requests** | No: their own classification policy (hazardous/critical, approval hints, fleet reach) decides whether approval is needed | When approval is needed: always, the requester can't approve | `commanding/lifecycle_policy.ex:48`, `request_store.ex:117` | Not a gap if commands are deliberately outside the governance setting | **Ruling A** |
| **Command groups** | No (as above) | When a second GO is needed: the submitter can't decide. Members needing no second GO are auto-approved by policy (`group_submission.ex:198`) | `control/commanding/group_decision.ex:86` | As above | **Ruling A** |
| **Fleet planning policies** | No | Always, but only in the control wrapper: the reviewer must not be the version's author (stricter than 'direct') | `control/planning_policy.ex:118` `not_author`; the domain `FleetPlanningPolicies.approve/7` has no check | The domain function relies on its single caller. A second caller would bypass it. | Move `not_author` into the domain function (small, no behaviour change). Ruling B on following the setting. |
| **Automation grants** | No | None. One admin issues a grant (`automation_grants.ex:20`, `authorize_admin`) whose allowed actions can include `:submit` **and** `:approve` plans | `contact_planning/automation_grants.ex`; used at `contact_plan_approvals.ex:584` | Under 'independent', one admin can authorize a service to submit and approve plans: separation by proxy. `separate_approver/4` checks user actors only. | **Ruling C** |
| **Mission-model revision decisions** | No | None, and no authorization at all: `RevisionDecisions.approve/5` takes a bare actor map | `mission_models/revision_decisions.ex:18` via `MissionModels.approve_revision/5` | Dormant: no caller in `cadence` or `cadence_web` lib | Mark `# todo(authz):` now; scope and separation before anything calls it |
| **The governance setting itself** | - | None. One admin with `:manage_settings` can switch 'independent' → 'direct', then approve their own work | `governance/activation_policy.ex:40` | Relaxing the requirement needs no second person (saves are recorded with the actor by `ScopedSettings`) | **Ruling D** |

## Rulings for the director

- **A. Commands vs the governance setting.** Command approval follows its own classification
  policy and always enforces no-self-approval when approval is needed. Should 'direct' and
  'independent' govern commands too, or stay separate by design?
  - My read: keep them separate. Commanding safety is per command, not per mission setting.
  - Say so in the policy text, so an admin who chooses 'direct' isn't surprised.
- **B. Fleet planning policies.** They always require a non-author approver, even under 'direct'.
  Should they follow the setting, as plans now do?
  - My lean: follow the setting for consistency.
  - Either way, move the check into the domain function.
- **C. Automation grants under 'independent'.** Options:
  1. A grant that allows both `:submit` and `:approve` needs a second admin to issue it.
  2. Under 'independent', a grant can't include both actions.
  3. Accept it as delegated authority and show it in the plan's audit.

  My lean: (1). The grant is the decision that replaces every later approval, so it gets the
  second person.
- **D. Relaxing the setting.** Should switching 'independent' → 'direct' (mission or organization
  level) need a second admin? Tightening it wouldn't.
  - My lean: yes, since otherwise every other row is one click from void.
  - At minimum, the switch should appear in the audit feed where approvers look.

The mission-model `# todo(authz):` and the fleet-policy check move are small and need no ruling; I
can add them to this PR on the director's go.

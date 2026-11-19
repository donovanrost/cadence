TITLE: Issuing an automation grant needs a second person's approval under the independent setting

TYPE: story. PARENT: #207. LABELS: type:story, domain:approvals, domain:contacts, domain:identity,
component:management-plane, component:api, component:console. MILESTONE: lead's call (slot right after #280).

As an organization admin, I want an automation grant to take effect only after a second admin approves it when
the mission's approval setting is independent, so that one person can't hand a service the power to submit and
approve work that would otherwise need two people.

**Acceptance criteria**
- [ ] Who: proposing and approving a grant both stay organization-admin only (today's :manage_automation_grants)
      and person-only. A service holding organization_admin is refused explicitly (the capability check doesn't
      look at actor kind). Widening to mission admins is out of scope (open question 2).
- [ ] Issuing a grant creates it as proposed. It authorizes nothing until it's approved: planning, submit and
      approve under it are refused while it's proposed, with a clear refusal.
- [ ] Under independent, the grant's approver is a different person from its proposer, and outside the
      accountable people of the service it names (#280's set). Overlap is refused; an unknown set fails closed.
- [ ] Under direct, the proposer's own approval stands, as for other kinds (no new refusal under direct).
- [ ] Checked at use: every submit or approve under a grant re-reads the grant's status in the same transaction,
      and refuses unless it's approved and within its validity.
- [ ] Validity starts at approval, not at proposal. A proposal that's never decided expires.
- [ ] Revoking or narrowing a grant is a tightening: any eligible admin does it alone, at once, with no proposal.
      Test: revoke works while another change to the same grant is still proposed, so the two-person rule can
      never block switching automation off.
- [ ] Widening a grant (more actions, more services, longer validity) makes a new proposal that needs approval
      again.
- [ ] The decision records the mission's approval policy in force, as other decisions do (M2 evidence), and is
      re-checked if the policy changed between proposal and approval.
- [ ] Rejecting a proposed grant needs a reason; a rejected proposal can't be approved later.
- [ ] The grant's proposer and approver both count in #280's approving set for any plan the service approves.
- [ ] Grants issued before this change: the dev reset recreates them (DECISIONS #112); no backfill or shim.
- [ ] The console offers Approve / Reject only to an eligible viewer, from the server's flags (as #233 does with
      allowed_values), never computed client-side. An ineligible viewer sees why, in ux's words.
- [ ] Refusals record nothing. A grant's audit shows proposal, decision, revoke and narrowing, with who and when.
- [ ] Verified live on the dev stack.

**Open questions (director)**
1. Policy tightened later: a grant approved by one person under direct keeps authorizing after the mission moves
   to independent. Should it stop until a second approval (ca-security's lean), or is that accepted?
2. Should proposing or approving widen to mission admins? Today it's organization admins only.

Context: Built by: mms-security. Reviewers: ca-security (sole security reviewer; the builder never reviews their own
PR), api-ops (Commanding & Approvals), mms-engineer (Mission Model & Spacecraft), and Ground & Comms (fe-ops' squad:
the grant code, contact_planning and Control.PlanningGrants, is theirs). Words by ux/mms-ux. Slot: right after #280
(lead, 11-19), built on #280's accountable set. Director 11-19 (via api-ops), new requirement raised in #280's
review; approval-sweep Ruling C (option 1); AutomationGrants.issue, Control.PlanningGrants,
contact_grant_controller; docs/apogee/domain/mms-threat-model.md (MM-1); DECISIONS #112.

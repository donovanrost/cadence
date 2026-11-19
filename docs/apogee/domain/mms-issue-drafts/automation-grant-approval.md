TITLE: Issuing an automation grant needs a second person's approval under the independent setting

TYPE: story. PARENT: #207. LABELS: type:story, domain:approvals, domain:contacts, domain:identity,
component:management-plane, component:api, component:console. MILESTONE: lead's call (slot after #280).
REQUIRED REVIEWERS: ca-security (security; mms-security builds it, so doesn't review its own PR); api-ops
(Commanding & Approvals); an MMS squad reviewer other than the builder; ux/mms-ux (words).

As a mission admin, I want an automation grant to take effect only after a second admin approves it when the
mission's approval setting is independent, so that one person can't hand a service the power to submit and
approve work that would otherwise need two people.

**Acceptance criteria**
- [ ] Issuing a grant creates it as proposed. It authorizes nothing until it's approved (planning, submit and
      approve under it are refused while it's proposed, with a clear refusal).
- [ ] Under independent, the grant's approver is a different person from its proposer, and outside the
      accountable people of the service it names (#280's set). Overlap is refused; an unknown set fails closed.
- [ ] Under direct, the proposer's own approval stands, as for other kinds (no new refusal under direct).
- [ ] The decision records the mission's approval policy in force, as other decisions do (M2 evidence), and is
      re-checked if the policy changed between proposal and approval.
- [ ] Rejecting a proposed grant needs a reason; a rejected grant can't be approved later.
- [ ] Changing a grant's allowed actions, services or validity makes a new proposal that needs approval again.
- [ ] The grant's proposer and approver both count in #280's approving set for any plan the service approves.
- [ ] Grants issued before this change: the dev reset recreates them (DECISIONS #112); no backfill or shim.
- [ ] The console shows a proposed grant, who proposed it, and an Approve / Reject for an eligible admin, with
      ux's words; an ineligible viewer sees why.
- [ ] Refusals record nothing; a grant's audit shows proposal and decision with who and when.
- [ ] Verified live on the dev stack.

Context: Built by: mms-security. Required reviewers: ca-security (security) and api-ops; words by ux/mms-ux. Slot: right
after #280 (lead, 11-19), built on #280's accountable set. Director 11-19 (via api-ops), new requirement raised in #280's review; approval-sweep Ruling C (option 1:
a grant that allows both submit and approve needs a second admin); AutomationGrants.issue, Control.PlanningGrants,
contact_grant_controller; docs/apogee/domain/mms-threat-model.md (MM-1); DECISIONS #112.

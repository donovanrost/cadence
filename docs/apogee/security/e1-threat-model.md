# Threat model: E1 #207, "Approvals that two people really made" (ca-security, draft 2026-11-19)

**The promise:** under 'independent', every recorded approval was made by an authenticated person who
didn't author or submit the thing approved. That person's organization and mission allow it. The
record says so, permanently and truthfully. Reviewers check PRs against `review-checklist.md`; this page
says which threats that list exists for, and where each stands. The per-path facts are in
`docs/apogee/domain/approval-sweep.md`.

**Assets:** the decision records (approvals, four-eyes records, settings revisions and their audit);
the approval setting (`cadence.governance`) and the per-kind policies (#201); the accountable people
behind every actor, persons and service identities.
**Actors:** operator, mission admin, organization admin, platform admin (in admin mode), service
identity (acting under its capabilities or an automation grant), the system/seed actor.
**Trust boundaries:** browser console ↔ API (session + CSRF); pre-console REST ↔ API (bearer: person or
service); organization ↔ organization; mission ↔ mission; request ↔ the transaction that records it.

## Threats

| # | Threat | Control today | Status |
|---|---|---|---|
| T1 | **Self-approval on some path.** The console and pre-console REST check separation differently, so the weakest path sets the real rule. | Each path's own check (sweep table). | Open: #260 (re-approve skips separation), #263 (REST reports a refusal after recording). Contact plans: #277 (an earlier author approves after someone else cuts a version). |
| T2 | **Separation by proxy.** A person acts through a service identity they issued or hold, then approves the result. The same applies to an automation grant that allows both submit and approve. | Human-approver rules on most kinds; contact plans allow a service approval under a grant. | #280 (director 11-19): the accountable set is the issuer plus every rotator; an approver in it is refused, wherever a second GO is needed; an unknown set fails closed. Includes REST command requests, where the self check compares user ids only. Grant approvals count the grant's approver; issuing a grant needs a separate approver (ruling 3, #283). The seed actor is MM-2. |
| T3 | **An unknown author passes.** A check that can't find the author, or finds no person, allows. | #236 fails closed (`activation_approver_authors_unknown`). | Open wherever a nil requester passes (#280). Rule: an unknown author refuses. |
| T4 | **Refused, but written.** A refusal after a write, or an "approved" answer or event for a transaction that rolled back. | Contact plans: one transaction, operation row written only on success (#257). | Open: #263 (REST approve), #261 (a lost connection answers 200 for another person's decision), #262 (500 on a blocked approve), #278 (contact-plan approve publishes inside the transaction). |
| T5 | **The record changes or is incomplete.** A decision row is updated or deleted, or a path writes no four-eyes record, or the record doesn't state the policy in force. | Approval rows are inserted; the policy is recorded on contact plans (#226(b)). | #116 (immutable), #117 (every path writes a complete record), #226 (the policy in force), #227/#228/#239 (shown in history and audits, with admin mode). |
| T6 | **The wrong person loosens the policy.** Anyone below organization admin loosens the setting, by any route: a mission value, the organization default, or clearing an override. | #233: org admin only, decided on the effective value, under the section lock, audited. | Closes on #233's merge. #201/#221-#225 must keep the rule per kind, with unknown values counting as strictest (#233 N1). |
| T7 | **Client-supplied actor or identity.** A body names `requested_by`/`decided_by`, or identity metadata names a creator. | 422 `actor_not_assignable` on REST commanding (DECISIONS #30, #32). | Service identities: #281 removes the REST service-identity endpoints (GET and POST `/api/organizations/:org/service_identities`), and with them the client-supplied `metadata` path. The issuer and rotators are recorded server-side (#280). |
| T8 | **Crossing tenants.** One organization or mission reads or decides another's records, through an id, a dedup key or an `on_conflict` re-read. | MissionScope / ControlPlaneAccess; org and mission in queries and unique indexes (e.g. `contact_plan_operations`). | Check per PR (checklist 7). Offboarding (#220) needs an audited purge that keeps the evidence it must keep; #118 is parked. |
| T9 | **Approving content that isn't what was reviewed.** The content changes between the reviewer's read and the decision. | Expected version + content hash; versions are immutable snapshots. | Holds while versions stay immutable. If a version row ever becomes mutable, the client must send the hash it saw. |
| T10 | **Replays and idempotency.** A retry returns someone else's answer, or skips authorization. | Replays keyed by org, mission and op id; matched on actor, action, plan and digest. | #278: authorize before replaying. |
| T11 | **Routing around controls in ops.** Scripted approvals, minted tokens or seed approvals write false records. | TEAM.md Controls; #250 (seeds never approve). | Procedure + #250. The seed actor's accountability is MM-2. |
| T12 | **Service identities issue service identities.** A service holding organization admin issues or rotates other services (organization admins included). Credentials then outlive revoking the one that made them. | `:manage_service_identities` checks the capability, not the actor kind. | #281: issue, rotate, revoke and list are person-only, and the actor holds every capability the identity has. The REST service-identity endpoints are removed, leaving the console as the only issuer. #282: organization-level actions are person-only by default. |

## Order (lead, 11-19, updated)
#233 → #280 → #281 → #283 → #250/#231 → #277 → #263 → #278 → #260-#262 → #282. #284 (mission-level
access) is parked until Cedar. The epic is done when T1-T7, T10 and T12 are closed
and each has a test that fails without its fix.

## Director rulings (11-19, on #280)
1. The accountable set applies wherever a kind needs a second person's GO (command group GO, arming,
   release), not only approve.
2. Services keep approving under an automation grant. The grant's approver counts in the approving set,
   and an overlap with the authors is refused.
3. Issuing an automation grant is itself a decision under the mission's policy, with its own separate
   approver: #283, right after #281.

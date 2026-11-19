TITLE: An admin can approve their own work when it was done through a service identity they issued

TYPE: bug. PARENT: #207. LABELS: type:bug, domain:approvals, domain:identity, domain:mission-model,
component:management-plane, component:api, component:console. MILESTONE: lead's call (placed right after #233).
REQUIRED REVIEWERS: ca-security, mms-security.

**What happens**
Under the 'independent' approval setting, a second person must approve work. Work done through a service
identity counts no person as its author. Service identities don't record who issued them or who rotated
their credential. So an organization admin who issues a service identity, or holds its credential, can
author work through it and then approve that same work as if someone else had done it. For mission-model
revisions, a revision with no recorded person importer can be approved by any admin.

**What should happen**
A service identity's act counts as the act of everyone accountable for it: the person who issued it and
every person who rotated or was handed its credential. Under 'independent', an approver in that set is
refused, for every approval kind. Where the set isn't known (identities from before this change), approval
fails closed until an org admin records the accountable people. That recording is audited, and the admin
who records it joins the set. Automated planning and CI imports keep working when someone outside the set
approves.

**Acceptance criteria**
- [ ] An impact list per approval kind (model revisions, spacecraft-configuration and other activations,
      configuration change sets, contact plans incl. fleet planning policies, provider changes, commands)
      is reviewed by ca-security and mms-security BEFORE the build starts.
- [ ] Issuing a service identity records the issuing person; every credential rotation or hand-over
      records its actor. Both appear in the organization audit. They're stored in server-built fields in
      the same transaction, on every issue path (console, organization console, REST), and never read from
      client-supplied identity metadata (a request that sets them is refused with actor_not_assignable).
- [ ] For every kind, under 'independent', the author set expands each service author to its accountable
      people, and an approver in that set is refused with the kind's existing self-approval refusal.
      Nothing is recorded on refusal.
- [ ] A service issued or rotated by a service inherits that service's accountable people; an unknown link
      anywhere in the chain makes the set unknown.
- [ ] A service may approve only where a kind already allows it (an automation grant). Its approving set is
      its accountable people plus the grant's approver, and it's refused when that set meets the author set.
- [ ] A service author whose accountable people aren't recorded makes approval fail closed with a distinct
      refusal (like #236's activation_approver_authors_unknown), and the console says why.
- [ ] An org admin can record the accountable people for an identity that has none on record. The action
      is audited, and that admin joins the set (test: they can't then approve that identity's work).
- [ ] Automated planning and a CI catalog import proceed when an approver outside the set approves (test).
- [ ] No backfill script and no dev-data shim; the dev reset recreates the identities.
- [ ] Verified live on the dev stack.

**Impact**
Without this, one admin can satisfy a two-person rule alone by acting through a service identity, which
voids the separation the 'independent' setting promises.

Context: director decision 11-19 (relayed by api-ops); same class as approval-sweep Ruling C; checklist item
C5 (ca-security); MM-1 in docs/apogee/domain/mms-threat-model.md; DECISIONS #92 (a), #112, #236. Seed
(system-actor) authorship is tracked separately (MM-2) and is out of this issue's scope.

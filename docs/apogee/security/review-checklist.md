# Security review checklist (security lead, draft 2026-11-18)

What a squad security engineer checks on a PR that touches permissions, approvals, secrets, the
network or tenant boundaries (squads charter). Every squad's security engineer applies the same list.
Each item has a short reason. Cite the code path and the condition for every finding, not a summary.

## How to record a review

- Post it with `gh pr review N --comment`. The body starts `[agent-name] VERDICT: APPROVE` (or
  `REQUEST CHANGES`), then the **full head SHA you read**.
  *Why:* the team shares one GitHub account, so GitHub can't tell reviewers apart. The body line is
  the only record of who reviewed, and the SHA ties it to the code.
- Say what you read, what you ran and what you didn't.
  *Why:* a reader has to be able to tell a checked claim from a trusted one.
- A push after your review voids it for the new commits. Re-review them, or say they're out of your scope.
- Never review your own work.

## The checks

### 1. The actor comes only from the authenticated scope
The person or service acting is taken from `current_scope`, never from the body, query or a header.
A request that names an actor gets 422 `actor_not_assignable` (DECISIONS #30, #32;
`docs/apogee/api/security-actor-sweep.md`).
*Why:* a client-named actor lets anyone act, approve or be recorded under someone else's name.

### 2. Authorization runs first, and runs on the server
Check the capability before any lookup whose answer differs by outcome (idempotency keys, version
checks, "already done" refusals), and before any write. Replays of stored answers are authorized
too.
*Why:* checks that run before authorization answer questions for people who aren't allowed to ask
them, and a replay that skips authorization outlives a revoked role.

### 3. Fail closed when a rule can't be evaluated
Unknown actor, missing policy, an author lookup that fails, an unexpected value: refuse with a
named reason. Never fall back to allow. Mark a known gap with `# todo(authz):` and add it to
`docs/apogee/authz-inventory.md`.
*Why:* a check that silently passes when its input is missing is no check at all.

### 4. Refuse before writing; a refusal leaves nothing behind
Every refusal happens before the first write, or rolls the whole transaction back. That includes
side records (audit, operation/idempotency rows) and **announcements**: publishes, broadcasts and
jobs are scheduled only after commit.
*Why:* a recorded approval that the API calls refused (#263), or an "approved" event for a
rolled-back approval, makes the record lie.

### 5. Separation of duties covers every author
Under 'independent', the approver is none of: the submitter, or anyone who authored content between
the last approved (active) version and the version under review. A server-side copy of a version
("cut") must not erase the earlier authors (#236).
A service identity's act counts as the act of every person accountable for it: whoever issued it
and whoever rotated or received its credential. If that set isn't recorded, the author is
unknown, and under 'independent' an unknown author fails closed, so nobody may approve until a
person is on record (separation by proxy; approval-sweep Ruling C). *Pending the director's OK.*
*Why:* checking only the latest author lets a person approve their own content once someone else
touches it, and a service identity the approver controls is the approver.

### 6. Only an organization admin may loosen an approval control
Compare the **effective** value before and after the save, not just the submitted value: an
organization default, a cleared override or a changed inheritance can loosen it as well (#233).
Tightening may be wider.
*Why:* every four-eyes control in the product rests on this one setting.

### 7. Tenant scoping is server-side on every read and write
Every query, unique index, idempotency key and dedup key includes the organization (and mission
where relevant), taken from the scope, not the URL alone. A row found under another tenant is
"not found", never its content. With `on_conflict: :nothing`, re-read the winning row and check its
tenant before using it.
*Why:* a global key with a tenant-blind re-read hands one tenant another tenant's row.

### 8. Decision records are append-only and complete
Approval and four-eyes records are inserted, never updated or deleted (#116). They carry the actor,
the time, the version and hash decided, and the policy in force (#226). Every approval path writes
one (#117).
*Why:* the record is the evidence that two people really decided.

### 9. Every path to the same action is held to the same rules
Console, pre-console REST, LiveView, Mix tasks and seeds: list them, and check the PR's rule on each.
*Why:* the paths drift apart (#260, #263). The weakest one sets the real rule.

### 10. Stored hashes and digests stay stable
Changing a struct or a digest layout that feeds a stored hash follows DECISIONS #108 (stable hash +
legacy-value test, or a director plan). A canonical-JSON digest carries a layout version.
*Why:* a silently changed hash invalidates every stored approval or replay key.

### 11. Nothing secret on GitHub; no exploit steps in public
No email address, password, token, cookie or private key in a branch, commit, PR body, comment or
fixture. Issues describe the class of the problem and the fix. Reproduction steps that would
work against a deployment go to the squad lead and the director over herdr.
*Why:* the repository is public.

### 12. Errors and details don't leak more than the caller may read
Problem `details` and refusal messages contain only what the caller can already read. Name people
by display name, never fall back to an email address.
*Why:* refusals are an easy place to leak identities or other tenants' state.

### 13. No route around a control, even in tests or QA
No scripted approvals under a person's name, no tokens minted outside the product path, no node
calls that write decision records (TEAM.md, Controls). Test fixtures that need an approval go
through the real path or are clearly fixtures in the test database.
*Why:* a false record in dev looks just like a real one in the audit.

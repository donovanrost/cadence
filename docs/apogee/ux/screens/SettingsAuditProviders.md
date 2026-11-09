# Settings, Audit log, Provider accounts (Setup › Mission settings + Organization)

No boards: these are built from existing components. **Reading layout**, Setup rail. Owner:
fe-setup (endpoints: api). They're quiet admin pages, so the goal is honest, compact and consistent
with Profile/People.

---

## Settings (mission `M/setup/settings[/:section]`, org `O/org/settings[/:section]`)
**Question:** "How is this mission (or org) governed and configured?"
- **Sections come from the server's settings registry** (today `cadence.governance` is the default
  section, and apps contribute others). The UI never hard-codes the section list or its fields. Left
  local nav (as on Profile) lists the sections with a mono key in Technical details; the default
  section opens first.
- **Section panel:** title + one-sentence purpose, then fields generated from the section schema
  (label, type, unit, enum, default, help, `effective` vs `set here`). Each field shows where its value
  comes from: `SET FOR THIS MISSION`, `INHERITED FROM ORG`, or `DEFAULT`. Inherited values render in
  `text-4` with `Override` / `Reset to inherited` (the Profile override pattern).
- **Saving:** settings that are change-set kinds (when domain adds them) stage (`Stage change`);
  everything else saves immediately with a version line (`v4 · 01:12Z by Donovan R.`). Governance
  changes that need approval follow the server's policy (ApDecision, reviewer ≠ author). Errors follow U20.
- **Read-only** without the capability: values as text plus "Org admins change settings."
- **Empty section** (an app with no settings): don't list it.

## Audit log (`O/org/audit`, linked from Readiness R2 and revisions)
**Question:** "Who changed what, when, and why?"
```
lbl "REFLECT ORBITAL · AUDIT LOG"   h1 "Last 7 days"        range: ApTimeRange (presets 24h · 7d · 30d)
filters: actor (select) · mission (select) · kind chips (Config · Commanding · Access · Alarms · Contacts · Data)
┌ L1 Audit table (scrolls) ───────────────────────────────────────────────────────────────┐
```
- **Row:** time (mono, `11-09 01:12:07Z`) · actor (name; service identities in mono with a `SERVICE`
  tag) · action in words ("Applied r6 · 2 changes", "Approved REQ-0419", "Invited ana@…",
  "Acknowledged VBAT on EARENDIL-001") · target (link) · mission · why (reason / note, `text-3`).
  Identical consecutive actions group (Timeline rule). Name link → the object's page.
- **Source honesty:** a unified audit read doesn't exist yet (plans/setup.md). Until api unifies
  `OperationalEvents` + config revisions + command/alarm actions + access events, show the sources
  that exist and say which are missing: info callout "Showing configuration, commanding and access
  events. Contact and data-source events aren't in the audit log yet." Never imply completeness.
- **Export:** `Export CSV` for the current filter (secondary).
- Empty range: "No audited actions between 11-02 and 11-09."

## Provider accounts (`O/org/provider-accounts[/:accountId]`, org admins)
**Question:** "Which ground-network providers can this org book, and are the credentials healthy?"
- **List** (ApTable): Provider (display name + mono provider type) · Account name · Status tag
  (`■ CONNECTED` / `▲ CREDENTIALS EXPIRING · 6 days` / `◆ AUTH FAILED` / hatched `NOT CHECKED`) ·
  Missions using it (count, link) · Last successful call (`T+04:12`) · Added (by, when). Primary `Add
  provider account`.
- **Add / detail:** provider select (from the server's adapter registry: `provider_adapters`), account
  name, credential fields **generated from the adapter's schema** (secret fields write-only: shown as
  `•••• set 11-02` with `Replace`; never echo a secret), environment (sandbox/production if the adapter
  has it). `Test connection` (secondary) reports the real result with the provider's message. Save is
  only enabled after the required fields are filled. Missions panel: which missions use this account
  (link to Setup › Ground stations › Providers).
- **Removal:** `Remove account` (danger) is blocked with a reason while missions use it ("Used by 2
  missions. Unlink it from them first.").
- Health is real only: if the server doesn't check credentials, the status is `NOT CHECKED` (hatched),
  not connected.

## Acceptance (for qa)
- No hard-coded settings sections or fields; inheritance source is shown on every field.
- The audit log says which sources are missing until it's unified.
- Secrets are never echoed back; provider status is never green without a real check.

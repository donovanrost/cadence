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
  (label, type, unit, enum, default, help, `effective` vs `set here`).
- **Override is per section for now** (fe-setup's code read, 11-13). Today a mission override stores the whole
  section, so per-field Override and Reset can't be done truthfully (U20).
  - **Header tag:** the section header carries the source: `SET FOR THIS MISSION`, `INHERITED FROM ORG`, or
    `DEFAULT`. Fields carry no tag of their own.
  - **Inherited section:** values render in `text-4`, read-only, with the compact `Override for this mission`.
    It opens the fields for editing under an info line: "Overriding copies all of this section's organization
    values to Earendil. They stop following organization changes until you go back to the organization's
    settings." Saving stores the override.
  - **Overridden section:** the fields are editable. `Use the organization's settings` confirms first: "Earendil
    will use Acme Space's <Section> settings. This mission's own values for it are discarded." It saves
    immediately with the version line.
  - **Org lock:** `allow_override` false keeps the section locked, as built.
  - **Per field, chosen** (lead asked, 11-13; api has capacity). Once api stores only the overridden paths, each
    field gets its own source tag and `Override` / `Reset to inherited` (the Profile override pattern), and the
    section-level controls go. Why:
    - A section copy silently freezes every other field in the section. They stop following the organization,
      and nobody chose that.
    - Per-field matches how profile overrides already work, so there's one model for "inherited unless
      overridden".
    - The section-level UI stays until then. Migration keeps only the fields that differ from the organization's
      value at that moment; the rest inherit again. Record that as one audit entry per mission: "Settings now
      follow the organization except the fields set for this mission."
    - **Built** (fe-setup 424a17138, api 14455857d). Buttons: `Override` (inherited), `Change` and `Reset to
      inherited` (set here). Reset saves at once, with an outcome line that keeps the old value, so it can be
      put back: "Command shelf follows the organization again (was Minimized). Saved as v5." Governance and
      approval fields confirm first: "Approval for changes and app activations will follow Acme Space: Applies
      without approval."
    - The section header no longer carries a source tag. Fields carry their own. The header shows a count when
      any field is set here: `2 SET FOR THIS MISSION`.
    - Director's condition: governance and approval fields always stay set for the mission, even when they equal
      the organization's value. Where the migration kept one that matches, the entry adds: "Approval settings
      stay set for this mission, even where they match the organization." They show `SET FOR THIS MISSION`
      afterwards, as any override does.
- **Percent fields** (unit `ratio`, shown as %; qa typed 0.9 meaning 90%). The console catches the
  fraction-for-percent slip inline, with no dialog and no server floor (nobody knows a real one):
  - When the typed value is above 0 and at most 1, a caution hint shows under the field as the user types: "That's
    0.9%. Did you mean 90%?" with the compact button `Use 90%`.
  - Save stays enabled, so a real 0.9% can still be saved. It applies to every ratio field from the schema, not
    a list.
  - The hint goes once the value is above 1, or once `Use 90%` is pressed.
- **Saving:** settings that are change-set kinds (when domain adds them) stage (`Stage change`);
  everything else saves immediately with a version line (`v4 · 01:12Z by Mira K.`). Governance
  changes that need approval follow the server's policy (ApDecision, reviewer ≠ author). Errors follow U20.
- **Governance section** (`cadence.governance`, lead's ask 11-13). Its one setting gates both change-set applies
  and app activations (L10), so the words name both:
  - Section text: "Who has to agree before configuration changes and app activations take effect."
  - Field `approval_requirement`, label `Approval for changes and app activations`.
  - Options: `direct` `Applies without approval` · `independent` `Needs a second person's approval`.
  - Help: "Covers change sets in Setup › Changes, spacecraft configuration reviews, and app settings that need
    activation, such as decom. App settings that save immediately, such as limits, aren't covered." (fe-setup
    found the third reader.)
  - Saving `Needs a second person's approval` can first list the automation grants it would suspend (#499): words
    and behaviour in U105 "Suspended", "The settings save that suspends".
- **Read-only** without the capability: values as text plus "Org admins change settings."
- **Empty section** (an app with no settings): don't list it.

## Audit log (`O/org/audit`, linked from Readiness R2 and revisions)
**Question:** "Who changed what, when, and why?"
```
lbl "REFLECT ORBITAL · AUDIT LOG"   h1 "Last 7 days"        range: ApTimeRange (presets 24h · 7d · 30d)
filters: actor (select) · mission (select) · kind as a one-of segmented control (`All` · Config · Commanding · Access · Alarms · Contacts · Data, plus kinds the server adds, e.g. Account; `All` first and the default). It's single-choice, with no multi-select chip. Past 8 kinds, or under 1100px, it becomes a `Kind` select
┌ L1 Audit table (scrolls) ───────────────────────────────────────────────────────────────┐
```
- **Row:** time (mono, `11-09 01:12:07Z`) · actor (name; service identities in mono with a `SERVICE`
  tag) · action in words ("Applied r6 · 2 changes", "Gave GO on SET_MODE and 2 more for 12 spacecraft", "Invited ana@…",
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
  (`■ CONNECTED` only when the provider was actually contacted / `REFERENCE OK · PROVIDER NOT CONTACTED` neutral, only when there has never been a successful call; with one, `REFERENCE OK` and the last-call column says when / `▲ REFERENCE MISSING` / `◆ AUTH FAILED` / hatched `NOT CHECKED`) ·
  Missions using it (count, link) · Last successful call (`T+04:12`) · Added (by, when). Primary `Add
  provider account`.
- **Add / detail (revised per api's design note: Cadence never receives secret values):** fields from the
  adapter schema (`GET /provider-adapters/:key/schema`): provider (adapter select), account name, base
  URL, environment, region (optional). **Credential** is a *reference*, never a secret:
  - `Where the secret lives`: choice segmented `Secret manager` / `Environment variable` (the latter tagged
    `DEV ONLY` in caution; refuse or warn on production environments if the server says so).
  - `Reference` (mono input): placeholder `providers/reflect-orbital/northlight-prod` (secret manager) or
    `NORTHLIGHT_API_KEY` (env). Help: "Cadence reads the secret from there when it calls the provider. The
    secret itself is never sent to or stored in Cadence."
  - No masked "•••• set" field and no password input anywhere on this page.
  `Test reference` (secondary; renamed from Test connection while that's all it does) reports exactly what
  was checked (api returns `checked`, `failed`, reason code, message): today only the reference is checked,
  so success reads "Reference found · the provider wasn't contacted (provider sign-in checks aren't
  available yet)", and failure reads the server's message ("Reference not found in the secret manager").
  Never "Connected" unless `checked` includes the provider. Environment-variable references where local
  credentials aren't enabled show the server's validation error under the backend choice
  (`details['credential.backend']`). Save is enabled when the required fields are filled; an
  untested account saves with status `NOT CHECKED`.
  **Editing** saves a new version (`v2`); changing the reference is just a new reference value. History
  lists versions with who/when and the reference (not secret) used. Missions panel: which missions use
  this account (link to Setup › Ground stations › Providers).
- **Removal:** not available yet (no account retirement in the domain). Hide `Remove`, and say "Accounts
  can't be removed yet." in the detail's Technical details, rather than a disabled dead button.
- **Mission provider detail, `Account grant` row** (Setup › Ground stations › Providers, L12; fe-setup 2e899643c).
  Label `Account grant`, not `Grant`. Values come from a word map over the grant's `state`, never the raw state:
  - active: `Active · v3`.
  - revoked: `Revoked · v3` in crit text. The detail also shows a crit callout: "The organization revoked this
    mission's grant to <account name>, so this provider can't be used until it's added again from an active
    grant." Without the account name (members): "…revoked this mission's grant, so…".
  - unrecognized: `v3`, with the state left out (U20).
  - `null` (an older provider bound without a grant): `None: set up before account grants`. Not "bound
    directly", which is model wording.
- Health is real only: if the server doesn't check credentials, the status is `NOT CHECKED` (hatched),
  not connected.

## Acceptance (for qa)
- No hard-coded settings sections or fields; every section shows where its values come from (per field once api stores only overridden paths).
- The audit log says which sources are missing until it's unified.
- No secret is ever entered or shown; credentials are references. Provider status is never green without a real check.

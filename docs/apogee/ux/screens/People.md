# People & access (S5 · org admin)

Routes `O/org/people` (tab People) · `O/org/people/invitations` · `O/org/people/services` ·
`O/org/people/policies` · person `O/org/people/:userId`. Setup rail › Organization ›
People & access · **reading layout** · Board `People.dc.html`. Owner: fe-setup. Data:
`docs/apogee/plans/setup.md` §S5. Scope: DECISIONS #2 (roles stay `organization_admin` / `member`;
Cedar later; UI gates on session capabilities), #7 (two-person rule is policy-driven).

**Question:** "Who can do what, who's on console, and how do I add someone?"
**Journey:** invite by email with a role (and mission scope when it exists) → see who can command
and who can give a second GO → manage service identities and their keys.

## Layout
```
lbl "REFLECT ORBITAL · ORGANIZATION"
h1 "People & access"
subline: 14 people · 2 pending invites · 3 service identities · 4 on console now
tabs: People 14 · Invitations 2 · Service identities 3 · Command policies
┌ U1 table panel (flex 999) ─────────────────┐ ┌ aside: U2 Invite · U3 Service ids · U4 Policies ┐
```
The canvas's **Roles** tab is **dropped** until Cedar roles exist (DECISIONS #2). Subline parts
are omitted when unknown (`on console now` needs presence).

## U1 · People (ApTable)
Header: title, filter field ("Filter by name, role or mission"), meta `14 OF 14`.
Columns: **Name** (name link 600 + email mono 11 `text-4` below) · **Role** (`Org admin` /
`Member`, the real values) · **Missions** (`All` for org admins, else list; omit the column while
membership isn't mission-scoped) · **Command** (`YES` readout / `NO` `text-4`, mono) · **Second GO**
(same) · **Status** tag (`On console` readout outline / `Off shift` `text-3` / `Invited` `text-3`) ·
**Last active** (mono, `now`, `4m ago`, `7h ago`, `never`).
- *Command / Second GO* derive from **capabilities the server evaluates per user** (e.g.
  `command.request`, `command.approve`), never from the role name in the browser, so Cedar can
  replace the logic without UI changes.
- *Status / Last active* need presence + last-seen (plan gap). Until then **drop both columns**
  (U10 logic: no dashes column-wide).
- Footer "6 more, all viewers" + `Show all 14` when paged.
- Row actions: an `action menu`-style popover on the name page only (change role, remove); the
  table has no per-row buttons (rule: one link per row).

## U2 · Invite (aside panel)
Fields: Email (sans, `fld`), Role select (`Member · can command and give a second GO` / `Org admin
· also manages people and setup`; option descriptions come from capabilities, so they stay honest),
Missions checkboxes (hidden until mission scope exists). Primary `Send invite` (standard 38px, the
only primary on the page). Success: invitation row appears on the Invitations tab, nominal callout
"Invite sent to ana@…" in the panel. Errors (already a member, invalid email) inline under the field.
Shown only with `org.invite`.

## Invitations tab
ApTable: Email · Role · Invited by · Sent (mono) · Expires (`T−6d`) · status (`Pending` /
`Expired` caution). One row action via the email link → detail with `Resend` / `Revoke`.

## U3 · Service identities (aside panel + full tab)
Rows `si`: name (mono 600) · last used (mono, right) · scope sentence (`Telemetry write · Earendil`)
· key age warning as caution mark + sentence ("Key is 104 days old, rotation policy is 90"). Header
meta link `NEW`. Full tab adds created, key id (mono, truncated), `Rotate key` / `Revoke` on the
detail page; the new secret is shown once in a well with `Copy` and the sentence "You won't see
this again."
- Rotation policy days: only if the org has one; otherwise no warning (don't invent 90).

## U4 · Command policies (aside panel + tab)
Read-only in v1 (DECISIONS #7: policy-driven, mission-configurable later): each policy as title
(600) + one sentence, from the server's effective policy, e.g. "Two-person for hazardous and
critical commands: a second GO from another person who can approve." and "Fleet-wide reach: any
request to more than N spacecraft needs a second GO." The tab footer says "Policies become
configurable per mission later." No edit controls until then.

## Person page (`O/org/people/:userId`) — not on the canvas
Header: name (entity title), role tag, email (mono). Panels: **Access** (capabilities as plain
sentences grouped: Operate, Command, Approve, Setup, Organization; `YES/NO` mono), **Activity**
(last 10 audit events by this person), **Manage** (Change role select + `Save`, `Remove from
organization` danger button with typed-confirm). Your own row: role change disabled with "You
can't change your own role."

## Account (`/console/account`) — review #18
**Pending invitations (legacy L21; Notifications is dropped, #64):** when the signed-in user has invitations
to other organizations, Account shows them first: `Acme Space · Member · invited by Mira K. on 11-10` with
[Accept] [Decline] (Decline confirms first). Accept adds the org to the switcher and opens it. The org switcher
shows `1 invitation` at its foot, linking here. Not on Now (mission-scoped) or org People (that's the inviting
org's admin view). The email link `/invitations/:token` stays server-rendered (IA) for people who aren't signed in.
Your profile (name, email), password change (current + new + confirm, `<.input>`-equivalent
fields), active sessions (device, last seen, `Sign out`), notification preferences (later). Reading
layout, no rail; reached from the account menu.

## States
Non-admins: People tab readable (names, roles), no invite panel, no service identities or
invitations tabs (capability-gated), a `text-3` line "Org admins manage access." Empty org (just
you): table with your row + callout "Invite your first operator."

## Acceptance (for qa)
- Roles shown are the real two; no Roles tab.
- Command / Second GO come from server capabilities; changing a user's role updates them without a
  client change.
- Columns without data (presence, missions) are absent, not filled with dashes.
- Invite form validates inline; secrets are shown once.

# Sign-in, invitations, no-organization, admin mode (L5, L6)

SPA auth screens replacing the LiveView ones. Owners: lead (screens and shell), api-ops (JSON endpoints, attempt
limit 2ba5cd57). One sign-in path, `/sign-in` (single email + password form). Every password field shares the
attempt-limit state below.

## Auth layout
A centred column, 400px (16px gutters on a phone), Cadence mark on top, no rail or top bar, page background with
the grid. One panel per screen: h1 (display 24px), at most one sentence under it, fields, then a full-width
primary. Footer text-3: `UTC 23:55:03`.

## Too many attempts (429, `retry_after` seconds)
- A caution callout above the fields: "Too many attempts. Try again in 0:42." The countdown is m:ss and live.
  When it reaches zero the callout goes and the form works again.
- The primary is disabled with that sentence as its reason. Typing is still allowed.
- Never "locked" (there's no lockout), and never which part was wrong.

## Sign-in (`/sign-in?return_to=…`)
- h1 `Sign in`. Fields: Email, Password. Primary `Sign in`. On success, go to `return_to` (same-origin only), else
  console home.
- Wrong email or password: crit callout "That email and password don't match." It never says which.
- Account disabled (403 `account_disabled`, only after a right password): crit callout "This account is
  disabled. Ask an organization admin for help." It doesn't say who can turn it back on, because we don't know.
- Network or 5xx: caution callout "Couldn't reach Cadence. Try again." with the server's reason when it gives one.
- Already signed in: redirect straight to `return_to` or home.
- There's no "forgot password" link until a reset flow exists (U20).

## No organization (`/no-organization`)
Signed in, member of no organization.
- **With pending invitations:** h1 `You have 2 invitations`. One row each: `Acme Space · Member · invited by Mira K.
  on 11-10` [Accept] [Decline]. These are the same rows as Account (L21), and Decline confirms first. Accept opens
  that organization.
- **Without:** h1 `You're not in an organization yet`. Then "Ask an organization admin to invite you. They'll
  need your email: qa@example.com." with the secondary `Sign out`.
- **Platform admins** also get the link `Enter admin mode` (admin area L7, where they can create an organization).

## Invitation link (`/invitations/:token`), signed out or signed in
The header line for every case is "Mira K. invited you to Acme Space as Member on 11-10."
| Case | h1 · body | Primary |
| --- | --- | --- |
| No account for that email | `Join Acme Space` · Name, Email (prefilled, read-only), Password (hint "At least 12 characters."), Confirm | `Create account and join` |
| An account exists, signed out | `Sign in to join Acme Space` · Email (fixed), Password (attempt limit applies) | `Sign in and join` |
| Signed in as that email | `Join Acme Space?` | `Join` + secondary `Decline` (confirms) |
| Signed in as someone else | caution callout "This invitation is for ana@x.com. You're signed in as qa@example.com." | `Sign out and continue` |
| Expired | off callout "This invitation expired on 11-17. Ask Mira K. for a new one." | — |
| Withdrawn | off callout "Mira K. withdrew this invitation." | — |
| Already used | off callout "This invitation was already accepted." | `Sign in` |
| Unknown token | off callout "This invitation link isn't valid." | `Sign in` |
| Declined | off callout "This invitation was declined. Ask for a new one if you want to join." | — |
| Unavailable | off callout "This invitation isn't available any more. Ask for a new one." | — |
| A case the console doesn't know | off callout "This invitation can't be used here. Ask for a new one." | `Sign in` |
Use the actor and time the server gives (U29). Without them, drop the clause and keep the sentence.
- **h1 for the terminal cases** (fe-ops f58d4e53): `Invitation not valid` · `Already accepted` · `Invitation
  expired` · `Invitation withdrawn` · `Invitation declined` · `Invitation unavailable` (also for unrecognized cases)
  · signed in as someone else: `Invitation for another account`. The callout sentence sits under the h1.
- **No dead ends:** every case with nothing to fill in offers `Continue to Cadence` when signed in, else
  `Sign in`.

## Admin mode step-up (L6)
- **Entry:** account menu `Enter admin mode`, shown only with the `platform_admin` capability. It opens a dialog
  (ApSheet, small) titled `Admin mode`, with the sentence "Enter your password to use platform administration
  for 1 hour." (the hour is the server's TTL) and a Password field. Actions: `Enter admin mode` (primary) and
  `Cancel`. Wrong password: "That password isn't right." 429 behaves as above. Visiting an admin route outside
  admin mode shows the same form inline on that page.
- **While on:** a caution chip in the top bar, left of the UTC clock: `ADMIN MODE · 52:10` (a live countdown to
  `expires_at`), which opens a menu with `Admin area` and `Leave admin mode`. It isn't a banner, because the
  banner slot belongs to U38. Under 5 minutes the chip text turns to caution-strong. The account menu also lists
  `Admin area` and `Leave admin mode`.
- **Leave:** immediate, no confirm. On an admin page it returns to console home, with an info toast "Admin mode
  ended."
- **Expiry:** the chip goes. An admin page that's open shows the info callout "Admin mode ended at 03:10Z. Enter it
  again to continue." with the inline password form. Nothing unsaved is discarded silently: a form with changes
  keeps them until the user re-enters admin mode or leaves.

## Acceptance (for qa)
- 429 shows a live countdown and re-enables at zero, on sign-in, invitation sign-in and admin mode.
- No screen reveals whether an email has an account (sign-in errors, and the 429 text).
- The admin chip counts down to the server's `expires_at`, and the admin routes require it.

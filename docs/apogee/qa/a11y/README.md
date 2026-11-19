# §6 Accessibility pass (qa)

BACKLOG §6: axe + keyboard traversal + focus order on every route, at 1440 and 390, as admin and
member, one file per screen. Fixes go to the screen's owner; kit-level fixes go to lead.

## Method

- **Where:** :4011, real data (the Earendil demo), headless system Chrome, one page at a time
  through `scripts/check-slot.sh` (lead's load rule). Read-only: pages are loaded and Tab is pressed;
  nothing is clicked or typed.
- **Who:** `admin` = `qa-org-admin` (organization admin), `member` = `qa-operator` (member).
- **Widths:** 1440×900 and 390×844.
- **Each page:**
  1. Wait for `body[data-shell-ready]`, network idle, and no "Loading…" text (up to 90 s; pages
     still loading are marked).
  2. axe WCAG 2.1 A/AA (`wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`).
  3. h1 count and landmarks.
  4. Tab from the top up to 120 times. Each stop records role, name, landmark, rect, whether
     it is visible, whether something else is on top of it (`elementFromPoint`), and whether a
     focus indicator exists (outline or box-shadow on the element or a `:focus-within` ancestor,
     or a border change on an input's wrapper). Flags: invisible or `aria-hidden` stops, no
     indicator, focus stuck on one element, page scrolls sideways.
- **Popups:** native `<dialog>` + `showModal` (ApSheet and the hand-rolled sheets) trap focus and
  return it; the palette has its own trap (qa #13). Checked in code and live (U31 Resolve dialog:
  focus lands in the textarea, returns to "Resolve…").
- **Excluded:** the dev-only Tidewave toolbar (`#tidewave-toolbar`, bottom left). It covers
  the 390 tab bar and some rows in dev; it isn't in production builds.
- **Known false positives, already ruled out:** kit inputs show focus by changing the
  wrapper's border from `rgb(42,54,68)` to `rgb(230,237,243)`, not an outline, so the probe
  checks that too.

## Files

One file per screen in this folder (`<screen>.md`): what was checked, findings with owner, and the
raw data's location (scratchpad `console/a11y-out3/`, not committed). Findings that need a fix also
go into `../issues.md` with a number.

## Status

Run 1 (11-13 00:00-03:00Z) was under load 50-160 and caught several screens mid-load, so its axe
results only count where the page had rendered. Run 2 (`a11y-out3`, from 07:55Z) waits for
loading to finish; the per-screen files are written from it.

## Summary (run 2, 304 page runs over 36 screens)

Clean at both widths for both roles (axe 0, one h1, every tab stop visible with an indicator, no
sideways scroll): K1, K2, Now, Fleet, Investigate (all six tabs), Alarms, Contacts, Telemetry
Explore, Timeline, Readiness, Profiles (except History at 390), Catalog, Changes, Revisions,
Comms, Stations, Data sources, Apps, Mission settings, Missions, Org settings, Account, home,
org home, not found.

| # | Finding | Screens | Owner |
| --- | --- | --- | --- |
| 1 | Table scroll wrapper (`overflow-x-auto`) at 390 has no tab stop, role or name (axe `scrollable-region-focusable`, serious) | catalog-import run, K3 pass review, person, profile History, spacecraft detail | lead (kit) |
| 2 | Wizard step bar scrolls sideways at 390 with no tab stop (same rule) | new spacecraft, all four steps | lead (kit) |
| 3 | In-text "Audit log" link marked by colour only (axe `link-in-text-block`, serious) | provider account | fe-setup |
| 4 | ~~Dashboards directory makes the page scroll sideways by 134 px at 390~~ fixed 9b9a99649: below 768 the directory is ux's Mobile rows (DirectoryRows.vue), ux accepted | Telemetry › Dashboards | dashboards |
| 5 | A member who opens an admin-only org page by URL gets a 403, "You do not have permission to do that." with a Retry that can't succeed, and an empty org-level rail | Audit, Provider accounts, People › Services, person | fe-setup |
| 6 | `GET /command-draft` 404 with no draft logs a console error on every load | Commands, Compose, Request | api / fe-ops |
| 7 | Requirements read 500 (qa #53) | Contact planning | api |

Kit popups (ApSheet and the hand-rolled native `<dialog>` sheets, palette) trap and return focus as
designed.


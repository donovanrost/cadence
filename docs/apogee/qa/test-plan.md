# Apogee QA test plan

One e2e spec per journey (`frontend/apps/console/e2e/<id>-<name>.e2e.ts`). Every spec also gets
the baseline checks: no console errors and no failed app requests (auto fixture), axe WCAG 2.1 AA,
keyboard-only completion of the primary action, ≥44px primary targets, status with a text/shape
equivalent, honest empty state (no invented numbers), and an error state with the API failing
(`page.route` → 500).

Data: Reflect Orbital / Earendil (500 spacecraft, 10 sites). Assertions use the seeded data,
not canvas sample values (e.g. the canvas's "EARENDIL-312 VBAT red" is illustrative).

## Shell

| Check | How |
| --- | --- |
| Signed out → `/sign-in` | fresh context, goto `/console` |
| Banner shows real org + mission | text from seed |
| Labelled nav, one `main`, one `h1` | roles |
| Deep-link reload returns SPA | goto `/console/<route>` → 200 |
| OPS / SETUP switch (SetupJourneys) | switch is a real control, state announced (`aria-pressed`/`aria-current`) |
| Nav order (Journeys NAV): Now, Fleet, Alarms, Commands, Contacts, Telemetry, … | link names + `aria-current` on active |

## Operator shift

| Id | Journey | Key assertions |
| --- | --- | --- |
| J1 | Now (start of shift) | Fleet count = 500 from API; stale counted separately from nominal; action queue ordered P1→P3; no "NOMINAL" over empty data |
| J2 | Investigate alarm | Alarm opens with the point plotted against limits; sisters list links to spacecraft; procedure → uplink prefill carries target ids |
| J3 | Command a group | Target by query (plane/profile/condition) resolves real SCIDs (never "SCID —"); >25 targets allowed; GO/NO-GO poll per target |
| J4 | Contacts | Schedule shows passes by station from real opportunities; conflicts distinguishable without color |
| J5 | ⌘K palette | ⌘K / Ctrl+K opens; focus trapped in dialog; Esc closes and restores focus; results are actions; `G N` / `G C` shortcuts navigate |
| J6 | Mobile on call | 390×844 viewport: alarm, trend, next AOS visible without horizontal scroll; GO/NO-GO + acknowledge reachable; no compose on phone |

## Setup

| Id | Journey | Key assertions |
| --- | --- | --- |
| S1 | Readiness | One verdict per area; blockers before suggestions; identical findings grouped into one line with a count; each finding links to its fix |
| S2 | Add spacecraft | Profile picker, count + naming pattern; proposed SCIDs checked for clashes against existing 1–500; staged as one change (cleanup after) |
| S3 | Catalog import | Upload XTCE → diff added/changed/removed; impact list; invalid file → readable error |
| S4 | Profile | Inheritance shown; overrides listed per spacecraft; stage → diff → apply creates next revision |
| S5 | People | List members of the org; invite flow validates email; role change requires confirmation |

## Commanding

| Id | Board | Key assertions |
| --- | --- | --- |
| C1 | Compose | Args/ranges/units from catalog; out-of-range arg blocked with message; staged request created |
| C2 | Approve | Requires a **second** user (two browser contexts); requester can't self-approve when policy enforces it; approve-with-exclusions |
| C3 | Uplink & verify | State model Draft→…→Verified rendered with text labels; only verification turns it green; abort available until radiating; live updates via channel |

## Scheduling

| Id | Board | Key assertions |
| --- | --- | --- |
| K0 | Pass prediction | Windows per station for a horizon; time picker keyboard-operable |
| K1 | Plan | Draft fills demand; exceptions listed; submit sends bookings |
| K2 | Re-plan | Station down → affected passes re-planned as one revision |
| K3 | Review | Planned vs flown table; reading view scrolls; missed passes flagged |

## Manual pass (per screen, browser-automation skill)

Screenshot at 1512×1000 and 390×844, keyboard tab order walk, zoom 200%, reduced-motion, and a
visual check against the canvas board. Findings go to `issues.md` and to the owner directly.

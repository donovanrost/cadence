# Apogee QA test plan

One e2e spec per journey (`frontend/apps/console/e2e/<id>-<name>.e2e.ts`). Every spec also gets
the baseline checks: no console errors and no failed app requests (auto fixture), axe WCAG 2.1 AA,
keyboard-only completion of the primary action, ≥44px primary targets, status with a text/shape
equivalent, honest empty state (no invented numbers), and an error state with the API failing
(`page.route` → 500).

Data: Reflect Orbital / Earendil (500 spacecraft, 10 sites). Assertions use the seeded data,
not canvas sample values (e.g. the canvas's "EARENDIL-312 VBAT red" is illustrative).

Scope follows `docs/apogee/DECISIONS.md`; the decision number is in brackets where it applies.

## Personas

Seeded by `dev/apogee_qa_personas.exs` (see `runbook.md`); sessions saved by `e2e/auth.setup.ts`.

| Key | User | Role | Used for |
| --- | --- | --- | --- |
| `admin` | `admin@example.com` | env administrator (platform admin mode) | default, smoke |
| `operator` | `qa-operator@example.com` | `member` | capability gating, requester in two-person flows |
| `second` | `qa-second@example.com` | `member` | second GO / approver |
| `orgAdmin` | `qa-org-admin@example.com` | `organization_admin` | Setup + People without platform admin |

**Capability gating [2]:** every screen with admin-only actions runs as `operator` and as
`orgAdmin`. A control the user lacks the capability for is absent or disabled with a reason,
the API rejects the action if forced (`page.request`), and gating follows the session bootstrap's
capabilities, not role names hard-coded in the UI.

## Shell

| Check | How |
| --- | --- |
| Signed out → `/sign-in` | fresh context, goto `/console` |
| Banner shows real org + mission | text from seed |
| Labelled nav, one `main`, one `h1` | roles, after `body[data-shell-ready]` |
| Unknown deep link → in-shell Not found, 200 | goto `/console/<unknown>` |
| OPS / SETUP switch | real control, state announced (`aria-pressed`/`aria-current`) |
| Nav order: Now, Fleet, Alarms, Commands, Contacts, Telemetry, … | link names + `aria-current` on active |
| Org switch | `PUT /session/organization` round-trip; banner updates; no stale mission data |

## Operator shift

| Id | Journey | Key assertions |
| --- | --- | --- |
| J1 | Now | Fleet count = 500 from API; stale counted separately from nominal; action queue ordered P1→P3; no "NOMINAL" over empty data |
| J2 | Investigate alarm | Point plotted against limits; sisters link to spacecraft. Alarm lifecycle [6]: ack, assign, hand-off note persist across reload and show to a second user; auto-clear when back in limits. **No procedure panel** [5] |
| J3 | Command a group | Target by query (plane/profile/condition) resolves real SCIDs (never "SCID —"); >25 targets allowed; per-target GO/NO-GO poll. **No waves/gates** [8] |
| J4 | Contacts | Passes by station from real opportunities; conflicts distinguishable without color. Ground track / masks show honest "not available" [4] |
| J5 | ⌘K palette | ⌘K / Ctrl+K opens; focus trapped; Esc closes and restores focus; results are actions; `G N` / `G C` navigate |
| J6 | Mobile on call | 390×844: alarm, trend, next AOS without horizontal scroll (AOS "not available" [4]); GO/NO-GO + ack reachable [6]; no compose on phone |

**Propagation [4]:** ground track, umbra/eclipse and AOS-prediction panels render a labelled
"not available" state, never placeholder geometry or times.

## Setup

| Id | Journey | Key assertions |
| --- | --- | --- |
| S1 | Readiness | One verdict per area; blockers before suggestions; identical findings grouped with a count; each finding links to its fix |
| S2 | Add spacecraft | Profile picker, count + naming pattern; proposed SCIDs checked for clashes with 1–500; creates per-entity versions (cleanup after) |
| S3 | Catalog import | XTCE upload → added/changed/removed/breaking from catalog revisions only [9]; **no used-by/impact cross-refs** in v1; invalid file → readable error |
| S4 | Profile | Inheritance shown; overrides listed per spacecraft. Routing rules live on the profile, materialized per spacecraft, with per-spacecraft overrides [3]; existing per-spacecraft rules migrated (Earendil: 1,000 primary/backup routes still resolve) |
| S5 | People | Real roles only (`organization_admin` / `member`) [2]; invite validates email; role change confirms; `operator` can't reach admin actions |

**Change sets [1], v1 (per-entity versions):** the UI must **not** show a mission `rN`, a
staged-changes bar, or "apply as rN+1" until the change-set model lands. Tests assert their
absence and that each save reports its real per-entity version. When change sets land: stage
→ diff → apply creates `rN+1` with who/when/why; concurrent stage by two users; rollback restores
the prior revision; a failed apply leaves nothing half-applied.

## Commanding

| Id | Board | Key assertions |
| --- | --- | --- |
| C1 | Compose | Args/ranges/units from catalog; out-of-range arg blocked with message; staged request created |
| C2 | Approve | Two-person rule is policy-driven [7]: hazardous/critical **or** multi-target over threshold → requires a GO from a different user (`operator` requests, `second` approves; requester can't self-approve); non-hazardous single-target → no second GO asked. Approve-with-exclusions |
| C3 | Uplink & verify | State model Draft→…→Verified with text labels; only verification turns it green; abort until radiating; live updates via channel |

## Scheduling

| Id | Board | Key assertions |
| --- | --- | --- |
| K0 | Pass prediction | Provider opportunity windows per station for a horizon; time picker keyboard-operable; no browser-side propagation [4] |
| K1 | Plan | Draft fills demand; exceptions listed; submit sends bookings |
| K2 | Re-plan | Station down → affected passes re-planned as one revision |
| K3 | Review | Planned vs flown table; reading view scrolls; missed passes flagged |

## Manual pass (per screen, browser-automation skill)

Screenshot at 1512×1000 and 390×844, keyboard tab order walk, zoom 200%, reduced-motion, and a
visual check against the canvas board. Findings go to `issues.md` and to the owner directly.

# Apogee QA issues

Running list kept by qa. Each issue is also sent to its owner as a direct message.
Status: `open` → `fixed` (owner says so) → `verified` (qa re-tested).

| # | Area | Summary | Owner | Status |
| --- | --- | --- | --- | --- |
| 1 | Console build | `@import "tailwindcss"` unresolved: SPA never boots | lead | verified (9d7790ea) |
| 2 | Favicon | `/favicon.ico` 404 logged as console error | lead / api | console verified (9d7790ea); LiveView `/sign-in` still 404s (low, api) |
| 3 | Console shell | Account button: visible "CA" missing from its accessible name (WCAG 2.5.3) | lead | verified (22653d8d) |
| 4 | Setup + shell nav | Members (no capabilities) are offered mission-config and org-admin actions the server forbids (decision 2) | fe-setup, lead | verified (6d51ca92 + lead's rail) |
| 6 | Readiness API | Served `verdict` keys singular vs §R/decoder plural | api / fe-setup | fixed: decoder + §R moved to singular (fe-setup) |
| 7 | Fleet API | After a server restart, once-heard spacecraft read `never_heard` (ever-heard comes from the volatile ETS current-value store; violates U9) | api | verified (43eb6da0: 10 stale, 490 never heard) |
| 8 | Investigate chart | Line/band drawn across a 26-min data gap; rate computed across it | fe-ops | verified (19887eec) |
| 9 | Investigate B1 | "No active alarm" shown as nominal (green) while the mission has no limits configured (U13) | fe-ops | fixed (d3a2e569), e2e updated |
| 10 | Investigate header | Prev/next links show "2 ]" but are named "Next spacecraft, EARENDIL-002" (WCAG 2.5.3) | fe-ops | fixed (d3a2e569), e2e updated |
| 11 | Config API | First `GET /missions/:id/config` returned 500 during an e2e run; a later call 200 with a baseline created at that moment (suspected race in lazy baseline creation) | api / domain | fixed (0c037ba0) |
| 15 | Session / shell | Env admin in admin mode (platform_admin) gets `organizations: []` and can't open any org by URL | api / lead | verified (lead: org selected from the URL slug) |
| 16 | Framing HOLD (DECISIONS #36 gate) | No COMPATIBILITY HOLD on dev for a profile frame_size change | domain / qa | verified: gate rerun passed after restart; default on (DECISIONS #45), Earendil override cleared (settings v6) |
| 18 | Changes preview decode | Hold items lacked `change_id`; console couldn't decode the preview (K2 'reply wasn't understood', Apply stuck) | domain / fe-setup | verified (cc4afc5a, 86663423) |
| 19 | Change-set submit | Submit answered 500 (DB pool timeout under load) after the apply had committed (r6, generation 4) | domain / api | open |
| 20 | Station availability | Any OUTAGE window makes station-availability reads 500 (`binary_to_existing_atom("outage")`); the create returns 500 but persists | domain / api-ops | verified (306ca39c) |
| 17 | Planning policy API | `pending.requested_by` is a bare id (UI expects `{name}`: whole page fails to decode); after a reject, `pending` still lists the version and `document` shows its values while `active_version` = 1 | api / fe-setup | verified (58f948ae; UI pending panel + reject) |
| 21 | Planning policy decisions | Server requires `comment` on approve/reject; the UI allows an empty comment and shows only 'The request parameters are invalid.' | fe-setup / api | fixed (d692fea8; documented) |
| 22 | Contact plan state (K2) | Provider-cancelled bookings (4 reservations `canceled`) leave the plan `reserved`, so K2 refuses to re-plan | api / domain | verified (27459044 + booking_lost backfill; plan partially_reserved, K2 proposes) |
| 23 | Provider event inbox | ~96 events stuck `received` since 10:47Z and 5 `processing` since 10:43Z on :4011 | api / domain | verified (16570f5d; drained) |
| 24 | K1 superseded draft | Dimmed superseded draft fails WCAG contrast (axe: 22 color-contrast nodes) | lead | verified (U27: marks dim, text full contrast) |
| 12 | Palette | 'Show all N' `<button>` inside `role=listbox` (axe aria-required-children) | fe-ops | verified (cb5b2d12) |
| 13 | Palette | Focus leaves the `aria-modal` dialog after two Tabs (no focus trap) | fe-ops | verified (cb5b2d12) |
| 14 | Catalog import | File picker shows no visible keyboard focus (WCAG 2.4.7) | fe-setup | verified (32c2cb4e) |
| 5 | Now · fleet matrix | Plane buttons: "P01" vs label "Plane 1" (WCAG 2.5.3) and 36×10px targets 18px apart (WCAG 2.5.8) | fe-ops | verified (8ccf851f) |
| 25 | Uplink · abort | Pointer click on Abort hit the dev-only Tidewave toolbar (keyboard worked) | fe-ops | verified (e05d3790: real mouse clicks on Abort and its confirm, group aborted) |
| 26 | K1 submit · gap reasons | Windows already past on today's draft read "Provider search unavailable" (printed twice per row) instead of saying the window has passed | domain / api | fixed (10ffd37d doubled text; d882ee70 `window_passed` "This window has already passed.", new drafts only); re-check on the next same-day draft |
| 27 | K1 submit · gap reasons | Ticking "Same reason for all" still leaves one reason box per spacecraft; filling only the first keeps Submit disabled ("Every gap needs a reason first.") | lead | fixed (10ffd37d: one shared reason box); `planning-submit-race` e2e uses it |
| 28 | Commands list · delivered group | A delivered group stays in the "Released" tab reading "GO given · released to the queue" (list rows carry no `progress`), indistinguishable from one still waiting for AOS | fe-ops / api | verified (a2b322c7 + cfef9e9a + fe-ops' nullable row decoder: 3MKNW and I2DO in Closed reading '1/1 delivered'; Uplink tag '1/1 delivered'; Released empty) |
| 29 | Uplink · system events | After b5d6ed6d, the Uplink page for any completed group fails to decode the system actor `{actor_kind: "system"}` (no `user_id`; ruled correct, contract updated in 57fe2d6c) | fe-ops (actor reader as a variant on `actor_kind`) | verified (c1fe0eb4: 3MKNW and I2DO decode; log reads 'Cadence closed the run · 1 not verifiable'; no console errors) |
| 30 | K2 repair after an applied repair | Repairing r1 again after one booking was lost re-proposes K2's 4 already-applied HBK moves ("Apply · send 4 requests") and classifies the lost 004@KIR pass as kept, so Apply would duplicate 4 bookings and not rebook 004 | domain / api (plan), fe-setup (Impact wording) | open (not applied); attribution now 'Canceled at <provider>' (fe-setup); rebooked marker on /passes pending domain/api |
| 31 | K1/K2 unconfirmed callout (U30) | The callout lists every unconfirmed booking (40) uncapped; at 1512×1000 Demand/Draft/Selected collapse to ~0 height and the Gantt disappears; icon centred on the list; axe scrollable-region-focusable; hatch drawn under the bar label (1.3:1 where a stroke crosses a stripe) | lead / ux | open |

## Details

### 1. SPA fails to boot: `tailwindcss` not resolvable

- Repro: sign in as admin on http://127.0.0.1:4011, open `/console`.
- Expected: shell renders, `body[data-shell-ready]`.
- Actual: blank page; `GET http://127.0.0.1:5181/console/src/styles/app.css` → 500
  `Can't resolve 'tailwindcss' in frontend/apps/console/src/styles`.
- Cause: `apps/console/package.json` has `@tailwindcss/vite` but not `tailwindcss`.

### 2. `/favicon.ico` 404 on every console page

- Phoenix serves no favicon; Chrome logs `Failed to load resource: 404 (/favicon.ico)` as a
  console error, which the e2e diagnostics guard fails on. Fix: `<link rel="icon">` in the SPA
  `index.html`.

### 3. Account menu button fails Label in Name (WCAG 2.5.3)

- `src/shell/AccountMenu.vue`: the button shows initials ("CA") but `aria-label` was
  "Account menu for Cadence Administrator". Voice-control users can't say "click CA".
  axe `label-content-name-mismatch` (serious) in `shell.e2e.ts`.
- Fix: `aria-label` starts with the visible initials. Shell e2e passes with it.

### 4. Capability gating missing for members (decision 2)

- Repro: sign in as `qa-operator@example.com` (member; session `capabilities: []`), open
  `/console/reflect-orbital/earendil/setup/spacecraft` and `/setup`.
- Actual: same UI as an org admin: **Add spacecraft**, **Import catalog**, and the Organization
  nav section (People & access, Missions, Provider accounts, Settings, Audit log).
- Server policy (`apps/cadence/lib/cadence/auth/policy.ex`): `manage_mission`,
  `manage_missions`, `read_organization`, `manage_provider_accounts` need `organization_admin`
  (or `platform_admin`). A member clicking through gets a refusal instead of a hidden/disabled action.
- Expected: gate on session `capabilities` (not role names); hide or disable with a reason.
- Tests: `setup-spacecraft.e2e.ts` / `setup-readiness.e2e.ts` "organization member" cases are
  marked `test.fail` and will flip (and fail loudly) once gating lands.

### 5. Fleet matrix plane buttons: Label in Name + target size

- `src/features/fleet/FleetMatrix.vue:78-88`. Visible text "P01", `aria-label="Plane 1"`: axe
  `label-content-name-mismatch` (serious). Voice users can't say "click P01".
- Measured at 1512×1000: each button is **36×10 px**, centres 18 px apart. WCAG 2.2 AA 2.5.8
  needs 24×24 px or enough spacing that 24 px circles don't overlap.
- Fix: label that starts with the visible text (e.g. drop `aria-label` and add sr-only
  " · plane 1" after "P01", or `aria-label="P01, plane 1"`) and give the button the full row
  height with a ≥24 px hit area (padding or a taller row).
- Test: `now.e2e.ts` "is accessible with alarms showing" is `test.fail` until fixed.

### 7. Restart turns heard spacecraft back into `never_heard` (U9)

- Repro: run live feeds (EARENDIL-001…010 heard 22:26–22:31Z), restart Phoenix, GET `/fleet`.
- Actual: all 500 `state: never_heard`, `last_received_at: null`; Now says "awaiting first contact".
- Cause: `CADENCE_TELEMETRY_CURRENT_VALUE_STORE` defaults to `ets` (node-local); `/fleet` derives
  last_received_at / ever-heard from it. QuestDB still holds ~98k observations for those 10.
- Expected (ux U9): once heard, a silent spacecraft becomes `stale`, never `never_heard`.
- Reported by ux; dev server now runs with the Postgres current-value store.

### 8. Investigate chart joins across data gaps

- Repro: `/console/reflect-orbital/earendil/fleet/1/investigate`, 6H window (alarms mocked), point
  `EPS.sa1_current`. Samples exist only 22:28:15–22:28:50 and 22:54:54–22:55:57Z.
- Actual: mean line and min–max band run straight across 22:29→22:54; Rate "+13.44 per hour".
- Cause: `chart/scale.ts` `runs()` uses the median step as "typical"; with 3 buckets the median
  is the gap. `model.ts` `ratePerHour` uses first→last regardless of gaps.
- Fix: gap threshold from the response's `bucket_width_ms`; rate over the latest contiguous run.

### 9. Investigate: "No active alarm" reassures while nothing is checked

- Repro: real server (seed has no limit definitions; `/fleet` says `limits.configured: false`),
  open `/fleet/1/investigate`. B1 shows a nominal callout "No active alarm on EARENDIL-001."
- Expected (U13, and as Now already does): say limits aren't configured, so absence of alarms is
  unknown, not nominal. Test: `investigate.e2e.ts` "no limits configured" (test.fail).

### 10. Investigate prev/next: Label in Name

- `SpacecraftHeader.vue:97-106`: visible "2 ]" / "[" vs `aria-label="Next spacecraft, EARENDIL-002"`.
  axe `label-content-name-mismatch` (serious). Start the name with the visible text, e.g.
  "2 ], next spacecraft EARENDIL-002", or make the visible key hint `aria-hidden` and show the name.

### 11. `/config` 500 on first access (suspected race)

- During a parallel e2e run (Readiness screen), `GET /api/console/v1/missions/mission-earendil-demo/config`
  returned 500 once. Immediately after, it returned 200 with a `baseline` head whose `applied_at`
  (23:17:43Z) matched that run, so the baseline was created lazily then. Two first requests
  creating the baseline concurrently is the likely cause. Server log had already rotated.

### 12. Palette listbox contains a button

- `features/palette/PaletteResults.vue:50-59`: "Show all N pages" is a `<button>` inside
  `role="group"` within `role="listbox"`. A listbox may contain only options and groups, so axe
  `aria-required-children` fires on `#palette-results`. Make it an option (activates on Enter like
  the others) or move it outside the listbox. Test: palette "is accessible when open" (test.fail).

### 13. Palette doesn't trap focus

- Ctrl+K, then Tab twice: focus lands on the page behind the `aria-modal="true"` dialog. Keep Tab /
  Shift+Tab inside the dialog until Esc. Test: palette "Tab keeps focus inside" (test.fail).

### 14. Catalog import file picker: no visible focus

- `features/catalog/UploadPanel.vue:67-80`: the `<input type="file">` is `sr-only` inside a styled
  `<label>`. Tab to it: the label's outline/border/shadow are identical focused vs idle, and the
  input's own outline is on a clipped 1×1 px box. Keyboard users can't see where focus is.
- Fix: a `focus-within:` outline on the label (same token the buttons use).
- Test: catalog-import "the file picker shows keyboard focus" (test.fail).

### 15. Platform admin in admin mode can't open an organization

- The env administrator now has the fixed id `user_environment_admin` and no Reflect Orbital
  membership. Fresh sign-in: `GET /session` gives `admin_mode: true`, `capabilities:
  ["platform_admin"]`, `organizations: []`, `current_organization_id: null`.
- `/console/reflect-orbital/earendil/...` then shows "There is no organization 'reflect-orbital'
  you can open."
- Expected (session.md): a platform admin in admin mode sees the current organization without a
  membership, and the server policy admits `platform_admin` everywhere. The shell should resolve an
  org from the URL for admin-mode sessions (or the session should list orgs the admin can open).
- Suite: default persona switched to `orgAdmin`; shell "platform admin without a membership" is
  `test.fail` until fixed.

### 16. No framing HOLD for a profile framing change

- Earendil, flag `profile_framing_generations` on (mission scope). Profile `profile-earendil-block-1`
  v1 `frame_size` 1115 = transports' `fixed_message_bytes` 1115; drift task: no drift; generation 1.
- Staged `spacecraft_profile` update `frame_parameters.frame_size` → 1024 (rollout all). Preview:
  `compatibility` GO, no holds; K2 shows no HOLD; Apply enabled with just a reason.
- ~~Cause: holds/3 ignores profile entries / audits live values.~~ **Wrong** (domain, with line
  refs): rollout returns moved craft as `spacecraft` update entries, and preview runs in a
  rolled-back transaction where staged values are live. Actual cause: `fbbeba63` (22:57) registered
  `FramingCompatibility` in `config/config.exs`; the dev server was last restarted 22:46 and the
  code reloader doesn't reload config, so `holds/3` was never called. domain added regression tests
  (58e25481).
- Not applied; staged change discarded. Re-run the full DECISIONS #36 check after the fix.

### 17. Planning policy: pending version breaks the page; reject doesn't clear it

- Save a new policy version (org admin): `GET /contact-planning/policy` returns
  `pending.requested_by: "user_…"` (a bare id). The console decodes `requested_by` as `{name}`, so
  the whole Policy tab shows "The server sent data this console does not understand
  (data.pending.requested_by: expected object)". Nobody can approve or reject in the UI.
  scheduling.md doesn't fix the shape; elsewhere actors are `{kind, id, name}` (suggest that).
- Reject v2 as another admin (`POST /policy/2/decision` → `200 {state: "rejected"}`), then
  `GET /policy` still has `pending: {version: 2, …}` and `document.budgets.max_contacts: 1001`
  (v2's value) while `active_version: 1`. Expected `pending: null` and the active document.

### 19. Submit returns 500 after a committed apply

- 2026-11-09 23:15 local, load ~37: `POST /config/change-sets/:id/submit` (restore frame_size 1115)
  → 500 `DBConnection.ConnectionError` (pool checkout timeout). The apply had committed: head r6,
  generation 4, pins moved, nothing staged.
- An operator is told it failed when it succeeded. Either don't fail the response after commit
  (post-commit work outside the request / tolerant), or make the response distinguish "applied,
  follow-up failed"; and the console should treat a 5xx on submit as "unclear, check now", not
  as failure.

### 20. Outage windows crash station availability

- `Cadence.Comms.StationAvailability.view/1` (`station_availability.ex:328`, via `derive/3` :174 and
  `published/3` :319) calls `:erlang.binary_to_existing_atom("outage")`; `:outage` isn't loaded
  in the dev VM (`:maintenance` / `:degraded` are).
- Repro (fresh boot): `POST /station-availability/earendil-svalbard/windows` `{kind: outage, …}`
  → 500, yet the window persists (retry → 409 `window_overlaps`). Afterwards `GET
  /station-availability` and `GET /station-availability/earendil-svalbard` → 500.
- Fix: explicit kind mapping instead of `binary_to_existing_atom`.

### 21. Policy decision comment is required but the UI doesn't say so

- `POST /contact-planning/policy/:version/decision` with `{decision: "approve", comment: ""}` →
  422 `invalid_params`, `details.comment: "is required"`. The Approve/Reject buttons are enabled
  with an empty Comment and the alert reads "Nothing was changed. The request parameters are
  invalid." (scheduling.md doesn't state the comment is required.)
- Fix: require the comment in the UI (disabled-with-reason, as Changes does for "why") or show
  the field error; api documents it.

### 26. Past windows read "Provider search unavailable"

- 2026-11-09 ~11:25Z, K1 Plan the day for 2026-11-09 (plan `contact_plan_fleet_d0ede25e2cd7efcafff80733`):
  20 contacts short, all in 00:00–06:00Z and 06:00–12:00Z, i.e. windows that had already passed or
  were closing. Each gap reads "Contact count not met · Provider search unavailable · Provider search
  unavailable". The reason is misleading (the provider was up; the window is in the past) and is
  printed twice.
- Expected: a reason that says the window has passed (or past windows left out of today's demand).

### 27. "Same reason for all" doesn't apply one reason

- Same submit sheet ("Accept 10 gaps · 20 contacts short"). Tick "Same reason for all", fill the
  first "Reason for accepting this gap" box: all 10 boxes stay, Submit stays `aria-disabled` with
  "Every gap needs a reason first." Filling all 10 boxes enables it.
- Expected: one reason box (or the first box's text applied to all) when the box is ticked.

### 28. Delivered group still reads "released to the queue" in Commands

- Ruling (director, 2026-11-09): group `state` is the approval lifecycle only; `queued` after
  delivery is correct. Delivery comes from `progress` + member stage, and no list or row may show
  a delivered group as only queued.
- Repro: command_group_bp7lvyewsq_3MKNW (SET_MODE 4 → EARENDIL-004) delivered 18:26:36.8Z on
  2026-11-09 (member `no_verifier`, HK.sc_mode 0 → 4). Commands › Released: the row reads
  "GO GIVEN · RELEASED TO THE QUEUE", the same as fe-ops' NOOP on 001 (I2DO) that really is still
  waiting for a contact. The group never leaves the Released tab.
- Cause: `GET /command-groups` rows carry no `progress`, so `CommandTable` can only show
  `GROUP_STATE_WORDS[state]` (`list.ts` tabs filter on `state` alone).
- OK already: the Uplink page h1 derives from progress ("1 executed · not verifiable").
- Expected: the row's state cell (and tab placement) reflects progress, e.g. "Executed · not
  verifiable" / "Queued for AOS". Needs `progress` (or a summary stage) on list rows (api), then
  the cell (fe-ops).
- Evidence: scratchpad cmd-list-released.png, uplink-004.png.

### 29. Uplink page fails on system `completed` events

- Repro: after b5d6ed6d's reconcile sweep (18:47:42Z), open
  `/console/reflect-orbital/earendil/commands/command_group_bp7lvyewsq_3MKNW/uplink` (or I2DO).
- Actual: "The server sent data this console does not understand
  (data.events[1].actor.user_id: expected string)". The event is
  `{"kind":"completed","actor":{"actor_kind":"system"}}`, with the `user_id` key missing.
- Ruling (director, 2026-11-09): system actors carry no `user_id`; api-ops' 57fe2d6c reverted an
  interim `user_id: null` and updated commanding.md. Fix is console-side: the actor reader becomes a
  variant on `actor_kind` (fe-ops).

### 30. Second repair of a plan ignores the applied repair and the newly lost pass

- Setup (2026-11-09, domain's stop-on-failure step b): 11-10 r1 = contact_plan_fleet_6e74ced0; K2
  repair contact_plan_fleet_8ae6517e (4 HBK moves) applied and reserved 18:38Z. At 19:00Z qa
  cancelled 004@KIR 00:54Z (provider_reservation_naf4iny7uy_8BQ9, operation 267cefb5…) via the
  contact-workspace cancel action; r1 went partially_reserved.
- Repro: Contacts › Plan day 2026-11-10 › "Re-plan after provider changes" → Propose.
  Run fleet_planning_run_brs6fn2wcu_1E8RC → draft contact_plan_fleet_064be1c7.
- Actual: Impact lists 5 lost (the 4 HBK ones already re-booked by 8ae6517e, plus 004), all
  "Canceled by Earendil Demo Ground Network" (004 was cancelled by QA Org Admin). The proposal moves
  the same 4 HBK passes again ("Apply proposal · send 4 requests"), and 004@KIR 00:54Z appears in
  `diff.kept` with a new snapshot id (opportunity_snapshot_brs6fn2wcu_1EFM4), so it would not be rebooked.
- Expected: the repair builds on the applied repair (8ae6517e is the live plan for those 4); the
  lost 004 pass is a move/rebook (one request), even when the best opportunity is the freed one;
  Impact attributes our own cancel to us.
- Not applied. Evidence: scratchpad k2-004-1.png, k2-004-2.png.

### 31. Unconfirmed callout crowds out the plan (U30)

- Setup: simulator run paused 20:24–20:37Z 2026-11-09; the 11-14 plan contact_plan_fleet_e238c640
  approved, so 40 bookings stayed pending past the 10-min window (plan state `unconfirmed`).
- Works: the header reads "R1 · 0 BOOKED · 40 UNCONFIRMED"; the callout names the provider and
  count, lists soonest first, and shows T− on the first row; K2's live-plan view shows the same
  callout; the legend reads "Unconfirmed"; on resume all 40 confirmed in 11 s and the plan went to
  `reserved` by itself.
- Problems: (1) all 40 rows are listed, so the A/B/D panels collapse and the Gantt can't be seen
  (u30-gantt.png); (2) the warning icon is centred on the list; (3) axe scrollable-region-focusable
  (serious): K1 2 nodes, K2 `#main`; (4) `.ap-bar--unconfirmed` paints the hatch on the label's own
  element: label rgb(189,179,255) is 9.8:1 on stale-deep rgb(20,15,38) and about 5.9:1 against the
  averaged hatch, but 1.3:1 on a stripe. Labels don't render at day scale (bars about 10 px wide).

<!-- One section per issue: ### N. title — repro steps, expected, actual, evidence (screenshot path / console error). -->

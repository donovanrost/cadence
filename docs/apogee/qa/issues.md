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
| 12 | Palette | 'Show all N' `<button>` inside `role=listbox` (axe aria-required-children) | fe-ops | verified (cb5b2d12) |
| 13 | Palette | Focus leaves the `aria-modal` dialog after two Tabs (no focus trap) | fe-ops | verified (cb5b2d12) |
| 14 | Catalog import | File picker shows no visible keyboard focus (WCAG 2.4.7) | fe-setup | open |
| 5 | Now · fleet matrix | Plane buttons: "P01" vs label "Plane 1" (WCAG 2.5.3) and 36×10px targets 18px apart (WCAG 2.5.8) | fe-ops | verified (8ccf851f) |

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

<!-- One section per issue: ### N. title — repro steps, expected, actual, evidence (screenshot path / console error). -->

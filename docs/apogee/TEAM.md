# Apogee UI team charter

**Mission:** reinvent the Cadence UI as a Vue 3 single-page app built in the **Apogee** design
language. The design canvas is the inspiration, not a spec to copy pixel for pixel.

- Design canvas (live): https://claude.ai/artifact/3J6o3pyVdREHiXvxX8HVrw
- Local copy of every board: `docs/apogee/design-reference/*.dc.html` (+ `canvas.json` for titles/grouping).
  Each file is self-contained HTML; the `<script data-dc-script>` block holds sample data.
- Branch / worktree: `ui/apogee-spa` at `/Users/donovanrost/.herdr/worktrees/cadence/ui-apogee-spa`.
  Everyone works in this one worktree. Do not create other worktrees or branches.

## Board map (from canvas.json)

| Group | Boards |
| --- | --- |
| Design language | `Main` (Apogee language), `Fonts` (type study, **Saira + Saira Condensed + Azeret Mono chosen**), `TimePicker` (component) |
| Operator shift | `Journeys`, `Now` (J1 start of shift), `Investigate` (J2 alarm), `Command` (J3 command a group), `Contacts` (J4 plan contacts), `Palette` (J5 ⌘K), `Mobile` (J6 on call) |
| Setup | `SetupJourneys`, `Setup` (S1 readiness), `AddSpacecraft` (S2), `Catalog` (S3 XTCE import + diff), `Profile` (S4), `People` (S5) |
| Commanding | `CommandFlow`, `Compose` (C1), `Approve` (second operator), `Uplink` (uplink & verify, live) |
| Scheduling | `ScheduleFlow`, `PassPrediction` (K0), `SchedulePlan` (K1), `Replan` (K2 station down), `PassReview` (K3 planned vs flown) |

## Roster

The director is the session that hired you. Pane IDs are herdr pane IDs.

| Name | Role | Pane | Owns (write access) |
| --- | --- | --- | --- |
| director | Orchestrator, priorities, final say on scope | `w0Q:p1` | `docs/apogee/TEAM.md`, `docs/apogee/STATUS.md` |
| lead | Tech lead / frontend architect | see `docs/apogee/ROSTER.md` | SPA scaffold, shell, router, API client, shared components, build + Phoenix serving glue (with api) |
| ux | UX & design-system designer | see ROSTER | `docs/apogee/ux/**`, design tokens spec, visual review |
| api | Backend / Phoenix API engineer | see ROSTER | `apps/**` Elixir code, API contracts in `docs/apogee/api/**` |
| fe-ops | Feature engineer, Ops mode | see ROSTER | SPA feature dirs for Now, alarms, contacts, commanding, palette |
| fe-setup | Feature engineer, Setup mode | see ROSTER | SPA feature dirs for readiness, spacecraft, catalog, profiles, people |
| qa | QA & accessibility | see ROSTER | e2e/browser tests, `docs/apogee/qa/**` |
| domain | Domain-model engineer | see ROSTER | `apps/cadence/**` new models (change sets, profile routing, alarm lifecycle), `docs/apogee/domain/**` |

Live pane IDs are in `docs/apogee/ROSTER.md` (written by the director after hiring).

## Communicating (herdr)

Send a teammate a message with (`herdr` may not be on PATH in agent shells; use `$HERDR_BIN_PATH`):

```bash
"$HERDR_BIN_PATH" pane run <pane_id> "[from <your-name>] <message>"
```

- Keep messages to a few lines. Put anything longer in a file under `docs/apogee/` and send the path.
- Always prefix with `[from <name>]` so the receiver knows who to answer.
- Before sending, you may check whether they're busy: `herdr pane get <pane_id>` (`agent_status`).
  Messages to a working agent are queued, so sending is fine either way.
- Report to the director (`w0Q:p1`) on: milestone done, blocker, or a decision that's above your pay grade.
  Don't report routine progress.
- **Delivery check:** a message sent to an *idle* agent can land in its input box without being submitted.
  After sending, run `"$HERDR_BIN_PATH" pane get <pane_id>`: if it's still `idle`/`done` a few seconds later,
  run `"$HERDR_BIN_PATH" pane send-keys <pane_id> Enter`.
- Never close, kill or rename another person's pane. Never run `herdr server stop`.

## Architecture defaults (lead may refine; record changes in `docs/apogee/ARCHITECTURE.md`)

- **New SPA app** inside the existing pnpm workspace: `frontend/apps/console` (Vue 3 + TS + Vite,
  `vue-router`, Pinia if needed, Tailwind v4). Follow `frontend/AGENTS.md` and
  `frontend/docs/code-standard.md` (typed domain models, runtime decoding of API responses).
- It is a **standalone SPA**, not a module-federation remote and not LiveVue. Do not modify the
  existing federation host or `packages/ui`/`packages/design-tokens`; Apogee tokens/components
  live in the new app (or a new `frontend/packages/apogee-ui` if the lead decides).
- **Served by Phoenix** at a new path (default `/console/*`, catch-all returns the SPA index) behind
  the existing browser session; the SPA calls JSON endpoints with the session cookie + CSRF token.
  Existing LiveView pages keep working; we are building alongside, not deleting.
- **Live data** via Phoenix Channels (the `phoenix` JS client) where the design shows live values
  (Now, Uplink & verify, alarms).
- **Modifying APIs is allowed.** Prefer clean, purpose-built JSON endpoints for the SPA over
  contorting the UI around the old application-host query bridge. The api engineer owns the
  contracts; document each in `docs/apogee/api/`.

## Quality bar

- Elixir: `mix compile --warnings-as-errors`, `mix credo --strict` (don't add violations),
  `mix format`, per-app tests (`cd apps/cadence_web && mix test`).
- Frontend: typecheck + lint for the new app pass; no file over 400 lines; no render
  function/template block over ~50 lines without extraction.
- Real data only. No invented stats in shipped UI; if the backend lacks something, the api
  engineer adds it or the UI shows an honest empty state.
- Accessibility per the canvas: real buttons/links/inputs, 4.5:1 text contrast, ≥44px targets on
  primary actions, status never encoded by color alone (the canvas pairs shape + color + text).
- The CLAUDE.md "UI rules" about `assets/css/components` and `<.button>` etc. govern the
  LiveView/HEEx layer, not the new SPA.

## Controls (director, 2026-11-14 and 2026-11-16)

- **Never route around a permission or approval control.** Don't mint tokens or credentials outside the
  product path to get past a permission check (11-14: qa's service-token mint for a REST cancel was refused
  and not worked around). Don't write an approval or any human decision record by calling a domain
  function from a node or script under a person's name, even as a QA precondition (11-16: a scripted
  pre-gate model approval wrote a false record and had to be reverted). If a check needs an approval or
  permission that only a not-yet-landed path can grant, take the check out and run it after the real path lands.
- **Approval BEFORE, not an FYI after.** A step that routes around an approval or permission control needs
  the director's OK BEFORE it runs. "Say if you'd rather…" is only for calls that are safe to have already
  happened.

## Running the restart chain (director, 2026-11-17)

On 11-17 an approver's session died mid-turn at 09:17Z, right after qa's hand-over, and the chain (step 4
part 2, the 001 repair, the gap fixes) sat still for ~3 h 20 min under a hold with no end time.

1. **Start AND end.** The chain owner (lead) checks each step's expected END as well as its start, and pings
   within 15 min of either being missed. An idle pane ending in an API error is a dead turn, not work in progress.
2. **Backup approver.** Every approval step in a chain names a backup approver, a different agent from the
   stager. If the named approver hasn't acted within 15 min of the hand-off, the owner switches to the backup.
   An approval never sits waiting on one session.
3. **Holds end.** Every heavy-job hold has an end time when it's set. If the step it protects hasn't started
   by then, the hold lapses and the owner re-sets it explicitly, with a new end time.

## Git

- Commit small and often on `ui/apogee-spa`. Never push, rebase, reset, or stash. The director handles PRs.
- **Always commit by path, with the hook off:** `HK=0 git commit -m "…" -- <your paths>`.
  The shared worktree makes the hk precommit hook unusable: it runs for minutes over everyone's
  uncommitted files and the test database. You run the checks yourself instead (below).
- Never `git add -A` / `git commit -a`, never commit others' files. If `index.lock` exists, another
  commit is in flight: wait and retry; never delete the lock.
- Checks to run before committing:
  - Docs only: none.
  - Frontend: typecheck + lint (+ tests) for the console app (see `docs/apogee/ARCHITECTURE.md`).
  - Elixir (api only): `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` on touched
    files, and the tests for the touched area. **Only api, api-ops and domain run Elixir tests**, since parallel runs fight
    over the `cadence_test` database (domain uses `MIX_TEST_PARTITION=2`, api-ops uses `3`). qa runs the dev server against the dev database.
- **Heavy jobs go through the team gate (director, 2026-11-17):** `var/heavy-gate.sh --agent <you> -- <command>`
  (status: `var/heavy-gate.sh --status`). Heavy = full suites, test directories, hooked commits, builds, vue-tsc /
  typecheck, pnpm install, credo, the architecture check. The gate waits until BOTH the 1-min and 5-min load are
  under 16 AND fewer than 2 heavy jobs run team-wide; one heavy job per agent at a time. A heavy job run outside the
  gate is a rule break. Never set the HEAVY_GATE_* variables (devops' tests only), HEAVY_GATE_HELD included. Exit 75
  means it waited 30 min and ran NOTHING: report it to lead, don't retry in a loop. qa takes the slot lock
  (`--slot-begin '<what>'` / `--slot-end`) for its slots and hold windows; everyone else waits. Single targeted test
  files can run without it. Never leave watchers, dev servers or feeds running that you aren't using (qa owns the one
  shared dev stack).
- Conventional commit messages (`feat(console): …`, `feat(api): …`) with the Co-Authored-By trailer.

## Phases

1. **Foundations (now):** ux writes the design spec + IA; lead scaffolds the SPA + shell + Phoenix
   serving; api inventories endpoints, adds SPA session/bootstrap endpoints, and maps each screen to data.
   fe-ops / fe-setup study their boards and the existing LiveView pages + APIs for their area and
   draft a per-screen data plan; they start building when lead announces the scaffold is ready.
   qa sets up the browser test harness and a seeded dev login.
2. **Screens:** ops shift (Now → Investigate → Command → Contacts → Palette) and setup
   (Readiness → Spacecraft → Catalog → Profiles → People) in parallel.
3. **Flows:** commanding end to end (Compose → Approve → Uplink) and scheduling
   (Prediction → Plan → Replan → Review).
4. **Polish:** mobile on-call, accessibility pass, visual review against the canvas.

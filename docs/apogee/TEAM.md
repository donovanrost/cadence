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

## Squads (director, 2026-11-19; approved by the user)

The team works in domain squads. The board's **Squad** field holds each issue's squad. Legacy-page retirement
(E3) is done by the squad that owns the page's domain; the release lead keeps the E3 order. The Roster above
records who was hired for what; for ownership and review, this section wins.

| Squad | Domains (board labels) | Epics | Squad lead | Members |
| --- | --- | --- | --- | --- |
| Commanding & Approvals | commanding, approvals, identity | E1 #207, #201 (per-kind policies), #220 (offboarding) | api-ops | api, ca-security (security engineer, also security lead), ca-ux (UX designer), ca-engineer |
| Mission Model & Spacecraft | mission-model, spacecraft, applications | E2 #208, E4 #210 | fe-setup | mms-security (security engineer), mms-ux (UX designer), mms-engineer |
| Telemetry & Data | telemetry, data-management | E6-E9 #212-#215 | domain | staffed when laptop 3 arrives |
| Displays & Alarms | dashboards, alarms | E10 #216, dashboards | dashboards | staffed when laptop 3 arrives |
| Ground & Comms | comms, contacts, providers | E5 #211 | fe-ops | staffed when laptop 3 arrives |
| Platform | platform, tooling, CI, release, console kit | E11-E13 #217-#219, E3 #209 coordination | lead (release lead) | devops, qa |

### Owned paths

A path belongs to the squad that owns its domain. Shared layers (the web controllers and console API under
`apps/cadence_web/lib/cadence_web/`, the read models under `apps/cadence/lib/cadence/reads/`, the console's
`frontend/apps/console/src/features/`, and tests) follow the domain they serve: the file or folder name says
which. Anything not listed is Platform's. Where it isn't clear, the release lead decides and records it here.

| Squad | Backend (`apps/cadence/lib/cadence/`) | Web and console | Other |
| --- | --- | --- | --- |
| Commanding & Approvals | `commanding*`, `governance.ex`, `governance/{activation_policy,activation_locks,decision_record}.ex`, `action_requests/`, `accounts*`, `auth*`, `organizations*`, `administration/`, `secrets/`, `control/commanding*`, `control/command_brief.ex`, `control/command_encoding_preview.ex`, `management/commanding*` | console features `commands/`, `review/`, `people/`, `account/`, `auth/`, `admin/`, `audit/`, `settings/` (approval settings); web: command, approval, session and admin controllers, the console `activation_request_controller` and the settings controller's approval-setting path | `frontend/modules/commanding`, `frontend/apps/organization-admin`; `dev/apogee_qa_personas.exs`; `docs/apogee/api/commanding.md` |
| Mission Model & Spacecraft | `mission_models*`, `catalog*`, `spacecraft*`, `spacecraft_type*`, `spacecraft_store*`, `configuration/`, `activations*`, `applications/`, `application_dispatch/`, `extensions/`, `extension_catalog.ex`, `capabilities/` (Ground & Comms reviews `uplink_gateway`), `governance/`'s binding and capability rows | console features `spacecraft/`, `profiles/` (routing panel and extra routes: Ground & Comms reviews), `catalog/`, `activations/`, `changes/` (shared: see below), `readiness/`, `apps/`; `frontend/apps/spacecraft`, `frontend/apps/mission-catalog`; web: application host, release and surface code | `packages/cadence_catalog`; seeds `dev/apogee_qa_mission.exs` and `dev/apogee_qa_mission/`, and in `dev/reflect_orbital/` `seed.exs`, `configuration.exs`, `fixture.exs`, `activation.exs` (C&A reviews), plus `dev/reflect_orbital_demo/configure.exs` and `dev/reflect_orbital_activate.exs` (C&A reviews); docs `docs/apogee/api/{setup,changes,activations}.md`, `docs/apogee/domain/{mission-model-intent-vs-impl,catalog-generations,config-materialization-model,profile-routing}.md`, and the ux screens Setup, AddSpacecraft, Catalog and Profile |
| Telemetry & Data | `telemetry/`, `ingress*`, `ingress_journal/`, `ingress_archive*`, `semantic_observations*`, `semantic_runtime*`, `replay*`, `protocol/`, `data_sources/`, `source_endpoints*`, `projections/` and `runtime/` (split below), `derived_telemetry*`, `cfdp/`, `governance/`'s packet and derived-telemetry definition rows | console features `telemetry/`, `investigate/`, `sources/`, `timeline/`; `frontend/apps/telemetry-decom` | `frontend/modules/telemetry-decom`, `derived-telemetry`, `data-operations`; `packages/ccsds`, `packages/xtce`, `apps/cadence/priv/questdb/`, `dev/ingress-benchmark/` |
| Displays & Alarms | `dashboards*`, `alarms/`, `limits*`, `notifications*`, `ops/` | console features `dashboards/`, `alarms/`, `now/`, `fleet/`; `frontend/apps/ops-console`; web: console `dashboard_*` and `limit_transitions` modules, the `dashboard_*`, `alarm_*`, `alarm_episode_*`, `alarm_history_*` and `ops_counts` controllers, `channels/console/dashboard_channel.ex`, the `legacy_dashboard` and `legacy_ops` redirect controllers, `live/dashboard_author_auth.ex`, `live/notifications_bell.ex` | `frontend/modules/dashboards-and-exploration`, `limits-and-alarming`; `dev/reflect_orbital/dashboards.exs` |
| Ground & Comms | `comms/`, `contacts*`, `contact_planning/`, `ground_networks*`, `provider_adapters*`, `jobs/outcome_resolutions*`; in `control/`: `contacts.ex`, `contacts/`, `scheduling.ex`, `plan_confirmation*`, `plan_resubmission*`, `planning_*`, `providers.ex`, `providers/`, `pass_results_close_out*`, `contact_fact_consumer*`; in `management/`: `contacts.ex`, `contacts/`, `providers.ex`, `providers/`, `provider_account_*`, `communications_setup*`, `comms/`, `pass_review_settings_section*`, `transports.ex`, `config_kinds/transport.ex` (MM reviews) | console features `comms/`, `contacts/`, `planning/`, `scheduling/`, `replan/`, `resolutions/`, `stations/`, `providers/`; `frontend/apps/comms-overview` | `frontend/modules/communications`, `planning-and-contacts`; `apps/cadence_simulator/`; `docs/apogee/api/{contacts,scheduling}.md`; `dev/reflect_orbital/planning.exs`, `live_contacts.exs`, `dev/reflect_orbital_planning/` |
| Platform | `platform/`, `architecture/`, `observability*`, `missions*`, `operational_events*`, `mission_events/`, `listing.ex`, `ids.ex`, `repo.ex`, `application.ex`, `dev_profile.ex`, `smoke/`, `persistence/`, `jobs/` (except `outcome_resolutions`), the rest of `control/` and `management/` (cross-domain routing; changes need the owning squad's review too) | the console shell, router, API client and kit (`frontend/apps/console/src/{shell,router,api,live}`, `features/kit/`, `features/palette/`, `features/mobile/`, `features/missions/`); `frontend/packages/*`; `frontend/apps/host`, `storybook`, `surface-fixture`, `contract-probe`; `frontend/tools/` | `.github/`, `config/`, `mix.exs`, `mix.lock`, `mise.toml`, `scripts/`, `docs/apogee/TEAM.md` and `qa/`; `dev/` scripts not listed above |

**Mixed directories** (domain's read, 11-19). Telemetry & Data owns them, and the named squad also reviews changes to its files:
- **`runtime/`:**
  - Ground & Comms: `contact_*`, `realized_contact_runtime*`, `path_*`, `transport_*`, `uplink_*`, `session_*`, `provider_binding_spec`.
  - Commanding & Approvals: `commanding.ex`, `transmit_command`, `action_executor`, `dispatch_records`, `execution_agent`.
  - Mission Model & Spacecraft: `mission_runtime_spec`, `binding_set_index`, `activation_context`, `generation_applied`, `mission_admission`, `profile_acceptor`, `mission_model_plan_decoder`.
  - Platform: `cluster*`, `process_namespace`, `supervisor`.
- **`projections/`:**
  - Displays & Alarms: `telemetry_latest_limit_states`.
  - Commanding & Approvals: `command_status`.
  - Mission Model & Spacecraft: `activation_status`.
  - Ground & Comms: `contact_status`.
  - Platform: `mission_events`, `managed_resource_status`, `domain_fact_consumer`, `supervisor`.
  - Telemetry & Data: the rest.
- **`reads/`:** each file goes to the squad whose domain it reads. Telemetry & Data has `telemetry*`, `telemetry_decom/`, `point_*`, `console_sample*`, `data_source*`, `derived_telemetry*`, `pass_telemetry_stored`, `replay.ex` and `operational_evidence`. Displays & Alarms has `alarm_*` and `limit_state_evidence`; Commanding & Approvals has `command_*` and `verifier_series`; Ground & Comms has `plan_history`.

**Approval rules in other squads' directories** (api-ops' read, 11-19). Commanding & Approvals reviews any change to these, whoever owns the directory:
- every file named `*approval*` or `*four_eyes*`;
- `control/activations/approval.ex` and `control/activation_requests/`;
- `control/model_approval_gate.ex`, `control/actor_ref.ex` and `management/approval_setting_access.ex`;
- `activations/approval_admission.ex`;
- `reads/activation_approvals.ex`, `reads/command_groups.ex` and `reads/organization_audit/`;
- `applications/spacecraft_configuration/{authors,review,catalog_authority}.ex`.

**The change-set framework** (console `changes/`: KindEditor, SchemaForm, refusals, ChangeSetBoard) is Mission Model & Spacecraft's, and every squad stages through it. A change to it is also reviewed by the squads whose change kinds use it. Changes to ReviewPanel, submit or apply are also reviewed by Commanding & Approvals. **Routing rules** live in backend `comms/` (Ground & Comms) and show in the spacecraft and profile screens (Mission Model & Spacecraft), so the two squads review each other's routing changes.

**Shared files** (`router.ex`, `application.ex`, the root and app `mix.exs`/`mix.lock`, `config/*.exs`, the console's
route list): any squad may change its own lines. The release lead reviews any change to them and settles
conflicts. `dev/chaos/` is the user's lab: no squad edits it.

### Roles

- **Director:** priorities, milestones, and the high-stakes gates: pins, data drops, approval-policy changes, and anything outward-facing.
- **Release lead (lead):** merges into develop, the order changes land in, cross-squad integration, release to `main`, and the squad leads' daily sync.
- **UX lead (ux):** the design system and wording rules. Squad designers work to them, and ux reviews cross-squad UI.
- **Security lead:** the first security engineer hired (Commanding & Approvals). Also owns the rules every squad's security engineer applies.
- **Squad lead:** a working engineer. Sets the squad's order inside the milestones, reports to the director and syncs with the release lead.
- **Squad UX designer:** the squad's console flows and words.
- **Squad security engineer:** threat-models the squad's features. A required reviewer on any change that touches permissions, approvals, secrets, the network or tenant boundaries.
- **Squad engineers:** build, test and open PRs.

### Review rules

- **Every PR:** reviewed by a different agent in the owning squad, recorded on the PR. We share one GitHub account, so the review is a comment review headed with the reviewer's agent name and verdict.
- **Another squad's code:** a PR that touches it is also reviewed by that squad.
- **Security-sensitive changes** (see the security engineer above): the squad's security engineer also reviews.
- **Merging:** only the release lead or the director merges, after green CI. Nobody pushes to or force-pushes `develop` or `main`.
- **Landing:** qa lands merged develop SHAs on the laptop-1 dev stack, fast-forward only, in qa slots.
- **Issue links:** PR bodies say `Refs #N`, never `Fixes`, `Closes` or `Resolves`, which close the issue at merge, before landing. The issue's owner closes it by hand after qa's post-check, with the evidence in a comment.

### Machines

| Machine | Runs |
| --- | --- |
| Laptop 1 | The shared dev stack (develop, :4011, simulator, Postgres, QuestDB); the director, release lead, qa, devops, ux; current squad leads until they move |
| Laptop 2 | Commanding & Approvals, and Mission Model & Spacecraft. Each has its own worktrees, its own test Postgres and its own heavy gate |
| Laptop 3 (coming) | Telemetry & Data, Displays & Alarms, and Ground & Comms |

Laptop 2's agents are addressed as `donovans-macbook-pro-1/NAME` in hc (for example `hc send donovans-macbook-pro-1/ca-security "..."`). Since 11-19 they push their own branches and open PRs. Their token can't edit the project board yet (no project scope), so their squad lead moves their cards. Each agent on a worker machine works in its own worktree off develop; nobody shares a working copy. The
laptop-1 stack stays the integration environment, run by qa.

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

- Elixir: compile every project with warnings as errors: `MIX_ENV=test mix workspace.run -t compile --order postorder --early-stop --env-var MIX_ENV=test -- --force --warnings-as-errors` at the repo root (the CI command; a plain `mix compile` at the root builds only the workspace app, not cadence, cadence_web, the simulator or the packages); `mix credo --strict` at the repo root (don't add violations),
  `mix format`, per-app tests (`cd apps/cadence_web && mix test`).
- Elixir, before opening a backend PR, also run the CI jobs that a plain suite misses (all gated, on your own test partition):
  - `mix format --check-formatted` at the repo root;
  - `MIX_ENV=test mix workspace.run -t hex.audit` at the repo root (a new advisory fails CI even when nothing changed);
  - the ingest journal-off matrix: `cd apps/cadence && CADENCE_TEST_INGRESS_JOURNAL=off mix test --only ingest_journal_matrix`;
  - the simulator suite: `cd apps/cadence_simulator && mix test`, with the same `MIX_TEST_PARTITION`;
  - `mix test.planes` at the repo root;
  - `mix test.cluster` at the repo root. It starts Erlang distribution and peer nodes, and each peer runs its own `epmd -daemon`, which can bind on all interfaces next to the dev epmd (11-19 02:14Z). Leave it to CI and say so in the PR; run it locally only with qa's OK (the epmd rule).
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
4. **GO conditions are in the slot's plan (director, 2026-11-18).** Every condition in a director GO is copied VERBATIM into
   the slot's plan as a checklist, and the chain owner confirms the checklist is in the plan BEFORE the slot starts.
   A slot can't start with a GO condition missing from its plan. (11-18: comms batch 1 landed with only its dry's
   post-checks; its GO conditions, incl. a step-4 + gate re-check meant to come BEFORE it, ran late.)

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
  - Elixir (api only): `mix format`, the all-projects compile above (or `mix compile --force --warnings-as-errors` inside each app you touched), `mix credo --strict` on touched
    files, and the tests for the touched area. Every engineer runs the Elixir tests for their own work, in their own worktree, through their machine's heavy gate. On laptop 1, use your claimed partition (claimed in qa's runbook register; domain uses `MIX_TEST_PARTITION=12`, api-ops `3`). On a worker machine, use that machine's own test Postgres and the partitions devops set up there (laptop 2's register is `~/projects/cadence/test-partitions.md` on laptop 2: 10-19 Mission Model & Spacecraft, 20-29 Commanding & Approvals). Disk floors are the same on every machine: below 25 GiB free, no new builds, suites or installs; at 22 GiB, tell the director at once (dashboards still never runs Elixir: lead, 11-17). **Side worktrees (director, 2026-11-19):** on laptop 1, side worktrees with build output are the main background disk growth (devops, 11-19: up to 1.5 GB an hour). Keep one reusable side worktree per agent and switch it between branches. Remove a side worktree the day its PR lands on the qa stack, unless you name a follow-up that needs it: check its content against develop first (`git diff`, not only `git cherry`, because of squash merges), save anything worth keeping as a patch, then `git worktree remove` from the shared tree, never `rm -rf`, and only outside qa slots and holds. Never remove another agent's worktree. devops posts a worktree survey daily at 14:00Z, and lead chases owners from it. qa runs the dev server against the dev database.
- **Heavy jobs go through the team gate (director, 2026-11-17):** `var/heavy-gate.sh --agent <you> -- <command>`
  (status: `var/heavy-gate.sh --status`). Heavy = full suites, test directories, hooked commits, builds, vue-tsc /
  typecheck, pnpm install, credo, the architecture check. The gate waits until BOTH the 1-min and 5-min load are
  under 16 AND fewer than 2 heavy jobs run team-wide; one heavy job per agent at a time. A heavy job run outside the
  gate is a rule break. Never set the HEAVY_GATE_* variables (devops' tests only), HEAVY_GATE_HELD included. Exit 75
  means it waited 30 min and ran NOTHING: report it to lead, don't retry in a loop. qa takes the slot lock
  (`--slot-begin '<what>'` / `--slot-end`) for its slots and hold windows; everyone else waits. **Holds:** while a hold is active, a new
  heavy job exits 75 at once, except a job of qa while qa holds the slot lock: that one runs through the hold, still
  subject to load, memory and swap, and is logged in `heavy-gate.d/hold.log` as RAN-THROUGH (lead, 11-19, for the reset's
  quiet window; laptop 2's gate is unchanged). Single targeted test
  files can run without it. Never leave watchers, dev servers or feeds running that you aren't using (qa owns the one
  shared dev stack).
- Conventional commit messages (`feat(console): …`, `feat(api): …`) with the Co-Authored-By trailer.

## Tracking: the GitHub board (director, 2026-11-18)

Work is tracked on the GitHub project **Cadence**: https://github.com/users/donovanrost/projects/3
(issues on donovanrost/cadence; repo milestones; Status = Todo / In progress / In review / Ready to land /
Blocked / Done; Owner = agent). `docs/apogee/BACKLOG.md` is FROZEN as history; DECISIONS.md and the design
docs stay the record, linked from issues.

- The board is PRODUCT work only, written as a software project (user, 2026-11-18). Dev-environment operations
  (restarts, dev data fixes, dev retention) live in qa's runbook and log, never on GitHub.
- Every NEW piece of work is an issue created UNDER ITS EPIC (`gh issue create -R donovanrost/cadence … --parent <epic
  number>`; epics are #207-#219), added to the project (`gh project item-add 3 --owner donovanrost --url <issue url>`),
  with a milestone (M1-M9) where one fits, labels (one of type:story, type:bug, type:task, plus an area label) and your
  Owner.
- Shapes: STORY 'As a <operator / mission admin / platform admin>, I want <capability>, so that <outcome>' + acceptance
  criteria as checkboxes; BUG: what happens / what should happen / how to reproduce / impact; TASK: what / why / done
  when. Plain titles, no team shorthand; shorthand, DECISIONS numbers, doc links, branches and SHAs go on a final
  'Context:' line. Approved samples (11-18): story #150, bug #158, task #166; templates in .github/ISSUE_TEMPLATE after the develop merge.
- LABELS (director, 11-18): no issue without a TYPE (type:story / type:bug / type:task / type:epic), at least one DOMAIN (domain:telemetry, alarms, dashboards, commanding, contacts, comms, mission-model, spacecraft, approvals, identity, applications, providers, data-management) and at least one COMPONENT (component:management-plane, control-plane, data-plane, api, console, legacy-ui, platform, simulator, tooling).
- A live check is an acceptance-criteria checkbox ('Verified live on the dev stack') on the story or bug it
  verifies, never its own issue.
- Keep YOUR OWN cards' Status current (`gh project item-edit`), and comment on the issue at milestones (SHA,
  PR, check results). Close an issue when it has landed AND been post-checked.
- Restart chains are NOT on GitHub (user, 11-18): qa's runbook and pass checklist carry them.
- Decisions still go to the director by message; routine progress goes on the board.
- Everything on GitHub is public. Plain words are fine (security items included), but never the user's
  email, passwords, tokens, cookies or other credentials.

## Pull requests into develop (user, 2026-11-17; in force from the develop cut-over)

Once `ui/apogee-spa` has merged into `develop` and qa's dev stack runs develop:
- Every piece of work is a feature branch off `develop`, linked to its issue. Agents push their OWN feature
  branches and open PRs into `develop`. Never push to or force-push `develop` or `main`.
- A PR merges only after CI passes AND the reviews in Squads › Review rules are recorded in the PR (we
  share one GitHub account, so the record names the reviewing agent). Only the release lead or the director presses merge.
- qa lands only MERGED develop commits, fast-forward only (`git merge --ff-only <sha>` on the local
  `live/develop`), and logs the PR numbers with each landing. Dries and the #108 struct-hash check stay.
- Until the cut-over, the rules in Git above stand (the director pushes; nothing is picked onto the frozen tip
  during the freeze).

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

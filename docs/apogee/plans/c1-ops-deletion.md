# §11c(C1): delete the legacy /ops pages except /ops/alarms (plan, dashboards for lead, 11-16)

Pattern: `plans/legacy-deletion.md` (fe-setup). Read-only inventory 11-16 on head `355cd169d`; re-grep before the
batch. R = `apps/cadence_web/lib/cadence_web/router.ex`, HPL = `live/host_page_live.ex`, rj =
`frontend/apps/host/src/routes.json`. Lands as one batch after (B), only with qa's live checks and the director's go.

## Gate: parity rows (fe-ops' status, qa's live results 11-16)
| Rows | Built | Live |
| --- | --- | --- |
| A1/A2 priority + expiry | 6457c219f, c60a64ab5 (+ U75) | read-only PASS; **armed High + expiry run pending** (lead's quiet window) |
| A3, A4b/c attempts + verifier evidence | 19a547cd0 6aaa57871 b2edea7ab | PASS 03:35Z |
| A4a verify times | 744305e1d 8216a6cbc | PASS (an 11-14 row shows no 'Verified at': older row, field absent) |
| A5a/b state, search, target; A5c Load more | 3cf72bc1e | PASS; **A5c unit-tested only** (qa OK; lead/director to confirm) |
| A8/A9 Timeline detail, permalink, filters, paging | dashboards 04437cc3d..a71f02134, 977c6a73f | PASS 08:35Z |
| A10 plan versions + decisions | fe-setup 72d492e07 fa01362e2 | PASS 03:48Z |
| A12 Contacts History (+ Timeline links) | 0e5bdcd06..f8a79b2ca | PASS 08:28Z (follow-up for qa's future-date note in review) |
| A16a offer details; A16b routes | 84aed5aa0; 11f733e61 | PASS 03:30Z; PASS ~04:50Z |
| R1 server-resolved arguments (C-condition) | fdb139d5a c60a64ab5 c0588977d | **pending**: needs a real request awaiting approval (product path only) |
| D1–D4 | 3b6afd455 e3022d920 | PASS |
| Federation smoke (the (C) gate) | devops 0fb86f686 + 987034f1e | green on its branch; lands after (B) ~11:30Z |

Out of C1: A6a–d, A7 (the /ops/alarms rows) → C2; A11/A13 built with L14 (reservation page stays); A14 with the user.

## Routes and targets (one 302 each, slug lookup per `ConsolePaths`)
| Legacy (`/missions/:mission_id/…`) | Console target |
| --- | --- |
| `/ops` | `ops.now` |
| `/ops/planning`, `/ops/planning/new` | `ops.contacts.plan` |
| `/ops/planning/runs/:id` | `ops.contacts.plan?run=<id>` |
| `/ops/plans/:id` | `ops.contacts.plan?plan=<id>` |
| `/ops/contacts` | `ops.contacts` |
| `/ops/contacts/records/:contact_id` | `ops.contacts.history?contact=<id>` (`/passes/:id` resolves scheduled and realized ids) |
| `/ops/timeline` | `ops.timeline` |
| `/ops/commands`, `/workspace`, `/stages`, `/stages/new`, `/stages/:id` | `ops.commands` (stages gone by design) |
| `/ops/commands/new` | `ops.commands.new` |
| `/ops/commands/requests/:id`, `…/queue` | `ops.commands.request` `/commands/:id/review` (same `command_request_id`) |
| `/ops/commands/requests/:id/history` | `/commands/:id/uplink` (attempts + evidence) |
| `/ops/contact-workspace`, `…/records/:id` | `ops.contacts`, `ops.contacts.history?contact=<id>` |

**Retained** (still render; each names who keeps it): `/ops/alarms` (C2), `/ops/contacts/:provider_reservation_id`
(L14), `/ops/data-operations[/manage]`, `/ops/explore`, `/ops/activations` (L10's own batch), `/ops/telemetry/explore`.
The ops frame (`host/src/ops-workspace/features/frame/*`) stays: it wraps every retained /ops page.

## Decisions for lead before building
1. **Federated `ops_console` surfaces.** Every C1 page except contact-workspace also exists as a federated surface
   (`applications/ops_console.ex:26-110,199-205`: workspace, contact_schedule, contact_plan_show, contact_record,
   fleet_planning[_new|_run], commands, timeline; Vue `apps/ops-console/src/Ops*.vue`). Their components call
   `useOpsHeader` with C1 route ids, so regenerating the catalog breaks the host type-check, and
   `HostRoutes.for_surface` loses their host routes. **Proposal:** delete those surfaces in the SAME batch (as the
   L1–L4 federated batch did), so the domain reads, actions and page components go too. Otherwise the batch has to
   bring back the `retained-legacy-routes.json` mechanism (f13e537c6, removed 4085ea817).
2. **The legacy federation smoke** (`tools/phoenix/federation_browser_smoke.mjs:5245`, contract `:3209`) uses the
   `commands` surface and asserts `/ops/commands`. devops' console smoke is unaffected (console routes only), but the
   legacy smoke needs devops' update in the batch if decision 1 deletes `commands`.
3. **Who builds the Elixir half.** dashboards doesn't run Elixir. The server side is large: R lines 134-140, 409-490
   (less the retained routes); HPL trims (:21-22, :147-418, :436-450, :672-679 and others); 15 `ops_*_page.ex`
   modules; the contact-workspace controller and HTML; 20+ web tests deleted, 4 trimmed; redirects in
   `ConsolePaths` style. **Proposal:** api writes the redirects (as for L1–L11), and an Elixir owner (api-ops, or
   fe-setup when free) does the server deletions. dashboards does the frontend, the route catalog, the tests that
   ride with it, the retained list and the docs.
4. **Domain modules.** These are only called by C1 web pages, but they're cross-plane sinks: `reads/command_review`,
   `reads/command_history*`, `reads/ops_workspace/timeline`, `control/commanding/{queue,workspace}_submission`,
   `management/commanding/{stage_*,workspace_*}`, and `actions/plan_review_workflow` (+ `plane_boundary.ex:141,
   495-498`). **Ask domain** whether they go in C1 or a follow-up.

## Frontend (dashboards, side worktree with its own node_modules)
- **Delete** (HPL-only): host `ops-workspace/features/contact-workspace/*`, `timeline/{TimelinePage,TimelinePanel}.vue`
  and their tests; `frontend/modules/commanding` features `command-authoring`, `command-history`, `command-review`,
  `command-stages`, `queue-submission`, `stage-create`, `stage-workbench` and `workspace` (with their entry files and
  package exports); `mission-commands/{CommandMonitor,CommandEvidence}.vue` + `contribution.ts` + tests;
  `shared/stages`, `shared/priority.ts` and the `command-draft` editor files; the planning `*Contribution.vue`
  wrappers, `schedule-page-adapter.ts` and the fleet-planning contribution files.
- **Trim:** rj and `catalog.generated.ts` (regenerated), `module-pages/contributions.ts`, `host-navigation.ts`
  (`ops_workspace` kind), BrowserHost and its tests, the frame's nav rail (`shared/destinations.ts`: timeline,
  commands, planning and contacts point to the console; `frame/context.ts:63`), `producer-contracts.json`,
  `structural-rules.test.mjs:69` and storybook stories.
- **Keep** (shared): `frame/*`, `landing/*` and `timeline/{TimelineDestination.vue,contracts.ts}` if decision 1 keeps
  the surfaces; the `Ops*` page components and their contracts (federated); `contact.contributions.ts`
  (reservation, L14); `command-draft/{contracts,exact-values,target-label}.ts` (spacecraft commanding).
- **Links into deleted routes** that stay on the 302s or get repointed: `OpsContactDetail.vue:207` (L14) →
  `/ops/plans/:id`; `WorkspaceSettings.vue:136`, `SpacecraftCommandingPanel.vue:39,165`; `reads/spacecraft/
  configuration.ex:155` (`/ops/commands/workspace?target=`) + its validator; `settings_page.ex:14`.
- **Checks:** console + host vue-tsc, host vitest, ast-grep over packages and apps, lint/test:structure, the
  `producer-contracts` checks; the smokes to devops.
- **Docs:** `ux/information-architecture.md:176-189`, `legacy-deletion.md` (a C1 section + the status row).

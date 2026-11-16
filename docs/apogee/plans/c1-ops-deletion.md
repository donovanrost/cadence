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
| A5a/b state, search, target; A5c Load more | 3cf72bc1e | PASS; A5c unit-tested only: **accepted** (qa, lead 11-16; noted for the director) |
| A8/A9 Timeline detail, permalink, filters, paging | dashboards 04437cc3d..a71f02134, 977c6a73f | PASS 08:35Z |
| A10 plan versions + decisions | fe-setup 72d492e07 fa01362e2 | PASS 03:48Z |
| A12 Contacts History (+ Timeline links) | 0e5bdcd06..f8a79b2ca | PASS 08:28Z (follow-up for qa's future-date note in review) |
| A16a offer details; A16b routes | 84aed5aa0; 11f733e61 | PASS 03:30Z; PASS ~04:50Z |
| R1 server-resolved arguments (C-condition) | fdb139d5a c60a64ab5 c0588977d | **pending**: a real awaiting-approval request made through Compose by a real operator (qa); never seeded |
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
| `/ops/commands/requests/:id`, `…/queue` | `/commands/<group id>/review`: the console's `:requestId` is a COMMAND GROUP id (`RequestScreen` reads `/command-groups/:id`), so the redirect looks up the request's group (fe-ops); a 302 keeping the request id would 404 |
| `/ops/commands/requests/:id/history` | `/commands/<group id>/uplink` (attempts + evidence), same lookup |
| `/ops/contact-workspace`, `…/records/:id` | `ops.contacts`, `ops.contacts.history?contact=<id>` |

**Retained** (still render; each names who keeps it): `/ops/alarms` (C2), `/ops/contacts/:provider_reservation_id`
(L14), `/ops/data-operations[/manage]`, `/ops/explore`, `/ops/activations` (L10's own batch), `/ops/telemetry/explore`.
The ops frame (`host/src/ops-workspace/features/frame/*`) stays: it wraps every retained /ops page.

## Rulings (lead 11-16, after fe-ops' review)
1. **Delete the federated `ops_console` surfaces of every C1 page in the same batch** (the L1–L4 federated
   precedent); no `retained-legacy-routes.json` comeback. Surfaces: `workspace`, `contact_schedule`,
   `contact_plan_show`, `contact_record`, `fleet_planning[_new|_run]`, `commands`, `timeline`
   (`applications/ops_console.ex:26-110,199-205`; Vue `apps/ops-console/src/Ops*.vue`). **The app stays**:
   `installation_policy: :platform`, it carries the `commanding.defaults` settings section and the retained
   surfaces. **Console embedding check:** the console mounts only `setup`-area surfaces (`features/apps/
   surfaces.ts:6`); of C1's surfaces only `workspace` is `application_workspace` (= setup), so Setup › Apps lists
   "Ops Console" with that surface today and loses it in C1. Nothing else in the console embeds them (no static
   reference to `ops_console` in `apps/console/src`; the federation canary is devops' fixture app since 987034f1e).
2. **devops updates the legacy federation smoke in the batch** (`federation_browser_smoke.mjs:5245`, contract
   `:3209`: the `commands` surface and its `/ops/commands` assertion): a new canonical surface, or drop it if no
   legacy ops surface survives.
3. **Split:** api writes the redirects (as L1–L11, with the command group lookup above); **fe-setup does the server
   deletions once (B) is live**; dashboards does the frontend, the route catalog, the retained list and the docs.
4. **Domain's C1-only sinks go in a follow-up domain batch after C1 is live** (domain lists them now):
   `reads/command_review`, `reads/command_history*`, `reads/ops_workspace/timeline`,
   `control/commanding/{queue,workspace}_submission`, `management/commanding/{stage_*,workspace_*}`,
   `actions/plan_review_workflow` (+ `plane_boundary.ex:141,495-498`).

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
  `/ops/plans/:id`; `WorkspaceSettings.vue:136`, `SpacecraftCommandingPanel.vue:39,165`; `settings_page.ex:14`;
  `reads/spacecraft/configuration.ex:155` (`/ops/commands/workspace?target=<sc>`) + its validator: **repoint to
  Compose `ops.commands.new?targets=sc:<spacecraft id>`** (preselects the craft; fe-ops).
- **Checks:** console + host vue-tsc, host vitest, ast-grep over packages and apps, lint/test:structure, the
  `producer-contracts` checks; the smokes to devops.
- **Docs:** `ux/information-architecture.md:176-189`, `legacy-deletion.md` (a C1 section + the status row).

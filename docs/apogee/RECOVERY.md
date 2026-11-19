# Team recovery after a machine reboot

Written 2026-11-14 21:08Z by the director, before a user-initiated reboot. If herdr doesn't restore the
panes, recreate them and resume each agent with its Claude session.

## How to resume an agent

```sh
cd <worktree>
claude --resume <session-id>
```

Then tell it: "[from director] Machine rebooted. Re-read your last handoff in docs/apogee/RECOVERY.md and
continue."

## Sessions (from herdr's pane records, 21:08Z)

| Name | Role | herdr pane | Worktree (cwd) | Claude session id |
| --- | --- | --- | --- | --- |
| director | Orchestrator (main session) | `w0Q:p1` | `~/.herdr/worktrees/cadence/worktree-see-what-claude-can-do` | `417229aa-0c4f-4e9a-91e9-ec15ea8e7d6c` |
| lead | Tech lead | `w0R:p1` | `~/.herdr/worktrees/cadence/ui-apogee-spa` | `9329f570-096e-40ac-9539-fcffbe8ba183` |
| ux | UX / design system | `w0R:p2` | `ui-apogee-spa` | `fc79d3fb-be3b-4d88-9fe1-f9f5fed9b604` |
| api | Backend API | `w0R:p3` | `ui-apogee-spa` | `8e49aebc-1e3a-4680-8d60-c2f3900e8a92` |
| fe-ops | Frontend, Ops | `w0R:p4` | `ui-apogee-spa` | `ba9c2ff8-42ab-48ee-8fe4-2fd33b44d05c` |
| fe-setup | Frontend, Setup | `w0R:p5` | `ui-apogee-spa` | `e9127bd3-3816-46f3-9a09-f46b3a156d0a` |
| qa | QA, owns the dev stack | `w0R:p6` | `ui-apogee-spa` | `18d0f7b0-f396-4e7b-9deb-a084ced831ba` |
| domain | Domain model | `w0R:p8` | `ui-apogee-spa` | `c35dac59-0d54-454b-a49c-ba978078808e` |
| api-ops | Backend, Ops/commanding | `w0R:pC` | `ui-apogee-spa` | `b214f0a1-97ce-4069-96f5-82b8047d88f4` |
| dashboards | Dashboards rebuild | `w0R:pG` | `ui-apogee-spa` | `e463b19f-daed-4d3f-8e87-2623237965e6` |
| devops | CI on GitHub Actions | `w0S:p1` | `~/.herdr/worktrees/cadence/ci-github-actions` | `a6d07257-f64b-4ab0-85dd-34cbb0686b85` |
| credo | Credo burn-down (finished) | `w0T:p1` | `~/.herdr/worktrees/cadence/chore-credo-scope-burndown` | `00974bb7-5c8e-44ae-893a-bf2f1f94904b` |

Non-agent qa panes in `w0R` (the dev stack): `qa-server` (`:4011`), `qa-console-vite`, `qa-simulator`
(`:4111`), `qa-live-feeds`. qa restarts these; see qa's restart order below.

pane ids will change if herdr recreates panes; update `docs/apogee/ROSTER.md` after recovery.

## Dev stack restart order (qa)

Stack shut down cleanly 21:13-21:15Z (qa): `:4011` stopped gracefully (drain: contacts 0, journals
[]); the simulator stopped gracefully; the cadence-apogee-questdb container stopped; Postgres stopped
with `pg_ctl stop -m fast` (pg_controldata "shut down", checkpoint 67/7C894AB8); the brew service is
unloaded. No ports open. Next pass after the reboot: 00:13:49Z.

After boot, in order (qa does this on resume):
1. OrbStack up; `brew services start postgresql@14`; check `SHOW max_connections` = 200.
2. `docker start cadence-apogee-questdb`; ports 9200/8822 answer.
3. Simulator in pane w0R:pA (the runbook line, `--sname qa_sim`); run offset 0.
4. `:4011` in pane w0R:p7 (the runbook START line, OTEL cleared after mise). Post-checks: log level
   :info, admspec gen 8, journal on, modified_modules [], QuestDB env, 0 errors, no reconciler
   terminations, repair dry run still only 4NYUX = recheck.
5. The main checkout's `:4001` is the user's to bring back.

Note: OrbStack's Kubernetes will likely bring the user's `cadence-chaos` lab back too (it has
filled the disk before); the user decides whether to stop it.

## Handoffs (each agent, before the reboot)

_Each agent's 2-3 line handoff goes here as it arrives._

- **ux** (`fc79d3fb…`, confirmed): nothing uncommitted (last b67c5a598). Waiting on others: U57
  rejected-booking Now item (domain, after the "delivery unverified" decision), U56 window_moved
  timeline (api's sentence), U54 nouns and U53 switch (landing via qa). Open asks: Book-a-pass copy
  review once off its flag; fe-setup's app-surface frame, 5-link cap, Gantt legend, policy panel
  fixes. After resume: reread `ux/decisions.md` U53-U57, then answer queued pane messages.
- **lead** (`9329f570…`, confirmed): nothing uncommitted; BACKLOG current at 8d9063387. Waiting on the
  00:13:49Z sim session-start line, qa's 4NYUX post-check ~06:51Z, and 11-15's first restart (preview
  fix + 1b43c321c + api U55 + fe-ops L1-L4). After resume: re-read BACKLOG §0, confirm each agent
  resumed with its queue (domain, fe-setup, api-ops rows), then route qa's first-restart slot.
- **api-ops** (`b214f0a1…`, confirmed): nothing uncommitted, no side worktrees. Landed today: #90,
  catalog rerun-safe, the sim session-start log (d1536906b, live since the 19:44Z sim restart).
  Waiting: qa's grep for the first "Session started for" line at the 00:13:49Z pass; domain's
  reconciler cadence proposal (tomorrow); the QuestDB P1 suite (c9f2199d0 on test/questdb-ingest),
  never run against a real QuestDB (needs disk or CI). After resume: re-read pane traffic, check qa's
  session-start line, review domain's proposal when it arrives.
- **dashboards** (`e463b19f…`, confirmed): nothing uncommitted; last ab3c7ed48 (never-started reader),
  1e44feb54 (L8 status). L8 done apart from domain's table drop. Waiting: qa's live checks of section
  editing (non-empty remove + start collapsed), the ChartMarker union c7bc1ee7f and booking rule
  30626f98f, domain's never-started frame 1b43c321c in a restart (then ZKgUX), limits after the flip.
  After resume: read herdr messages from qa/domain/lead, then answer whichever check comes back.
- **fe-ops** (`ba9c2ff8…`, confirmed): nothing uncommitted. Side worktree fe-ops-l1l4 is clean; branch
  fe-ops/l1l4-federated (9 commits, tip 1f8357fb9) has the director's GO for 11-15's first restart,
  after domain and api at qa's node-down. Waiting: U54/U55/U56/U51 servers (readers committed). After
  resume: wait for qa's node-down call, cherry-pick -x L1-L4, compile, send SHAs; then repoint the 5
  legacy links to console routes (this week).
- **api** (`8e49aebc…`, confirmed): nothing uncommitted; side worktree api-held is clean. Waiting: U55
  3bacc837b (branch api/u55-on-ab) for 11-15's first restart (SHA with qa); L10/L12/L13 redirects
  5f78be8dd/305de0c82/88baf9ef8 (branch api/legacy-l10-l12-l13) with fe-setup's deletion batch,
  after qa's live checks and the director's go. After resume: check panes for qa/lead/domain, then
  wait for qa's slot call for U55. The step 4 preview endpoint waits on domain's findings.
- **fe-setup** (`e9127bd3…`, confirmed): nothing uncommitted, no side worktrees; today's work is live
  (b23 + U53 + fix + L8c; docs 510c00d18). Next: the L10/L12/L13 deletion. Recipes agreed with
  qa/api/domain/api-ops (L10 on mission_fyyx5ju6zm_3ESL; L12/L13 on a new QA-org mission, Event
  Ingestion "Disabled"); api's redirects ready. After resume: wait for qa's live checks of those
  three, build the batch in a new side worktree with its own node_modules, then the director's go.
  After that, §11c's covered-already pages.
- **domain** (`c35dac59…`, confirmed): nothing uncommitted. Landed tonight: window truth
  (f65fa86ff..bdf661a05) and the hot-loop fix 881e19e8c. Parked on branches in worktree
  domain-77-stage3: the preview fix (domain/profile-preview-scale: 7bb725650, fa0ecabf2, ab0842686,
  72d340c1f), the never-started frame (1b43c321c, domain/never-started-frame), the reconciler
  proposal notes (87a551fda, domain/reconciler-cadence, including qa's WAL baseline; the /tmp copy is
  lost on reboot). After resume, in lead's order: be on hand for the first restart (preview fix +
  1b43c321c), then the inbox nit, then the reconciler proposal to api-ops.
- **devops** (`a6d07257…`, confirmed): nothing uncommitted, nothing running; work on branches, none
  pushed. Pending the director: the Postgres doc 8590c0c53 (journal-off 20b8ad421 is already merged as
  #92). Pending the user's merge decision: f426e26d5, the team PR, the host.js pin. Timers (flake
  tracker until 11-20, the disk samples) die with the reboot; the tracker, its state and the scripts
  are copied to `ci-github-actions/.devops-scratch/` (untracked, with HANDOFF.md). After resume:
  re-create the timers from HANDOFF.md, run the tracker once, take the overdue disk sample.
- **qa** (`18d0f7b0…`, confirmed): nothing in flight; tonight's work (restart b, L8c, the hot-loop fix
  881e19e8c, the baseline, WAL, sim #2) is logged in `var/qa-pass-checklist.txt`. Nothing
  uncommitted; dry-b-wt removed. After resume: restart the stack (order above), the runbook
  post-checks, grep the sim log for the first "Session started for" line (the 00:13:49Z pass), the
  4NYUX post-check (~06:51Z; from the DB if it's past), the WAL "before" windows, then 11-15's first
  restart.
- The uncommitted `docs/apogee/plans/dashboards-settings.md` was fe-setup's, committed as 260247244.
  Nothing else is uncommitted in the shared tree.

## Things that do NOT survive a reboot

- Scheduled wake-ups and background monitors inside agent sessions (devops' browser-flake tracker,
  running until ~11-20; qa's pass watchers). Each owner restarts its own after resume.
- `caffeinate`/Amphetamine sleep prevention.
- The stuck `coreaudiod` (a reboot clears it).

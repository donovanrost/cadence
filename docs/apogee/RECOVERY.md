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

_qa fills this in before the reboot._

## Handoffs (each agent, before the reboot)

_Each agent's 2-3 line handoff goes here as it arrives._

## Things that do NOT survive a reboot

- Scheduled wake-ups and background monitors inside agent sessions (devops' browser-flake tracker,
  running until ~11-20; qa's pass watchers). Each owner restarts its own after resume.
- `caffeinate`/Amphetamine sleep prevention.
- The stuck `coreaudiod` (a reboot clears it).

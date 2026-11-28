# Cadence engineering team

Written by the CTO on 2026-11-25. This replaces the Apogee-era `docs/apogee/{TEAM,ROSTER,RECOVERY,BACKLOG}.md`
and the per-agent briefs. Those rules (qa slots, holds, landing on `live/develop`, chain owners, freezes,
the shared worktree, "Refs not Closes") are **repealed**. Git history has them if you need context.

## What we are building

Cadence: a multi-tenant platform for constellation-scale spacecraft operations. **500 spacecraft is the floor**,
and nothing should have a hard ceiling. The **console** (`frontend/apps/console`, Vue 3 + `packages/apogee-ui`)
is the UI. Everything else UI-side is legacy and is being deleted.

## Ground rules

1. **No legacy code.** This is a development environment with no users. No backwards compatibility, no shims,
   no fallbacks, no deprecation periods, no migrations to preserve dev data. When something is replaced,
   delete the old thing in the same PR or the next one. When the model is wrong, fix the model.
2. **Dev data is disposable.** Dropping and recreating a database or QuestDB is always fine. Seeds rebuild it.
3. **Scale is a requirement, not a phase.** Every list, read model, channel and job must hold up at 500
   spacecraft: paginate, aggregate in the database, no per-spacecraft fan-out in request paths, no
   unbounded `Repo.all`. If you can't show it holds, say so in the PR.
4. **Real data only** in the console. If the backend lacks something, add it, or show an honest empty state.
5. **Public repo.** No emails, tokens, passwords or cookies in issues, PRs, commits' bodies or docs.

## Organisation

The CTO sets priorities and owns the org. Each **Head** owns an area end to end: backend domain, API,
the console screens for it, tests, the legacy pages it retires, and its 500-spacecraft behaviour.
Heads are working engineers and may hire and fire within their headcount (below).

| Head | Handle | Machine | Owns |
| --- | --- | --- | --- |
| Platform | `platform` | laptop 1 | CI (develop stays green), dev environment (per-worktree stack, seeds), build/test tooling, the scale harness (simulator at 500-1,000 spacecraft, benchmarks), `platform/`, `persistence/`, `jobs/`, `observability`, cluster runtime, migrations hygiene |
| Console | `console` | laptop 1 | `frontend/` (console shell, router, API client, `apogee-ui`, design system, words, a11y); **deleting the federated apps and host**; console-wide quality and performance. Domain heads build their own screens; console sets the patterns and reviews them |
| Commanding & Approvals | `commanding` | laptop 2 | commanding, approvals/four-eyes, identity, accounts, organizations, secrets, authz. **Security reviewer** for every PR touching permissions, approvals, secrets or tenant boundaries |
| Mission Model & Spacecraft | `mission-model` | laptop 2 | mission models, catalog/XTCE, spacecraft, spacecraft profiles, configuration, activations, applications, the change-set framework |
| Telemetry & Data | `telemetry` | laptop 2 | ingest, decom, projections, QuestDB storage and retention, replay, derived telemetry, calibration, limits and alarms, dashboards backend |
| Ground & Comms | `ground` | laptop 1 | contacts, pass prediction, scheduling/planning, ground networks, providers, links/transports, routing |

Path ownership follows the domain: the file or folder name says whose it is. Shared files (`router.ex`,
`application.ex`, `mix.exs`/`mix.lock`, `config/`, the console route list) can be edited by anyone for their
own lines; Platform (backend) or Console (frontend) reviews.

### Headcount

- Total live agents across both machines: **16**, including the CTO. Per machine: **6** on laptop 1 (it
  swaps under load, which skewed ground's timings 4-12x, so it takes no more), **10** on laptop 2.
- **Headcount is frozen at 16** (CTO, 2026-11-28): no new hires on either laptop. legacy-eng is fired when #672 lands.
- **Codex** may be hired for backend, infra, CI, data and scale work. **Never for frontend or UX.**
- Pick model and effort for the job: Heads and design/security work on Claude Opus, high effort. Well-scoped
  frontend work on Claude Sonnet or Opus. Backend implementation work: Codex (high) or Claude Sonnet.
- Record every hire and fire in the Roster below in the same day (PR to develop, docs-only).

### Hiring

Each agent gets its own worktree off `origin/develop` and its own hc terminal, named by handle.

```sh
# laptop 1 (add --on donovans-macbook-pro-1 for laptop 2; its repo is ~/projects/cadence/cadence,
# worktrees go in ~/projects/cadence/worktrees/<handle>)
git -C <repo> fetch origin && git -C <repo> worktree add --detach <worktrees>/<handle> origin/develop
(cd <worktrees>/<handle> && mise trust)        # without this, node is missing and hooks fail
# start a login shell (so mise's PATH applies), then the agent inside it
# herdr.space makes the terminal visible in the user's herdr-app: laptop 1 sp58a63cab3ed4d89afb805669510138a9
# (Apogee team), laptop 2 sp1603e397e561f3fd4f4373b657db0f1d. Forgot it? hc label <handle> herdr.space=<id>.
hc run --bg --name <handle> --no-parent --no-notify --keep --label team=cadence --label head=<your handle> \
  --label herdr.space=<id> --cwd <worktrees>/<handle>
hc send <handle> "claude --model <model> --effort <level> --permission-mode auto"
# Codex instead: sandboxed to its worktree, approvals off (it never blocks on a dialog). <git> is the
# main repo's .git (~/projects/cadence/cadence/.git on both laptops); a worktree's HEAD,
# refs, config and objects live there. Verified in the sandbox: gh, mix deps.get, git commit/push/branch -D, docker,
# a targeted mix test against local Postgres.
# Its sandbox lets it push anywhere the account can: its brief must say "push only <handle>/* branches;
# never push develop or main" (until #206 protects them).
# hc send <handle> "codex -s workspace-write -a never -c model_reasoning_effort=high \
#   -c sandbox_workspace_write.network_access=true \
#   -c 'sandbox_workspace_write.writable_roots=[\"<git>\",\"<git>/worktrees/<handle>\",\"$HOME/.hex\",\"$HOME/.mix\",\"$HOME/.cache\",\"$HOME/Library/pnpm\"]'"
hc send <handle> "<brief: role, area, first task, pointer to docs/TEAM.md>"
```

Laptop 1 worktrees live in `~/.herdr/worktrees/cadence/<handle>`. The new agent runs `mix deps.get`
(and `pnpm install` under `frontend/` for frontend work) in its worktree.

### Firing

1. Make sure the agent's work is pushed (or deliberately abandoned).
2. `hc kill <handle>` then `hc rm <handle>`.
3. `git worktree remove <path>`; delete its local branches once merged; drop its dev databases.
4. Update the Roster.

## How work flows

- **Trunk is `develop`.** Every change is a short-lived feature branch off `origin/develop`, in your own
  worktree, one issue per branch, small PRs. Never push to or force-push `develop` or `main`.
- **Merge gate:** green CI + one review by a different agent recorded on the PR as a comment headed
  `[<handle>] VERDICT: APPROVE|CHANGES at <sha>` (we share one GitHub account). Cross-area changes also need
  that area's Head. Security-sensitive changes also need `commanding`. Then **the owning Head merges**
  (squash). The Head reviews their hires' PRs; Heads review each other's.
  Merge with `gh pr merge <n> --squash`, then `git push origin --delete <branch>`. **Never
  `--delete-branch`**: it also deletes the local branch, which removes another agent's worktree if the
  branch is checked out there (platform-eng's, 11-26).
- **Closing:** `Closes #N` in the PR body is fine. Merged means done; there is no separate landing step.
- **Red develop:** Platform owns it. A PR that turned develop red is reverted first and fixed after.
- **CI is the scarce resource** (about 20 runner slots for the whole team). Open every PR as a
  **draft**; drafts run no CI. Mark it ready for review when you want CI and a review. Push in batches,
  not commit by commit. Rebase a stale PR only when it's about to merge.
- **Local checks before a PR:** `mix format`, compile with `--warnings-as-errors` for the apps you touched,
  `mix credo --strict` on touched files, the tests for the area you touched. Frontend: lint, typecheck and the
  tests for touched files. **Full suites run in CI**, not locally (16 GB laptops).
- **Dev scripts:** when a change affects `dev/`, run `MIX_ENV=test mix run --no-start --no-compile ../../scripts/ci/check_dev_scripts.exs`
  from `apps/cadence_simulator` after compiling the apps. The check compiles scripts without running entrypoints.
- **Dev stack:** per worktree, when you need one: your own database name, port and simulator. Nobody depends
  on a shared stack. Platform owns the scripts.
- **Board:** GitHub project 3 (https://github.com/users/donovanrost/projects/3). Issues live under their epic
  (#207-#219), have a type label and a domain label, and an Owner. Keep your own cards' Status current.
  Write issues plainly: story / bug / task.

## Communicating

- `hc send <handle> "[from <you>] <message>"`. From laptop 1, laptop-2 agents are `donovans-macbook-pro-1/<handle>`;
  from laptop 2, laptop-1 agents are `laptop1/<handle>` (the CTO is `laptop1/t11`).
  Keep it to a few lines; longer things go in the issue or PR and you send the link.
- Never ask a question as a dialog in your own terminal; nobody watches it. Send it to whoever decides with
  `hc send`. For the CTO that's `t11`, or `laptop1/t11` from laptop 2.
- Tell the CTO (`t11` on laptop 1, handle `cto`) about: a milestone done, a blocker you can't clear, a decision
  above your area, a hire or fire. Not routine progress; that goes on the board.
- If a session dies or the machine reboots, each agent's worktree and branch are the recovery point.

## Priorities (2026-11-25)

1. **Develop green** (Platform, today).
2. **Retire legacy UI** (epic #209): every LiveView operations page and every federated app (`frontend/apps/host`,
   `comms-overview`, `mission-catalog`, `organization-admin`, `spacecraft`, `telemetry-decom`, `ops-console`,
   `surface-fixture`, `contract-probe`, `packages/ui`, `plugin-sdk`, `legacy/`) is deleted once the console
   covers what it did. Domain Heads retire their pages; Console retires the host, shells and shared packages.
3. **Scale baseline**: Platform builds a 500 and 1,000 spacecraft simulator load; Telemetry and the other Heads
   measure their paths against it (epic #217, M8).
4. **Domain epics**, each Head in their own order.
5. **Stale PR triage**: each Head merges or closes the open PRs in their area within their first day.

## Roster

| Handle | Role | Machine | hc address | Model | Hired |
| --- | --- | --- | --- | --- | --- |
| cto | CTO | laptop 1 | `t11` | Claude Opus 5.5 | 2026-11-25 |
| platform | Head of Platform | laptop 1 | `platform` | Claude Opus 5.5, high | 2026-11-25 |
| console | Head of Console | laptop 1 | `console` | Claude Opus 5.5, high | 2026-11-25 |
| console-eng | Frontend engineer, Console (head: console) | laptop 1 | `console-eng` | Claude Opus 5.5, high | 2026-11-25 |
| ground | Head of Ground & Comms | laptop 1 | `ground` | Claude Opus 5.5, high | 2026-11-25 |
| ground-scale | Engineer, Mission Model & Spacecraft (head: mission-model; moved from ground 2026-11-28 for the overhaul) | laptop 2 | `donovans-macbook-pro-1/ground-scale` | Codex, high | 2026-11-25 |
| commanding | Head of Commanding & Approvals | laptop 2 | `donovans-macbook-pro-1/commanding` | Claude Opus 5.5, high | 2026-11-25 |
| mission-model | Head of Mission Model & Spacecraft | laptop 2 | `donovans-macbook-pro-1/mission-model` | Claude Opus 5.5, high | 2026-11-25 |
| telemetry | Head of Telemetry & Data | laptop 2 | `donovans-macbook-pro-1/telemetry` | Claude Opus 5.5, high | 2026-11-25 |
| mm-engineer | Engineer, Mission Model & Spacecraft (head: mission-model) | laptop 2 | `donovans-macbook-pro-1/mm-engineer` | Claude Sonnet, high | 2026-11-25 |
| telemetry-eng | Engineer, Telemetry & Data (head: telemetry) | laptop 2 | `donovans-macbook-pro-1/telemetry-eng` | Claude Sonnet, high | 2026-11-26 |
| commanding-eng | Engineer, Commanding & Approvals (head: commanding) | laptop 2 | `donovans-macbook-pro-1/commanding-eng` | Claude Sonnet 5.5, high | 2026-11-26 |
| platform-eng | Engineer, Platform (head: platform) | laptop 1 | `platform-eng` | Codex, high | 2026-11-25 |
| platform-sim | Engineer, Platform (head: platform) | laptop 2 | `donovans-macbook-pro-1/platform-sim` | Codex, high | 2026-11-26 |
| ground-eng | Engineer, Ground & Comms (head: ground) | laptop 2 | `donovans-macbook-pro-1/ground-eng` | Codex, high | 2026-11-26 |
| legacy-eng | Engineer, legacy UI deletion: #668, #672 and the frontend halves of pure deletes, with each owner's consent (head: console) | laptop 2 | `donovans-macbook-pro-1/legacy-eng` | Claude Opus 5.5, high | 2026-11-27 |

Codex (0.172.0) is installed and signed in on both laptops, under the node version `mise.toml` pins; a Codex
hire can go on either machine. If that pin moves, install Codex for the new node version too.

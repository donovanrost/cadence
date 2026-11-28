# CI plan: GitHub Actions for Cadence

Owner: devops. Status: **reviewed by the director, 2026-11-11**; delivery step 1 starts next.
Branch `ci/actions-develop`, based on `origin/develop` f9d89f83 (see
[Housekeeping](#housekeeping)).

Decided (director, 2026-11-11): Q4 yes, production console build in CI; Q6 yes, devops diagnoses
the federation `integrity_failure` in delivery step 2; Q7 yes, `mix hex.audit` as a
non-blocking step in `quality`.

Decided (user, 2026-11-11): Q1 yes, `ci-ok` becomes required on `develop` **and** `main` after
two green runs. Q3: pin OTP 29.0.5 / Elixir 1.20.4 in `mise.toml` as the one source of truth;
CI reads the pins from it and `frontend.yml` is aligned, in a commit of its own. Q5: all specs
run with writes gated off; the mutating serial job comes later. Q2 is pending the breakdown of
the 46 findings (43 mechanical; 2 `CyclomaticComplexity`, 1 `Nesting`; no TODO/FIXME tags).

Goal: PRs to `develop` and `main` get fast, trustworthy required checks, well under 15 min of
wall clock. Build order is **Elixir first** (phases 1–3), then the Apogee console and its full
browser e2e suite (phase 4).

## CI capacity measurement, 2026-11-28 UTC (#1030)

Fixed sample of 200 `pull_request` runs of `ci.yml`, from [45899244496](https://github.com/donovanrost/cadence/actions/runs/45899244496)
(2026-11-26 21:35:58 UTC) through [46102662313](https://github.com/donovanrost/cadence/actions/runs/46102662313)
(2026-11-28 03:24:01 UTC). The cutoff was 2026-11-28 03:28:50 UTC. The
reference `develop` commit was `37075aab150fd0121a25f7ea72e5119dd3407efb`.

Current concurrency groups runs by PR number and enables `cancel-in-progress`
for `pull_request` events. Push runs keep their own ref group and finish so
they can publish caches.

The sample uses the Actions REST endpoints for workflow runs, jobs with
`filter=all`, and 104 completed attempt log archives retrieved once. Runner
minutes sum `completed_at - started_at` across allocated jobs. Phase times use
step timestamps and nested cache logs. For 798 test steps, the time before the
first recognizable ExUnit or Playwright banner counts as setup. Test/check time
can include setup inside steps with no such marker. Other time includes evidence
uploads, teardown, and unclassified runner time. Queue time uses each job's
`started_at - created_at` where both timestamps are usable. The table includes
all 1,950 launched jobs in the counts and times the 1,931 completed by the cutoff.
[Workflow runs API](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow)
[Workflow jobs API](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run)

**5,268.3 runner-minutes** across the sample, or **26.3 per workflow run**
including drafts and cancellations. Among 97 completed first attempts with a
positive code gate and a required verdict, median runner cost was **54.3 min**
(p90 **71.0 min**). Their wall clock from creation to the last job was **16.9 min**
(p90 **36.4 min**). The first-runner wait across started runs was **0.3 min**
median and **3.4 min** p90. Of 1,894 measurable job waits, **652** were at
least one minute.

### Job costs and actual path decisions

| Job | Workflow runs / jobs | Setup min | Cache restore min | Test / check min | Other min | Runner min | Queue median / p90 min | Run median min | Path skips / ran with gate false |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Console e2e | 87 / 180 | 487.4 | 34.3 | 1,036.6 | 18.1 | 1,576.4 | 0.1 / 8.8 | 7.8 | 4 / 0 |
| Core tests | 90 / 185 | 241.9 | 20.9 | 509.8 | 14.4 | 787.0 | 0.1 / 9.9 | 4.2 | 15 / 0 |
| Web tests | 92 / 188 | 281.4 | 20.1 | 257.4 | 14.2 | 573.1 | 0.1 / 10.8 | 3.0 | 15 / 0 |
| Federation browser | 87 / 180 | 290.2 | 36.3 | 32.3 | 18.4 | 377.2 | 0.1 / 9.1 | 1.9 | 4 / 0 |
| Packages, simulator, planes and cluster tests | 91 / 94 | 124.4 | 9.1 | 176.6 | 6.0 | 316.2 | 0.1 / 7.4 | 3.2 | 15 / 0 |
| Browser assets (built once) | 103 / 107 | 92.9 | 15.8 | 166.5 | 9.8 | 284.9 | 0.1 / 9.0 | 2.6 | 4 / 0 |
| Web tests needing the federation publication | 87 / 90 | 129.2 | 9.9 | 101.3 | 6.0 | 246.3 | 0.1 / 8.1 | 2.6 | 4 / 0 |
| Elixir quality | 89 / 92 | 50.9 | 5.5 | 166.3 | 4.7 | 227.5 | 0.1 / 9.5 | 2.0 | 15 / 0 |
| Ingest tests, journal off | 90 / 93 | 123.4 | 10.8 | 72.5 | 7.2 | 214.0 | 0.1 / 10.2 | 2.1 | 15 / 0 |
| QuestDB integration | 91 / 94 | 99.6 | 6.4 | 71.7 | 7.2 | 184.9 | 0.1 / 9.8 | 1.7 | 15 / 0 |
| REST seed smoke | 90 / 93 | 154.8 | 4.9 | 16.3 | 6.3 | 182.3 | 0.1 / 11.5 | 1.9 | 15 / 0 |
| Frontend quality | 31 / 33 | 27.3 | 2.1 | 121.2 | 2.4 | 152.9 | 0.1 / 12.0 | 4.9 | 73 / 0 |
| JS dependency audit | 100 / 104 | 17.7 | 0.0 | 76.0 | 6.0 | 99.7 | 0.1 / 7.8 | 0.9 | 4 / 0 |
| Repository hygiene | 106 / 110 | 12.7 | 0.0 | 1.0 | 5.9 | 19.7 | 0.1 / 8.3 | 0.2 | — |
| Detect code changes | 111 / 115 | 2.6 | 0.0 | 6.5 | 4.9 | 14.0 | 0.1 / 1.2 | 0.1 | — |
| ci-ok | 189 / 192 | 0.2 | 0.0 | 3.4 | 8.5 | 12.2 | 0.1 / 2.8 | 0.1 | — |

The path column counts attempts where the recorded gate was false. It includes
101 attempts with explicit filter logs and four reruns that reused their
original `changes` job. Four explicit attempts were docs-only. There were 67
with the backend gate alone among the two scope gates, ten with the frontend
gate alone, and 20 with both. No job launched against a false recorded gate.

The broad code gate still ran **83 JS dependency audit jobs** on attempts with
no package manifests, lockfiles, package-manager config, or CI paths in the
reported changes. Those jobs used **80.1 min**. Advisory data can change between
commits, so narrowing that gate would change which failures are caught and
needs approval.

### Cancellations, reruns, and stale bases

| Observation | Count | Runner-minutes |
| --- | ---: | ---: |
| Canceled workflow runs | 68 | 1,336.1 |
| Likely superseded, with a newer run on the same head branch before cancellation | 62 | 1,335.9 |
| Likely superseded by a changed head SHA | 37 | 1,333.6 |
| Additional attempts | 4 | 204.0 |
| Attempts with the stale base warning | 12 of 28 with a recorded tested base and live tip | 482.0 |
| Confirmed draft attempts | 85 | 5.3 |

The cancellation rows overlap. Supersession is inferred from creation and
cancellation timestamps grouped by head repository and branch. Those elapsed
minutes accrued before cancellation became effective. Warned attempts include
successful jobs and describe the age of the tested base. Each confirmed draft
allocated a runner for `ci-ok` only.

### Cache observations and the long pole

| Restore | Exact | Fallback | Miss | Median restore, min |
| --- | ---: | ---: | ---: | ---: |
| Mix deps | 1,249 | 0 | 0 | 0.02 |
| `_build` | 0 | 1,249 | 0 | 0.04 |
| pnpm store | 932 | 48 | 0 | 0.06 |
| Playwright | 345 | 0 | 0 | 0.06 |
| npm cache | 413 | 0 | 0 | 0.03 |

Cache counts use completed restore actions with a recorded outcome. The cohort
had no complete cache misses to estimate a cold penalty. The `_build` fallbacks
satisfied restore requests under the current policy of publishing from base
branch pushes.

Console e2e shard 2 took **13.5 min** median and **15.0 min** p90 on successful
jobs. Shard 1 took **6.6 min** median and **8.2 min** p90. The fleet-scale budget
step on shard 2 accounted for about **463 runner-minutes**. Keep that check and
its isolated execution when evaluating shard balance.

The first setup cut to verify is the LiveView npm install in the browser artifact
consumers. The measured steps spent **27.7 min** in Console e2e and **28.6 min**
in Federation browser. Both consume a prebuilt artifact from the job that
already installs those dependencies. Verify that both suites can run from the
artifact before removing consumer setup. The recorded steps provide a
**56.3-minute upper bound** across this cohort. Measure the post-change jobs
before reporting realized savings.

## What exists today

| Thing | State |
| --- | --- |
| `.github/workflows/frontend.yml` | Frontend quality (`pnpm verify`, ~5.5 min) + Phoenix producer contracts and federation browser (~16 min). **The last two PR runs (#37, #38) failed and merged anyway.** The federation job fails in `FederationReleaseFixture.prepare_and_activate!` with `activate_catalog → {:error, %{code: :integrity_failure}}` (5 tests). Not yet diagnosed; see open question 6. |
| Elixir CI | None. Format, compile warnings, credo and the per-app suites run only on developers' machines (hk `precommit.affected`). |
| Branch protection | None on `develop` (API 404). No check is required today. |
| Runners | Repo is **public**, so `ubuntu-24.04` standard runners have 4 vCPU and 16 GB, minutes are free, and the account can run **20 concurrent jobs**. |

Reference timings from this repo's own Actions history (4-vCPU runners, **no warm cache**):

| Run | Step | Time |
| --- | --- | --- |
| CI, 2026-08-30 (old serial attempt) | deps fetch | 4:45 |
| | compile `--warnings-as-errors` + credo + workspace/architecture checks (cold) | 5:40 |
| | all suites (smaller codebase then) | 2:24 |
| Frontend, 2026-11-08 | `mix setup --check-locked` | 1:55 |
| | `pnpm test:producers` (cold test compile + producer tests) | 7:03 |
| | `mix test.browser.federation` | 4:57 (failed) |
| | `pnpm verify` | 4:31 |

## Job graph

One workflow, `ci.yml`, for phases 1–3, with a single aggregate required check. `frontend.yml`
stays as it is until phase 3 folds it in (it needs the same caches and the publication
artifact).

```
pull_request (develop, main) · push (develop, main) · workflow_dispatch

changes ──────────┐  dorny/paths-filter: elixir / frontend / docs-only
                  │
publication ──────┼──────────────┐  frontend build:publication → artifact "application-host"
quality ──────────┤              │  format · compile --warnings-as-errors · credo gate ·
                  │              │  workspace.check · extensions.check · architecture.check
test-core [1..2] ─┤              │  apps/cadence, mix test --partitions 2
test-packages ────┤              │  ccsds · xtce · cadence_catalog · cadence_simulator ·
                  │              │  test.planes · test.cluster
test-web [1..2] ──┴── needs ─────┘  apps/cadence_web, mix test --partitions 2
        │
ci-ok  (needs: all of the above; if: always(); fails if any needed job failed or was cancelled)
```

- **`ci-ok` is the one required check** for branch protection. Jobs skipped by the path filter
  count as success, so docs-only PRs pass quickly, and adding or removing jobs never means
  editing branch protection.
- Repository hygiene is a `ci.yml` job in `ci-ok`'s `needs`. It verifies that
  `mise.local.toml` stays ignored and scans only PR commits with a checksum-pinned
  gitleaks binary and the base branch's reviewed `.gitleaks.toml` rules. PR commits
  cannot supply scanner ignore files or inline allowances.
- `concurrency: ci-${{ github.ref }}` with `cancel-in-progress: true` on PRs (not on pushes to
  `develop`, which write the caches).
- `permissions: contents: read`; `persist-credentials: false` on checkout, as `frontend.yml` does.
- `timeout-minutes` on every job (20 for tests, 15 for quality), so a hung BEAM can't hold a
  runner for 6 h.

Phase 4 adds these jobs to the same graph (details in [Phase 4](#phase-4-apogee-console-and-full-browser-e2e)):

```
console-build ──── needs ── e2e [1..N]   Phoenix + simulator + QuestDB + Postgres, playwright --shard i/N
                                └─────── e2e-report (if: always(); merges blob reports; not required)
```

## Shared job setup (composite action)

`.github/actions/setup-cadence/action.yml`, used by every Elixir job, so versions and cache keys
live in one place:

1. `erlef/setup-beam` with OTP **29.0.5** and Elixir **1.20.4**. `frontend.yml` pins 1.20.3 and
   `mise.toml` says `latest` (developers resolve 1.20.4-otp-29 today). See open question 3.
2. `actions/setup-node` **24.16.0** + `corepack enable` (pnpm 11.22.0). **Every Elixir test
   job needs Node:** about 80 core and web test files shell out to `node` producer/consumer
   probes under `frontend/modules/**`. The probes import `vue`, `happy-dom` and `vite-plus`, so
   the jobs also need `pnpm install --frozen-lockfile` in `frontend/`. The federation fixture
   asserts `node --version == v24.16.0` exactly.
3. `sudo apt-get install libxml2-utils` (xmllint for the XTCE schema validator), only in
   `test-packages`.
4. Cache restore (below), then `mix deps.get --check-locked` for root and each child project
   (`mix setup`). Each child project has its own `deps/` and `_build/`.

All third-party actions are pinned by commit SHA with a version comment, as `frontend.yml` does:
checkout, setup-node and setup-beam reuse its SHAs; actions/cache (restore/save),
upload-artifact, download-artifact and dorny/paths-filter get SHAs resolved when the workflow is
written.

## Partitioning

| Job | What | How | Why |
| --- | --- | --- | --- |
| `test-core` ×2 | `apps/cadence`, about 2,820 tests in 499 files | `cd apps/cadence && MIX_TEST_PARTITION=$i mix test --partitions 2` | The long pole. Its `test` alias runs `ecto.create` + `ecto.migrate`, and partitioned DB names (`cadence_test$i`) already exist. |
| `test-web` ×2 | `apps/cadence_web`, about 970 tests in 178 files | same, `--partitions 2`, after explicit `mix ecto.create -r Cadence.Repo && mix ecto.migrate -r Cadence.Repo` | cadence_web has no DB-setup test alias; the root `mix test` relied on cadence running first. |
| `test-packages` ×1 | ccsds (295), xtce (11), cadence_catalog (30), cadence_simulator (144), `mix test.planes` (4 planes), `mix test.cluster` | sequential in one job | Small suites; four more runners would cost more setup than they save. |

- Each job has its own Postgres service, so `MIX_TEST_PARTITION` only names the DB, the
  ingress-journal dir and the simulator snapshot file. What actually splits the work is
  `--partitions N`.
- ExUnit splits **files** round-robin, not by duration, and `async: false` files run serially
  within each shard. The first green run prints `--slowest-modules 10` per shard, and I tune N
  from that (one matrix number per app).
- Browser-tagged tests stay excluded (`test_helper.exs` already excludes `:browser` and
  `:browser_smoke`); the federation browser job in `frontend.yml` owns them.
- Postgres 17 service with its data dir on tmpfs (`--tmpfs /var/lib/postgresql/data`), plus
  `fsync=off` and `synchronous_commit=off` via `ALTER SYSTEM` + reload in a step (service
  containers can't take `command:` args).

## QuestDB: not needed for phases 1–3

- `config/test.exs` for cadence routes every telemetry store to Postgres:
  `PostgresReadModel` writer, `HistoryStore.Postgres`, `CurrentValueStore.Postgres`, Postgres
  ingress and protocol archives, and `data_sources: [persisted?: false, bootstrap_defaults?: false]`.
- The QuestDB-flavoured tests (the BYO smoke test, managed provisioning, source credentials,
  etc.) inject `exec_fun`/`write_fun` stubs and point at fake hosts like
  `http://customer-questdb:9000`. No test opens a socket to a real QuestDB, and none skips on
  its absence.
- **The e2e stack (phase 4) does need a real QuestDB** for "real history" specs (`investigate`,
  `telemetry`): a `questdb/questdb:9.4.3` service container plus `mix cadence.questdb.migrate`.

## `ApplicationReleaseRegistryTest` and the publication output

What the test needs (from `apps/cadence_web/browser_test/support/federation_release_fixture.exs`):

- The real federation publication output under
  `apps/cadence_web/priv/static/assets/application-host/{comms,telemetry-decom,mission-catalog,ops-console,organization-admin,spacecraft}`
  (gitignored). It **asserts** `File.dir?` and fails when a directory is missing, so it never
  skips silently, but it fails without the build.
- Node 24.16.0 + corepack, because the fixture itself runs `pnpm --filter <plugin> build:release`
  and `check:release` for all six plugins, then the release packager.

Plan: a **`publication` job** runs `corepack pnpm run build:publication` in `frontend/` (the
same step `assets.deploy` uses) and uploads `priv/static/assets/application-host/` as an
artifact. Both `test-web` shards `needs: publication` and download it before `mix test`.
Because the file sits on whichever shard its round-robin slot picks, both shards download it.
If the download is missing, `download-artifact` fails the job, and the test's own `File.dir?`
assertion is a second guard. This needs no application-code change.

Cost: it puts the publication build (est. 2–3 min) in front of the web shards. Web is not the
critical path (core is), so this should fit. If it turns out to be, fallback B is to tag the
module `@moduletag :frontend_publication`, exclude the tag in `test-web`, and run it with
`--only frontend_publication` in `publication`. That's a one-line test change, made as its own
commit.

**Risk:** the same fixture is what fails in `frontend.yml` right now (`integrity_failure` on
activation). If it is a real bug and not a CI-environment issue, `ApplicationReleaseRegistryTest`
goes red in `test-web` too. I'll find out on the first run (open question 6).

## Credo gate

**Update 2026-11-12:** 08d5c2ac (#47) fixed the 46 out-of-scope findings and widened
`.credo.exs` to `plane_test/`, `browser_test/` and `dev/`. Repo-wide strict credo is at 0, so
**no baseline is needed**. The gate is steps 1 and 2 below: `mix credo --strict` plus
`scripts/ci/credo_suppressions.sh` (19 suppressions today). Step 3 is moot.

**Measured 2026-11-11 on develop f9d89f83:** `mix credo --strict` reports **0 issues** within
`.credo.exs`'s scope (`apps/*/{lib,test}`, `packages/*/{lib,test}`, `mix.exs` files,
`dev/otp_cluster/`). The violations still to burn down are elsewhere:

| Where | Count | Notes |
| --- | ---: | --- |
| Outside `.credo.exs` `included` (`apps/cadence/plane_test`, `apps/cadence_web/browser_test`, `dev/**`) | **46** (30 D, 9 R, 4 W, 3 F) | plane_test 3, browser_test 16, dev 27 |
| Inline `credo:disable-*` suppressions inside scope | **19** | 12 `Refactor.Nesting` (whole file), 4 `StructFieldAmount`, 2 `Apply`, 1 `CyclomaticComplexity` |

So the gate is:

1. **In scope: zero tolerance, no baseline.** `mix credo --strict` blocks. A baseline would only
   let regressions in.
2. **Suppression ratchet.** `scripts/ci/credo_suppressions.sh` counts `credo:disable` comments
   per check and fails if any count goes **up** relative to the merge base
   (`git show origin/$GITHUB_BASE_REF:...`). Without this, a suppression comment is the easy way
   around a zero gate. Lowering a count needs no file edit.
3. **Widen the scope with a baseline (recommended, step 2 of the gate).** Add `plane_test`,
   `browser_test` and `dev/` to `.credo.exs`, plus `.credo_baseline.json` holding the 46
   current findings fingerprinted as `{check, file, trigger}` with counts (no line numbers, so
   edits above a finding don't break it). `scripts/ci/credo_gate.exs` runs
   `mix credo --strict --format json`, fails on any fingerprint whose count exceeds the
   baseline, prints those issues with lines, and emits a notice when the baseline can shrink.
   CI also fails if a PR **adds** entries to the baseline file (diffed against the merge base),
   so the baseline can only ratchet down. This needs a `.credo.exs` change, which is
   application-adjacent, so I'll ask before doing it (open question 2).

## Caching

| Cache | Path | Key | Saved by |
| --- | --- | --- | --- |
| Mix deps | `deps`, `apps/*/deps`, `packages/*/deps` | `deps-v1-{os}-otp29.0.5-ex1.20.4-{hash(**/mix.lock)}` | first job to miss |
| Build, test env | `_build/test`, `apps/*/_build/test`, `packages/*/_build/test` | `build-test-v1-{…versions}-{hash(locks)}-{sha}`, restore-keys falling back to the lock prefix, then to the versions prefix | **only `push` to develop/main** (`actions/cache/save`), from `quality` |
| Build, dev env (phase 4) | the same `_build/dev` paths | the same scheme | push to develop, from one e2e shard |
| pnpm store | `$(pnpm store path)` | `pnpm-v1-{hash(frontend/pnpm-lock.yaml)}` | push to develop |
| npm (phase 4, LiveView Vite) | `~/.npm` | `npm-v1-{hash(apps/cadence_web/package-lock.json)}` | push to develop |
| Playwright Chromium | `~/.cache/ms-playwright` | `playwright-chromium-v1-{os}-{playwright version}` | push to develop/main (`.github/actions/playwright-chromium`) |

- PR runs **restore** the latest develop build and compile only what the PR changed. They never
  save, so PRs don't churn the 10 GB repo cache quota.
- Mix staleness after checkout: `actions/checkout` sets every file's mtime to "now". Mix
  compares source digests for files whose mtime moved, so a restored `_build` should only
  recompile changed files. **To verify on the first warm run**: if everything recompiles,
  add `git restore-mtime` (chetan/git-restore-mtime-action) before compiling.
- **No dialyzer.** It isn't in any `mix.exs`. A cold PLT for this dep tree (Phoenix, Ecto,
  OpenTelemetry, grpcbox …) costs several minutes, and adding it is a project decision, not a
  CI one. If wanted later, the PLT cache key is `{versions}-{hash(locks)}` in `priv/plts`.

## Expected timings (required checks, phases 1–3)

The Elixir rows are **estimates** from the reference runs above and the test-suite audit (1,829
core tests in 34–44 s and 1,727 web tests in 52 s on an idle 8-core box). I'll replace them with
measured numbers after the first two runs (one cold, one warm).

| Job | Warm cache | Cold cache (lock change) |
| --- | --- | --- |
| setup (runner, Postgres service, checkout, toolchains, cache restore, pnpm install) | 1:00–1:30 | 2:00–3:00 |
| `quality` | 4–5 min | 9–11 min |
| `test-core` (each of 4) | 3–5 min | 8–10 min |
| `test-web` (each of 2, after `publication` at 2–3 min) | 6–8 min from PR start | 10–13 min |
| `test-packages` | 3–4 min | 7–9 min |
| **PR wall clock (slowest path)** | **~8 min** | **~13 min** |

A cache-warming push to develop after every merge keeps PRs on the warm column. A `mix.lock`
change is the cold case, and it still lands under 15 min.

Concurrency: phases 1–3 fan out to 10 jobs per PR, plus `frontend.yml`'s 2. Two simultaneous PRs
(about 24 jobs) exceed the 20-job account limit and queue. Path filtering and cancel-in-progress
keep that rare. Phase 4 adds 3–4 jobs per PR.

## Phase 3 follow-ups (still Elixir-first)

- Fold `frontend.yml` into `ci.yml` behind `ci-ok`, reuse the `publication` artifact in the
  federation browser job, and put both on the shared caches (the 7-min `test:producers` step is
  mostly a cold test-env compile).
- `test:producers` re-runs producer test files that the core/web shards also run, with
  `CADENCE_REQUIRE_PRODUCER_FIXTURES=1` and a consumer ledger. If the shards can set that env
  and upload their ledgers for a coverage check in `ci-ok`, the separate step goes away. To be
  verified with the frontend owner.

## Phase 4: Apogee console and full browser e2e

Starts when `ui/apogee-spa` is on develop. Inputs: qa's handoff
(`docs/apogee/qa/e2e.md` on `ui/apogee-spa`, b2771377) and `docs/dev-environment.md`.

**Console typecheck, lint and unit tests** come for free. `frontend/apps/console` is a pnpm
workspace member, so `corepack pnpm verify` (`check` + `-r test`) in the frontend quality job
already covers it once merged. I'll confirm that `typecheck-workspace.mjs` and `-r test` pick it up.

**Full e2e suite (user's condition: in CI, and fast).** The suite is 18 specs plus `auth.setup`:
90 tests, **~392 s serial** (203.5 s wall at 2 workers on the loaded laptop). Per qa:

- **Never set `E2E_MUTATE` in CI.** Without it, the permanent-write paths in `changes` (apply),
  `catalog-import` (upload), `planning-policy` and `planning-submit-race` skip. "Full suite" here
  means every spec file runs, with those writes gated off (open question 5).
- `changes`, `setup-stations` and `setup-add-spacecraft` stage change sets and must not run
  concurrently against one server.

### Stack per shard job (each shard gets its own isolated stack)

Services: `postgres:17` (tmpfs) and `questdb/questdb:9.4.3`. Then, in order, with
`MIX_ENV=dev CADENCE_DEV_DATABASE=cadence_ci`, the QuestDB host/port variables,
`OTEL_EXPORTER_OTLP_ENDPOINT=` and `PORT=4011`:

1. Restore the `_build/dev`, deps, pnpm and npm caches; `npm ci` in `apps/cadence_web` (the
   LiveView sign-in page's Vite); download the console artifact; `mix compile`.
2. `ecto.create` + `ecto.migrate -r Cadence.Repo` and `cadence.questdb.migrate`, while the
   simulator starts in the background (`--sname ci_sim`, clean snapshot dir).
3. Phoenix in the background (`elixir --sname cadence_ci -S mix phx.server`), with a readiness
   poll on `/sign-in`.
4. Seeds: `reflect_orbital_demo.exs` (500 spacecraft), `apogee_qa_personas.exs`,
   `reflect_orbital_planning.exs`, then `reflect_orbital_activate.exs --single-operator` over
   distribution to `cadence_ci`. Seeding per shard keeps "today"-relative planning data fresh.
5. `playwright test` (below). `CI=1`, `BASE_URL=http://127.0.0.1:4011`.
6. Always upload the blob report, `test-results/` (traces and screenshots on failure) and the
   Phoenix and simulator logs.

**Console serving (qa's open question to lead):** I recommend serving a **production console
build**. A `console-build` job runs `vp build` once and uploads `priv/static/console`, and shards
run Phoenix with `CONSOLE_VITE_ORIGIN=""`, which `dev.exs` on `ui/apogee-spa` already supports.
That's one less process per shard, no HMR, faster page loads, and it tests what we ship.

### Sharding

- Playwright projects (qa owns the config change): `setup` → `desktop` (all read-only specs,
  `fullyParallel`) and `changesets` (the three change-set specs).
- Shard *i* runs `playwright test --project desktop --shard i/N --workers 3 --reporter blob`.
  **Shard 1** then also runs `--project changesets --workers 1`, which serialises them against
  that shard's own server (~45 s). Each shard re-runs `setup` (5 sign-ins), as qa notes.
- `e2e-report` merges blob reports into one HTML report (`if: always()`, off the critical path).
- **Start with N = 2.** Rule for raising N: when the slowest shard's test step goes over
  **3 min**, set `N = ceil(serial_seconds_on_CI / (3 workers × 150 s))`. Today's ~392 s laptop
  serial cost (less on an idle runner) fits in N = 1–2. The suite only needs sharding as it grows.

### Time budget (e2e shard job; estimates until measured)

| Step | Budget |
| --- | --- |
| runner + Postgres/QuestDB services | 0:20 |
| checkout, toolchains, cache restore, `npm ci`, artifact | 1:00 |
| warm `mix compile` (dev) | 0:30–1:30 |
| migrations + simulator + Phoenix boot | 0:45 |
| seeds + activation | **1:00–2:00 (unmeasured; the biggest unknown)** |
| `setup` sign-ins | 0:15 |
| tests: shard 1 = half the read-only tests + change-set specs | 1:30–2:30 |
| reports upload | 0:15 |
| **Job total** | **~6–8 min; hard budget 10 min, `timeout-minutes: 15`** |

The fixed cost is the stack, not the tests, so speed comes from bring-up, not more shards: warm
`_build/dev`, background boots in parallel with migrations, and a cached seeded-DB snapshot
(`pg_dump -Fc` keyed by the hash of `dev/reflect_orbital*`, `dev/apogee_qa_personas.exs` and
`priv/repo/migrations`) **if** seeding measures over 90 s. qa's ~1-min "fast real-server
subset" (`shell planning-requirements palette setup-readiness`) isn't needed as a CI gate,
because the full suite fits the budget. It stays useful as an on-demand `workflow_dispatch`
input.

### Making it required

Run e2e as non-required for the first week and track flake rate (any retry-to-green or
red-on-develop). Then add it to `ci-ok`. Playwright `retries` stays 0 for `desktop` (a flake
should be visible) and 1 for `setup`, as configured today.

## Delivery order

1. `ci.yml` with `changes`, `quality` (credo gate steps 1+2), `test-packages`, `test-core`,
   `ci-ok`, composite setup and caches. First run cold, second warm, then report timings.
   **Written 2026-11-12** (0d8aa9e6, after the mise.toml pin df9b3c11 and the
   `Cadence.Commanding` format fix be530feb); awaiting its first run.
2. `publication` + `test-web`, plus diagnosing the federation `integrity_failure`.
3. Fold `frontend.yml` in, plus the producer-contract and federation-browser cache work.
4. After `ui/apogee-spa` merges: `console-build`, `e2e` shards, `e2e-report`. Measure, tune N,
   then make it required.

Each step is a small `ci:` commit. The director pushes after the user agrees, and I report the
measured timings for every run.

## Open questions

1. **Branch protection** (director/user): once `ci-ok` is green twice, make it the required
   check on `develop` and `main`? Nothing is protected today, which is how the red frontend runs
   on #37/#38 merged.
2. **Credo scope widening:** OK to add `plane_test/`, `browser_test/` and `dev/` to `.credo.exs`
   with a 46-entry, ratchet-down-only baseline? Without it, the gate is "zero in current scope +
   no new suppressions" and those 46 stay invisible.
3. **Toolchain pin:** CI pins OTP 29.0.5 / Elixir 1.20.4; `frontend.yml` pins 1.20.3, and
   `mise.toml` says `latest` for both. Pin them in `mise.toml` so dev and CI can't drift? That
   changes every developer's toolchain, so it's the user's call.
4. **Console in CI** (lead, via qa's question): production console build served by Phoenix
   (`CONSOLE_VITE_ORIGIN=""`), as recommended above?
5. **"Full suite" with mutations gated off** (user/qa): qa says never set `E2E_MUTATE` in CI.
   Each shard's DB is throwaway, so a later option is a dedicated serial job that **does** run
   `E2E_MUTATE=1` (apply, import, policy versions, submit race) on its own stack. Do we want that
   now, or is "all specs, writes gated" what the user means by full?
6. **Federation fixture failure** in `frontend.yml` (`integrity_failure` on catalog activation,
   since at least 2026-11-08): who owns it? It blocks `ApplicationReleaseRegistryTest` in
   `test-web` if it isn't CI-specific. I can diagnose it as part of step 2 if you want.
7. **Security advisories:** `mix deps.get` reports Hex advisories (e.g. Bandit HTTP/2
   StreamError recovery). Add `mix hex.audit` / `mix_audit` to `quality` as a non-blocking step?

## Housekeeping

- This worktree's `ci/github-actions` branch was the user's **August** CI attempt (5 commits on
  66a0b1e1, 1,052 commits behind develop), not a branch off `origin/develop`. Those commits live
  on `origin/ci/github-actions`, and **PR #13 (`ci/github-actions` → `main`, open)** points at
  them. I reset the local branch to `origin/develop`; nothing local was lost. **Resolved:** the
  local branch is renamed `ci/actions-develop` with no upstream, so `origin/ci/github-actions`
  and PR #13 stay untouched. New work goes to a new PR against `develop`.
- The August `ci.yml` is superseded by this plan. Its xmllint lesson is carried forward. Its
  both-env `mix setup` is no longer needed, because `precommit.checks` now runs the architecture
  check under `MIX_ENV=test`. I'll confirm that on the first run.

# Earendil scale runs

## Hosted scorecards

#217 baselines use the **Earendil scale scorecards** workflow on the GitHub-hosted
`ubuntu-24.04` x64 runner with 4 vCPUs and 16 GB RAM. Dispatch when the PR queue
is short. Each fleet size gets a fresh runner and stack, and the workflow
measures one size at a time. Postgres runs as a service, and `dev/stack` starts
QuestDB 9.4.3 and seeds Earendil before the measurement. [GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories)

Start with 50 craft to verify startup and measurement timing.

```sh
gh workflow run scale-scorecard.yml --ref develop -f ref=develop -f spacecraft=50 -f shape=peak -f duration=600
```

After checking that run, dispatch with `spacecraft=500,1000`. The input defaults
are `ref=develop`, `spacecraft=50,500,1000`, `shape=peak`, and `duration=600`.
Use a ref containing the scale runner and dev stack. The hosted runs use 15 sites
and a synchronous ingress journal. Fleet sizes can range from 1 to 1,023. Use a
whole number of seconds up to 18,000 to leave room for setup and teardown within
the hosted job limit. [GitHub Actions limits](https://docs.github.com/en/actions/reference/limits)

Each job summary contains the scorecard. The artifact includes the Markdown
under `docs/scale/` and its JSONL series and JSON summary under `var/scale/`.
The page records the runner type and tested commit. A baseline requires the
1-minute load to stay at or below the logical core count and swap use to stay
under 50% in every sample. The Linux sampler reads `/proc/loadavg` and
`/proc/meminfo` and uses `nproc` for the core count. A threshold breach or a
missing host reading classifies the run as a ceiling check.

## Local runs

Local runs are development checks. Run from the repository root of a development
worktree with PostgreSQL, Docker for QuestDB, and the tools required by
`dev/stack up`.

```sh
mix cadence.scale.run --spacecraft 50 --shape peak --duration 60
mix cadence.scale.run --spacecraft 500 --shape average --per-site 16 --duration 600 --reset
mix cadence.scale.run --spacecraft 1000 --shape peak --duration 600 --reset
```

The command sets `EARENDIL_SPACECRAFT_COUNT`, brings up the worktree stack,
activates Earendil and opens one TCP ingress path per selected craft. Peak selects
every craft. Average selects up to eight per site by default, or up to sixteen
with `--per-site 16`. Set `EARENDIL_SITE_COUNT` before starting or resetting the
stack to change the site count. The simulator offers about ten packets per
second per selected craft.

Use a fresh worktree stack for a different fleet size, or pass `--reset` to
discard and reseed this worktree's stack data. Activation uses the Earendil
single-operator development policy. The command ends its contacts when the
measurement finishes and leaves the stack running.

The sampler starts after every selected simulator path has sent frames. It writes
the sampler JSONL and summary JSON under `var/scale/`. The command writes a
Markdown scorecard to `docs/scale/<UTC date>-<label>.md`. The label defaults to
`<shape>-<spacecraft>`. Use `--label` for another run of the same shape and
size on the same UTC day.

Each JSONL row records its measured `elapsed_ms`. The summary's `counters`
include the run total and the p50, p99 and max per-second rates for each counter.
The sampler divides each row's count by its measured interval before aggregating
rates. Gauges and latency distributions keep their original units.

Without `--spacecraft`, `mix cadence.scale.run --duration S` samples an
already running Cadence node. `mix cadence_simulator.load` runs the
simulator-only TCP sink benchmark.

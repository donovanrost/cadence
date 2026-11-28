# Earendil scale runs

Run from the repository root of a development worktree with PostgreSQL, Docker
for QuestDB, and the tools required by `dev/stack up`.

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

The report opens with the run classification, peak 1-minute host load and
peak swap percentage. A baseline requires the load to stay at or below the
logical core count and swap use to stay under 50% in every sample. Runs with
missing host readings or a threshold breach are ceiling checks.

Launch baseline runs from an unsandboxed session: a Codex sandbox denies macOS
`sysctl`, leaving host load and swap unavailable and making the run a ceiling check.

Without `--spacecraft`, `mix cadence.scale.run --duration S` samples an
already running Cadence node. `mix cadence_simulator.load` runs the
simulator-only TCP sink benchmark.

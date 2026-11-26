# Measure simulator contact load

Run from the repository root after `mix setup`.

```sh
mix cadence_simulator.load --craft 1000 --shape peak --duration 600
```

The command schedules provider contacts and runs the ordinary simulator
coordinators, CCSDS TM framing, and TCP send buffers. Ten loopback listeners
accept one connection per active contact. The sink identifies the path from the
first frame's spacecraft ID and counts complete frames and received bytes
across TCP reads. The command uses a private, temporary DETS store and runs
without Cadence, PostgreSQL, QuestDB, or Docker.

- `--craft` sets the fleet size. Use 50, 500, or 1,000 for the ingest baseline.
- `--shape peak` activates every craft. `--shape average --per-site 8` or
  `--per-site 16` activates up to that many craft at each of the ten sites.
  The remaining contacts have future acquisition times.
- `--duration` sets the measurement window in seconds. It starts after each
  selected path has delivered its first frame.
- `--output` sets the JSON Lines destination. The default is
  `var/simulator-load.jsonl` at the repository root.

The demo catalog produces ten CCSDS space packets per generation step. Its
science packet spans four TM frames, so the target is 13 frames and roughly
14.5 kB/s per craft. The command prints each interval and writes its exact
duration, active stream count, frame and byte totals, scheduler utilization,
BEAM memory, and per-path frame and byte deltas to JSONL. Each path is keyed by
TM SCID. A path can deliver zero frames within a single interval because a generation
step emits the packet families together. The command fails if a selected path
does not advance across successive two-second windows, an active stream is
lost, or a path averages below 98% of the target over the run. Short runs
allow one generation step at the measurement boundary.

Scheduler wall time covers normal BEAM schedulers in the simulator VM,
including its loopback sinks and sampler. It is reported as an aggregate
utilization ratio and as the busiest scheduler in each interval. Memory is
the total reported by the BEAM in bytes, including the loopback receivers.
The app can report a TCP resource error when the process open-file limit is
below its socket requirement. At 1,000 paths, the simulator and sink use about 2,000
connected sockets plus ten listeners.

The simulator load measurement is the producer baseline for the Cadence
ingest run tracked in [#717](https://github.com/donovanrost/cadence/issues/717)
and the scorecard in [#686](https://github.com/donovanrost/cadence/issues/686).

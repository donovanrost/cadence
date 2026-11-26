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

## Laptop measurements

Measured on 2026-11-26 on an arm64 Mac with Elixir 1.20.4, OTP 29, and eight
normal BEAM schedulers. All paths were active throughout each peak run.

| Peak paths | Window | Received frames/s | Target frames/s | Mean scheduler use | Busiest scheduler, max 1s |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 60 s | 650.0 | 650 | 0.16% | 1.25% |
| 500 | 60 s | 6,472.4 | 6,500 | 1.76% | 7.33% |
| 1,000 | 600 s | 12,970.9 | 13,000 | 4.13% | 11.90% |

The 1,000-path memory capture delivered 7,782,541 frames and 8,677,533,215
bytes. Every path delivered frames in each two-second window, and the slowest
path averaged 12.96 frames/s. Sampled BEAM memory was 223.3–466.4 MiB.
The median was 394.1 MiB, the 95th percentile was 451.5 MiB, and the last
sample was 414.7 MiB. The first and last two-minute medians were 302.5 and
424.7 MiB.

An independent 600-second run completed at 12,969.5 frames/s. The memory
capture finished sampling and reached the former five-second store flush
timeout during contact shutdown. The command now gives the final batch up
to 60 seconds to persist.

The 1,000-craft average fixture with 16 per site activated 160 paths and
delivered 2,079.9 frames/s over 15 seconds.

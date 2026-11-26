# Measure simulator contact load

Run from the repository root after `mix setup`.

```sh
mix cadence_simulator.load --craft 1000 --shape peak --duration 600
```

The command schedules provider contacts and runs the ordinary simulator
coordinators, CCSDS TM framing, and TCP send buffers. Ten loopback listeners
accept one connection per active contact. The sink identifies the path from the
first frame's spacecraft ID and counts complete frames and received bytes
across TCP reads. The command uses a private, temporary provider snapshot and runs
without Cadence, PostgreSQL, QuestDB, or Docker.

- `--craft` sets the fleet size. Use 50, 500, or 1,000 for the ingest baseline.
- `--shape peak` activates every craft. `--shape average --per-site 8` or
  `--per-site 16` activates up to that many craft at each of the ten sites.
  The remaining contacts have future acquisition times.
- `--duration` sets the measurement window in seconds. It starts after each
  selected path has delivered its first frame.
- `--binary-owners` adds the ten processes with the most referenced binary
  bytes and totals by process role to each ten-second diagnostic row.
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

Every tenth JSONL row includes the provider table's entry count and memory,
whether a snapshot is pending, the event count, the snapshot file size, and
the BEAM memory breakdown. It also includes completed snapshot write and
rename timings since the previous diagnostic sample. The terminal log
records initialization, contact shutdown, the final flush, and the store's
termination time.
Per-process binary counts use `Process.info(pid, :binary)`. A binary held
by two processes can appear in both totals. The independent BEAM binary
memory counter is `diagnostics.memory.binary`.

The simulator load measurement is the producer baseline for the Cadence
ingest run tracked in [#717](https://github.com/donovanrost/cadence/issues/717)
and the scorecard in [#686](https://github.com/donovanrost/cadence/issues/686).

## Laptop measurements with DETS

Measured on 2026-11-26 on an arm64 Mac with Elixir 1.20.4, OTP 29, and eight
normal schedulers. The 1,000-path soak used the 256-key batches and the
five-second flush deadline.

| Peak paths active throughout | Window | Received frames/s | Target frames/s | Mean scheduler use | Busiest scheduler, max 1s |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 60 s | 650.0 | 650 | 0.16% | 1.25% |
| 500 | 60 s | 6,472.4 | 6,500 | 1.76% | 7.33% |
| 1,000 | 600 s | 12,973.0 | 13,000 | 3.68% | 13.36% |

The 1,000-path run delivered 7,783,789 frames and 8,678,924,735
bytes. Every path delivered in each two-second window. The slowest path
averaged 12.96 frames/s. Sampled BEAM memory ranged between 213.1 and 509.0 MiB,
with a 367.8 MiB median, a 450.0 MiB p95, and 393.2 MiB in the final sample.

Across all 60 diagnostic samples, the store held 11,025 mirror entries,
16,185,248 mirror bytes, zero dirty keys, 10,011 events, and 9,113,628
DETS bytes.
There were zero persistence batches during delivery. Closing the contacts
took 186.2 ms and the final flush took 214.1 ms.
After shutdown the store had 14,012 events, 11,568,875 DETS bytes, and
zero dirty keys.

| BEAM memory category | First 2 min median MiB | Last 2 min median MiB | Change MiB |
| --- | ---: | ---: | ---: |
| Total | 323.3 | 416.1 | +92.8 |
| Processes | 112.1 | 120.1 | +8.0 |
| Binaries | 120.4 | 216.9 | +96.5 |
| ETS | 19.8 | 19.8 | 0.0 |

Binary memory accounted for most of the increase. The provider mirror and
DETS file stayed the same size throughout the measurement window.

The average fixtures delivered 1,039.9 frames/s with 80 active paths at eight
craft per site and 2,079.9 frames/s with 160 paths at 16 per site.

## 30-minute binary-memory soak

The follow-up used the same 1,000-path peak fixture with per-process sampling
enabled.

```sh
mix cadence_simulator.load --craft 1000 --shape peak --duration 1800 --binary-owners
```

On 2026-11-26, all 1,000 paths stayed active across the 1,800-second
measurement. They delivered 23,363,483 frames at 12,979.7 frames/s, with 3.49%
mean scheduler use. Each path delivered frames in every two-second window.

| Minutes | BEAM binary median MiB | BEAM binary p95 MiB | Coordinator refs median MiB | Send-buffer refs median MiB | TCP receiver refs median MiB |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0–5 | 125.0 | 157.3 | 50.6 | 26.9 | 39.8 |
| 5–10 | 181.0 | 213.4 | 51.4 | 28.1 | 103.2 |
| 10–15 | 231.0 | 263.0 | 53.3 | 26.2 | 149.2 |
| 15–20 | 245.8 | 278.8 | 53.9 | 25.1 | 168.1 |
| 20–25 | 252.7 | 284.5 | 55.5 | 26.2 | 174.4 |
| 25–30 | 258.6 | 283.1 | 54.6 | 29.5 | 177.0 |

TCP receiver references accounted for most of the initial rise and leveled off
in the final ten minutes. The provider store held at 11,025 mirror entries,
10,011 events, zero dirty keys, and a 9,114,453-byte DETS file throughout the
measurement. The first capture delivered all 1,800 samples and then hit a
five-second DETS timeout at its explicit shutdown flush.

## Shutdown persistence comparison

The 30-minute DETS run reached the five-second explicit flush deadline after
contact shutdown. Its slowest 256-key insert took 679.2 ms, while the slowest
sync took 11.2 ms. The store still had the same number of entries throughout
delivery.

Three short 1,000-path repeats timed both DETS termination and a verified
ETS snapshot of the same 15,026 entries. The snapshot probe wrote a temporary
file, synced it, and renamed it into place.

| Repeat | DETS flush ms | DETS terminate pending work ms | DETS close ms | ETS snapshot write and rename ms |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 269.6 | 0.010 | 0.097 | 69.8 |
| 2 | 224.0 | 0.007 | 0.186 | 72.7 |
| 3 | 255.5 | 0.005 | 0.147 | 70.6 |

The provider now publishes verified ETS snapshots once per second when there
are changes, and on clean shutdown. Successful HTTP mutations wait for a
snapshot to publish their writes. A restart opens the last atomically
published snapshot, so an abrupt exit can lose unpublished changes.

A snapshot-backed 1,000-path run completed 600 seconds at 12,973.5 frames/s.
All diagnostic rows showed the same 6,147,770-byte published snapshot during
delivery. Contact shutdown took 215.8 ms and the explicit flush took 245.0 ms,
including time behind a periodic snapshot that overlapped contact shutdown.
The subsequent store termination took 0.010 ms.

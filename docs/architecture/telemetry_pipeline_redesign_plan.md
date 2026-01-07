# Telemetry Pipeline Redesign Plan (Lanes + Shards + Durable Log)

## Goals & Constraints
- Smooth lumpy, high-rate telemetry by fanning out hot keys and batching without breaking per-key ordering guarantees.
- Auto-scale on backlog depth/drain rate while keeping shard assignment stable enough for stateful work.
- Preserve hot-reload (control-plane pushes config; no ETS-only config coupling) and multi-tenant isolation.
- Keep Cosmos-inspired phases (identify → decom → convert → derive) as pure functions, but reduce process hops in the hot path.
- Make the durable sink pluggable (OTP append log now; Kafka/Redpanda later) with a shared record envelope.

## Current Implementation Snapshot (what we have today)
- Mission runtime tree (per `MissionInstance`) spins up CVT (ETS), PacketIdentifier (ETS lookup), converters, limits, alarms, interfaces, and pipeline.
- Pipeline v1: Broadway chain via PubSub. Pipeline v2: GenStage `PartitionRouter` partitions by `{target_id, apid}` → per-partition stage chain (`IdentifyStage`, `DecommutationStage`, `ConversionStage`, `DeriveStage`, `CVTBatcher`), per-partition batching, metrics in `PipelineMetrics`.
- PubSub ingress topic `mission:<id>:telemetry:raw`; CVT updates fan back to PubSub for UI.
- Config/hot-reload: control plane pushes `MissionConfig`; children handle `{:apply_config, config}`. PacketIdentifier/limits/derived caches use ETS per mission; VersionRegistry + PubSub invalidation for reloads.
- Durable storage: none on the ingest path (CVT is in-memory ETS), replay/backfill not first-class.

## Keep / Modify / Delete
- Keep (as-is or lightly wrapped)
  - Phase modules: identification (`PacketIdentifier` + `BinaryExtractor`), conversion modules, derived item functions, limits state tracking.
  - Mission-level isolation and config push model (`MissionConfig` messages), control-plane → dataplane boundary.
  - CVT as a live cache for latest values (but fed by a consumer, not the only sink).
- Modify
  - Partitioning: move from single `{target, apid}` partition set to lane → shard buckets (sub-partitioning + virtual shards) with stable shard IDs and router versions.
  - Stage execution: fuse per-packet GenStage hops into per-shard batch workers (identify+decom+convert+derive in-process) to cut IPC overhead while keeping the same pure functions.
  - Config reload: versioned bundles per lane/shard (no ETS dependency for config), outputs tagged with `config_version`.
  - Backpressure/metrics: per-lane/shard depth, drain rate, e2e latency; autoscaler adjusts worker assignment, not shard keys.
  - Durable sink: add adapter layer (OTP append log now; Kafka/Redpanda later) with record envelope (`target`, `apid`, `seq`, `ts`, `router_version`, `shard_id`, `config_version`).
- Delete/retire
  - Broadway v1 pipeline and the multi-hop GenStage stage-per-phase chain in Pipeline v2 once the new lane/shard workers are in place.
  - PartitionRouter/PartitionSupervisor scaffolding as the router/lane/shard supervisors replace them.
  - Fan-in CVT batcher expectations; CVT becomes a consumer of the log, not the primary sink.

## Target Architecture (flow)
```
Ingress (interfaces/deframe)
  -> Router (lane select by APID profile/rate/ordering; shard = hash(target, apid, seq/ts, vnodes))
    |-- Payload lane (N shards) --+
    |-- Housekeeping lane (M shards) --+   # cold lane similar, critical lane optional
    |-- Cold lane (shared shards) --+
    |-- Critical lane (few shards) --+
             |
             v
      Shard worker (batch loop)
        identify -> decom -> convert -> derive   # pure functions, fused
        | metrics | backpressure (hi/lo watermarks)
        v
      Durable Sink (adapter)
        - OTP append log per shard (segment files)
        - Later: Kafka/Redpanda (same envelope)
        - Records tagged with router_version, shard_id, config_version
             |
             +-> CVT consumer (latest values)
             +-> Postproc/normalize/index
             +-> Replay tools / stateful lane feed

Stateful/Derived lane (sticky key = target + derivation key; controlled fan-out)
  - Consumes selected APIDs from sink or direct tap
  - Holds window/agg state + periodic checkpoints
  - Fixed topology during replays; cautious scaling with handoff
```

## Supervision (per mission)
```
MissionInstance
├─ RouterSupervisor
│   └─ Router (lane/shard hashing, backpressure)
├─ LaneSupervisor (per lane)
│   └─ ShardSupervisor (per shard)
│       └─ ShardWorker (batcher + fused transforms -> LogSink.append)
├─ StatefulLaneSupervisor
│   └─ StatefulShardWorker (sticky keys, checkpoints)
├─ LogSinkSupervisor (adapter: OTP append logs now; pluggable)
├─ LogSourceSupervisor (offset mgmt for consumers/replay)
├─ CVTConsumer (reads sink; updates ETS + PubSub)
├─ PostprocConsumer (normalize/index/analytics)
├─ AutoscaleSupervisor (watches depth/drain/latency; reassigns shard->worker)
└─ Metrics/Health reporter (per shard/lane timing, backlog, drops)
```

## Execution Model (GenStage vs GenServer)
- Router: GenStage producer with demand awareness; uses consistent hashing to pick shard and can honor backpressure by reducing demand when shard mailboxes exceed high watermark.
- Shard workers: GenServer (lowest overhead) that receives events from router, buffers, and runs a batch loop (size/time) executing `identify -> decom -> convert -> derive` in-process. We can wrap as GenStage consumers if we want explicit demand negotiation, but the inner execution stays fused.
- Stateful lane workers: GenServer with sticky keys and checkpoint timer; optional GenStage subscription for demand caps. Holds window/agg state.
- Consumers (CVT, postproc, replay): GenServer readers over `LogSource.subscribe/2` are sufficient; if we want demand-driven fan-out, add GenStage consumers with `max_demand/min_demand`.
- Rationale: keep demand/backpressure at the router boundary; minimize per-packet process hops by fusing downstream work per shard.

## Metrics, Telemetry, and Monitoring
- Extend `Cadence.Telemetry.PipelineMetrics` to include lane/shard dimensions and router_version/config_version tags where helpful.
- Hot-path counters/timings: packets/items received/processed, errors per phase, sampled timings for identify/decom/convert/derive/batch/append/end-to-end, bytes received.
- Shard health: inbox depth, enqueue/drain rate, backlog half-life, drop count, batch size/latency p50/p95, sink append latency, fsync lag (OTP sink), consumer lag (for CVT/postproc).
- Emit `:telemetry` events for router demand changes, autoscaler actions, config adoption, sink health; export via existing PromEx/Grafana stack.
- Dashboards: lane/shard heatmaps for depth/latency, backlog half-life SLO, drop rate, end-to-end latency samples, sink health, config version adoption.
- Alerts: backlog half-life above SLO, sustained drops, sink append/fsync latency high, config version lagging shards.

## Library Extraction from Existing Pipeline
- Extract pure function APIs from Pipeline V2 stage modules:
  - `Cadence.Runtime.Telemetry.PipelineV2.Stages.IdentifyStage` → `Cadence.Telemetry.Identify.run/2`
  - `...DecommutationStage` → `Cadence.Telemetry.Decom.run/2`
  - `...ConversionStage` → `Cadence.Telemetry.Convert.run/2`
  - `...DeriveStage` → `Cadence.Telemetry.Derive.run/2`
- Keep `BinaryExtractor`, conversion/derived item modules, limits utilities; ensure pure data-in/data-out signatures.
- Retire GenStage wrappers for these stages after the fused shard worker path is live.
- Reuse `PipelineMetrics` (with lane/shard extensions) and `CurrentValueTable` batching logic inside the new CVT consumer.

## Stateless Derived Telemetry (within the main lanes)
- The fused shard worker already runs derive after convert; stateless derived items like `y = x*10` and `z = y*2` are supported in the main lanes.
- Implementation details:
  - Include derived definitions in the config bundle; load into worker state per config_version.
  - Evaluate per event after conversion using a topological order over dependencies (mnemonic → derived mnemonic). Detect cycles at load time; fail fast if present.
  - Multi-pass fallback: if topo order is not precomputed, iteratively compute until no new values, with a small max iteration to avoid loops.
  - Keep derived outputs in the per-event map so later derived expressions (e.g., `z` using `y`) see them.
  - Batch execution does not share state across events; stateless means per-packet computation only. Cross-packet/aggregation needs the stateful lane.
- Hot reload: when derived definitions change, the new config bundle is swapped at the batch boundary; subsequent events use the new definitions, and outputs are tagged with the new config_version in the sink.

## User-Defined Processors (Lua via Luerl)
- Two execution modes:
  - **Stateless**: runs inside the main shard worker after convert; must be pure per packet and fast.
  - **Stateful**: runs in the stateful lane with sticky keys and per-key state; suitable for windowed/accumulating logic.
- Packaging:
  - Users upload Lua scripts; control plane bundles them with `config_version`, metadata (name, mode: stateless/stateful, state_key selector, resource limits).
  - Scripts are stored in the config bundle; workers load/compile at config swap; keep per-version cache.
- Sandbox:
  - Luerl with restricted libs (math, string, table); no IO/OS/ffi/env; no randomness unless provided.
  - Resource limits: step budget/time budget per call; memory cap per VM; kill on overuse. Run each script in an isolated process to avoid blocking shard worker; communicate via message passing.
  - Determinism: no access to wall-clock except an injected monotonic timestamp if allowed; no global mutable host state.
- Host API (examples):
  - `get(field)` to read converted values for this packet.
  - `emit(name, value)` to produce derived outputs.
  - `state_get()/state_put()` available only in stateful mode; state is scoped to the state key (e.g., target + derivation key) and checkpointed.
  - `log(level, msg)` for debugging with rate limits.
- Execution flow:
  - Stateless: shard worker passes the packet value map to the Lua VM, collects emitted derived fields, merges into event; errors are logged and counted, packet continues without those derived values.
  - Stateful: stateful lane worker passes packet and current state to Lua; Lua returns new state and emissions; state is stored and checkpointed periodically.
- Safety/operability:
  - Validate scripts on upload (syntax, no forbidden libs, optional static checks for globals).
  - Metrics: per-script invocations, errors, timeouts, avg/p95 runtime, drops.
  - Hot reload: new `config_version` swaps to new script set; stateful scripts can define a migration hook (`migrate(old_state)`); otherwise start fresh or drop state per policy.

## Limits Evaluation (placement and mechanics)
- Placement:
  - **Stateless limits** (thresholds on current values) run in the shard worker immediately after derive (and after stateless Lua, if enabled) to produce limit states per item; results flow with the packet to the sink.
  - **Stateful limits** (persistence, timers, staleness) run in a dedicated consumer (e.g., `LimitsConsumer`) reading from the sink to avoid blocking ingest; it updates limit state and triggers alarms.
  - Staleness monitoring stays as a separate process fed by CVT updates or sink stream.
- Config:
  - Limit definitions are part of the config bundle; include thresholds, persistence rules, deadbands, severity, and optional hysteresis.
  - Tag outputs with `config_version`; on reload, new limits apply at batch boundary; persistence counters reset or migrated based on policy.
- Evaluation flow (stateless in shard worker):
  - For each item, check thresholds/deadbands; emit limit state (green/yellow/red/blue) into the event; keep it with the packet when writing to sink.
  - Metrics: count of items evaluated, transitions per state, errors.
- Evaluation flow (stateful consumer):
  - Consume packets from sink; for each item + limit definition, apply persistence (N of M), timing windows, and staleness detection; update limit state store (per target/item).
  - Emit limit events to AlarmManager; update CVT limit state.
- Metrics/alerts:
  - Limit eval latency (p95), backlog for limits consumer, alarm throughput, staleness violations.
  - Alert if limits consumer lags the sink or drops messages.

## Implementation Phases
1) Envelope & Adapter Contracts
   - Define `Cadence.Telemetry.LogSink` / `LogSource` behaviours (`append/3`, `partitions/0`, `subscribe/2`, `ack/2`, `health/0`) and the record envelope fields (`router_version`, `shard_id`, `config_version`, checksum, ids).
   - Introduce a small shared struct for batched records (packet metadata + stage outputs).
   - Tag events at router with `router_version`; include in metrics.

2) Router + Lanes + Shards
   - Replace `PartitionRouter` with a lane-aware router (policy: payload/housekeeping/cold/critical; auto assignment by APID profile + rate; operator overrides allowed).
   - Implement virtual shards to keep shard IDs stable; route selects shard via consistent hash on `{target, apid, seq|ts}`.
   - Per-lane supervisors start shard supervisors; shard assignment can move workers without changing shard keys.

3) Shard Workers & Fused Transforms
   - Replace per-stage GenStage chain with a batch-processing shard worker: pull batch (size/time), run identify/decom/convert/derive functions in-process, push batch to sink.
   - Reuse existing stage modules as pure functions (extract callable API from `identify_stage`, `decommutation_stage`, etc.).
   - Backpressure: shard-local hi/lo watermarks on mailbox depth; propagate to router to pause/resume per lane.

4) Durable Sink (OTP-first, Kafka-ready)
   - Implement OTP append log adapter: per-shard segment files + manifest + offsets per consumer group; CRC + fsync policy; health reporting.
   - Implement Kafka/Redpanda adapter stub with the same API; support dual-write in staging.
   - Wire CVT consumer to read from LogSource (latest-value cache remains ETS but is downstream of the log).

5) Stateful Lane & Correlations
   - Add dedicated lane with sticky partitioning on state key; integrates derived telemetry that needs windows/joins.
   - Add checkpointing (periodic snapshots to durable store) and replay tooling (consume from offset 0 with autoscale off).
   - For cross-APID joins, co-route required APIDs into this lane via a compacted side-log or filtered tap from the sink.

6) Autoscaling, Metrics, Backpressure
   - Metrics: per shard depth, enqueue/drain rate, p50/p95 batch latency, append latency, drops, end-to-end latency sampled.
   - Autoscaler: scale shard workers per lane based on backlog half-life and drain deficit; reassign shard→worker; enforce cooldowns.
   - Backpressure: high/low watermarks per shard; router pauses ingress to that shard/lane and resumes on recovery.

7) Config / Hot-Reload (no ETS dependency)
   - Control plane publishes `{config_version, uri, checksum}`; workers fetch bundle from durable store into process state (optionally `persistent_term` cache), swap at batch boundaries.
   - Tag batches and sink records with `config_version`; keep prior bundle for in-flight work, then drop.
   - Derived/stateful: versioned derivation modules; migration hooks for shape changes; fixed topology during replays.

8) Cutover & Cleanup
   - Introduce new pipeline behind a feature flag (`pipeline_version: :lanes_v3`), run shadow mode if needed.
   - Retire Broadway v1 and `pipeline_v2` stage chain after validation.
   - Remove fan-in CVT expectations; ensure CVT consumes from sink.
   - Delete unused metrics/stat counters tied to the old chain; migrate dashboards to new metrics.

## What We Keep (with tweaks)
- Packet parsing/decom/conversion/derived logic modules; wrap them as pure functions callable from shard workers.
- Mission runtime isolation and control-plane-driven `MissionConfig` messaging for hot reload; add version tagging + bundle fetch.
- CVT as the live view cache (ETS) but fed from the durable sink consumer, not the ingest hot path.

## What We Change
- Partitioning model: lanes + sub-shards with virtual nodes; router versions recorded in records.
- Pipeline shape: fused per-shard batch workers instead of long GenStage chains.
- Durable persistence: add LogSink/Source adapters; CVT/postproc become consumers.
- Config handling: versioned bundles per worker (no reliance on node-local ETS for config), version tags on outputs.
- Autoscale/backpressure: depth/drain-driven scaling and pause/resume per shard.

## What We Delete
- Broadway v1 pipeline.
- `pipeline_v2` PartitionRouter/PartitionSupervisor + per-phase GenStage chains once lanes/shards are live.
- Any direct PubSub-to-CVT write path in the hot loop; replace with sink consumer.
- Ad-hoc ETS config caches that assume single-node scope; replace with versioned bundles and process-local state.

## Packet Capture & Replay (raw frames + deframed packets)
- Capture points:
  - Raw frame capture at interface/deframer output (before router) for bit-exact replay.
  - Deframed packet capture at router ingress (after target/APID classification) for logical replay.
- Storage options (pluggable via `LogSink`):
  - OTP append log: add separate shard-aligned streams for `raw_frames` and `packets`. Segment rotation, optional compression.
  - Kafka/Redpanda: dedicated topics `telemetry.raw.frames` and `telemetry.deframed.packets`, same envelope fields plus `frame_seq`/`frame_ts`.
- Envelope additions for capture:
  - Raw frame: `{frame_seq, frame_ts, interface_id, target_hint, config_version, router_version, shard_id, checksum, payload}`.
  - Packet: existing packet envelope plus `frame_seq/ref`, `deframe_source` metadata.
- Replay tooling:
  - `LogSource` readers support time/range filters and speed controls (real-time, accelerated, as-fast-as-possible).
  - Deterministic replay: fix router_version and shard mapping; disable autoscale; for raw frames, re-run deframer → router; for packets, inject directly at router ingress.
  - Export: write segments to file (e.g., `.cap` per shard) or stream out via CLI/API with optional compression.
- Retention/quotas:
  - Per-tenant quotas and retention policies for capture streams; configurable compression (frame streams compress well).
  - Manifest tracks segments, checksums, and watermarks for raw/packet streams.
- Monitoring:
  - Capture drop metrics (if capture disabled due to quota), capture append latency, replay lag during backfill.

## OTP Append Log via `:disk_log` (local-friendly sink)
- Structure:
  - One `:disk_log` per shard and stream type (`telemetry`, `raw_frames`, `packets`). Use wrap mode with segment size caps (e.g., 128–512 MB) to prevent unbounded growth.
  - Maintain a lightweight manifest per shard: active segments, offsets, checksums, high watermark, retention policy.
- Retention/compaction:
  - Dev/local: wrap mode with max byte size or segment count (e.g., keep last N GB). Old segments overwritten automatically; emit metrics for retention-induced drops.
  - Prod-like: rolling segments plus explicit deletion by time/bytes. Optional compaction only for derived/aggregated streams; raw streams stay append-only.
- Integrity:
  - Prefix each record with length + CRC (per record or per batch). On startup, scan from last checkpoint; truncate to last good record on corruption.
  - Sync: fsync on interval (e.g., 50–200 ms) or after N bytes; expose fsync lag metric.
- Offsets/consumers:
  - Store consumer offsets per shard/group in a small file/ETS table; flush every N records or M seconds.
  - `LogSource.subscribe/2` wraps `:disk_log` reads with chunked delivery to honor backpressure.
- Dual-mode:
  - Same LogSink/LogSource behaviour; choose `:disk_log` adapter for local/dev, Kafka/Redpanda for cluster. Support dual-write in staging for cutover validation.
- Monitoring:
- Metrics: append latency, fsync lag, segment count/size, retention drops, consumer lag; alert on corruption/truncation events.

## Pseudocode Sketches

### Shard Worker (GenServer with batch loop)
```elixir
def init(state) do
  {:ok, %{queue: :queue.new(), count: 0, timer: start_timer(), config: load_bundle(), router_version: state.router_version}}
end

def handle_info({:ingest, event}, st) do
  q = :queue.in(event, st.queue)
  st = %{st | queue: q, count: st.count + 1}

  st =
    if st.count >= st.batch_size do
      flush(st)
    else
      st
    end

  if :queue.len(q) > st.high_watermark, do: signal_backpressure(:pause, st.shard_id)
  {:noreply, st}
end

def handle_info(:flush, st) do
  st = flush(st)
  {:noreply, %{st | timer: start_timer()}}
end

defp flush(%{count: 0} = st), do: st
defp flush(st) do
  # preserve FIFO order
  events = :queue.to_list(st.queue)

  processed =
    Enum.map(events, fn ev ->
      ev
      |> Identify.run(st.config)
      |> Decom.run(st.config)
      |> Convert.run(st.config)
      |> Derive.run(st.config)
    end)

  {:ok, append_latency} =
    LogSink.append(
      st.shard_id,
      processed,
      config_version: st.config.version,
      router_version: st.router_version
    )

  PipelineMetrics.inc(st.mission_id, st.shard_id, :packets_processed, st.count)
  PipelineMetrics.record_timing_sampled(st.mission_id, st.shard_id, :append, append_latency)

  if :queue.len(st.queue) < st.low_watermark, do: signal_backpressure(:resume, st.shard_id)
  %{st | queue: :queue.new(), count: 0}
end
```

### Autoscaler (per lane, vnode reassignment)
```elixir
def loop(state) do
  stats = collect_shard_stats() # depth, enqueue_rate, drain_rate, latency

  cond do
    needs_scale_out?(stats, state.policy) and cooldown_over?(state) ->
      state = scale_out(state)
      reassign_vnodes(state)
    needs_scale_in?(stats, state.policy) and cooldown_over?(state) ->
      state = scale_in(state)
      reassign_vnodes(state)
    true ->
      :ok
  end

  Process.send_after(self(), :tick, state.poll_interval)
  {:noreply, state}
end

def needs_scale_out?(stats, policy) do
  Enum.any?(stats, fn s ->
    s.depth > policy.high_watermark and s.drain_rate < s.enqueue_rate
  end)
end

def reassign_vnodes(state) do
  # Move virtual nodes across worker set; shard_id->key mapping stays stable
  assignments = rebalance(state.vnodes, state.workers)
  apply_assignments(assignments)
end
```

## Open Items / TODO
- Config bundle plumbing:
  - Decide storage (blob/object store vs DB), size limits, checksum/signing/encryption.
  - Define fetch/retry/backoff and adoption protocol; expose config_version adoption lag metrics.
- Routing policy surface:
  - Per-APID sharding policy (strict / seq / ts), defaults, and how policies are stored in bundles.
  - Admin/introspection endpoint to view current lane/shard policy and hash ring.
- Hash ring/vnode persistence:
  - Persist vnode→worker assignments (e.g., in control-plane store) and bump router_version on changes.
  - Provide a manifest endpoint for consumers to discover partitions and router_version.
- CVT consumer from sink:
  - Design checkpointing of offsets, batching strategy, and replay safety.
  - Define interaction with staleness monitor and limits ordering expectations.
- Limits state storage:
  - Where persistence counters/state live (ETS + periodic snapshot?), recovery on restart, and behavior on config_version changes (reset vs migrate).
- Lua sandbox detail:
  - Exact allowed libs, time/memory limits, per-script isolation model, logging/audit, and validation path for uploads.
  - Packaging/versioning of modules inside config bundles.
- Security / tenant isolation:
  - Per-tenant separation in sink directories/topics, capture/replay streams, and user script scoping.
- Testing/benchmark plan:
  - Load profiles to tune batch size/watermarks, append latency targets, failure injection (sink down/corruption), replay correctness tests.
- Operational runbooks:
  - Retention rotation for `:disk_log`, recovery from corruption, dual-write cutover to Kafka, dashboards/alerts to stand up first.
- Stateful lane checkpoints:
  - Checkpoint format/location, handoff protocol on reassignment, migration hooks for state shape changes.

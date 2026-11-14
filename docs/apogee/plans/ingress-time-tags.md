# Ingress time tags and observation identity v2 (api-ops; domain reviews)

Status: built 11-14 on `fix/ingress-time-tags` (api-ops), through qa; develop and main ports follow.
Rulings: DECISIONS #83 (backpressure and drops), domain's identity rule, and the director's replay ruling (version
slot yes, cutover and guard no). The `ingress_backpressure` attention source is a follow-up change (shape to fe-ops,
words to ux first).

## Release note

- **Fixed: telemetry time tags under load.** When persistence fell behind, the journal consumer merged several seconds of
  journal entries into one evidence record stamped with the *first* entry's receipt time. Every frame without on-board
  time got that one time tag, and then the frames of a point collapsed into one observation identity. Canonical
  history (the default view) showed 1 of N samples. Seen on 11-14 00:38:36–00:40:40Z for spacecraft 001 and 009 at
  8:1. Every frame now keeps the receipt time of the journal entry its first byte arrived in.
- **Changed: observation identity v2.** An identity is one measurement. A CCSDS packet's `{:seq, apid, seq_count}` is
  always in the digest. A frame with no sequence count whose generation time is the receipt fallback gets
  `{:pos, journal stream, byte offset}` (or `{:pos, session, frame seq}` without a journal). On-board time with no
  count is unchanged: an envelope without a ref digests exactly as v1 did. The envelope carries
  `generation_time_source` (onboard | receipt). `identity_digest_version` tells the truth: 2 only when a ref is in
  the digest (next to it), else 1. Both are stored on the observation row: the version in `metadata_json`
  (`identity_digest_version`), the encoded ref in `provenance_json` (`identity_ref`, e.g. `["seq", 42, 100]`), so a
  v2 identity can be explained and recomputed from the row. **A missing `identity_digest_version` key means v1**
  (rows from before this change, and v1-digested rows after it), never "unknown". **Ships by node restart, not reload:** `Sample`,
  `RawEvidence` and `ObservationEnvelope` gain struct fields, and in-flight processes hold the old structs. Every TM path today decodes CCSDS space packets, which always carry a count, so `{:seq, ...}` is what ships
  in practice; `{:pos, ...}` is supported in the digest but no producer sets it yet. Derived values take their
  trigger's ref.
- **No migration, no cutover.** Rows written before this change stay as they were, including the collapsed identities
  from 11-14 00:38–00:40Z (QuestDB still has every physical row). Nothing re-persists live data under the live
  context: a replay run writes its own realm and `replay_run_id`, both in the digest, so it never revises live
  identities under any version; and journal consumers only move forward (a cursor regression is refused), so boot
  recovery and #71 replay read only entries that were never persisted.
- **Deploy with a graceful stop (journal sealed), not a kill.** The one edge: a frame persisted but not yet
  acknowledged when the node crashes is persisted again at boot. If that crash straddles this deploy, the frame was
  written under v1 and recovers under v2: one duplicate canonical identity per in-flight batch, once. A graceful stop
  seals the journal (every cursor at the tail), so nothing is in flight.
- **Backpressure (#83).** `Cadence.Ingress.ReceiveBackpressure.on_full/3` decides and counts:
  - a push-back transport (TCP) pauses: it stops reading and flow control holds the sender. Lossless; only stamps
    beyond the buffer arrive late. Counted as `cadence.telemetry.ingress.reads.paused` (`buffer`: journal | executor).
    The TCP reader already paused, never dropped, on a full journal (`tcp_socket.ex`) and at the executor high
    watermark; this change counts it;
  - a transport that can't push back drops the frame, counted as `cadence.telemetry.ingress.frames.dropped`. No such
    transport exists today (only `tcp_socket`), so this is a seam pinned by one test transport. No UDP adapter is
    built;
  - follow-up: the `ingress_backpressure` attention item (journal near full; frames dropped), with the journal
    utilisation read.
  - The TCP reader already stopped reading at the executor high watermark (`tcp_socket.ex:847`) and paused, never
    dropped, on a full journal (`tcp_socket.ex:780`). This change adds stamps, counts and the attention item, not a
    new reader.
- **Fixed: persistence failure class.** A crash in ingress persistence was classed `unknown`, because it was formatted
  into a string. It now carries the exception's module (for example `DBConnection.ConnectionError`).

## Root cause (11-14 00:39:09.829Z persistence_failed, and the 2-minute stall)

1. The socket reader stamps at recv (`provider_adapters/tcp_socket.ex:742`) and appends to the 8 GiB journal. It
   never paused tonight.
2. The journal consumer keeps one batch in flight (`runtime/ingress_journal_consumer.ex`). Under slow persistence,
   entries pile up and the next take gathers them all.
3. `ingress_journal/evidence.ex` `from_contiguous_entries` merged them with `receipt_time: first.receipt_time`.
4. With no on-board time, the frame codec's `timestamp: source_time || receipt_time`
   (`protocol/tm_frame_ingress.ex`) gave every packet in the batch the first entry's time.
5. The v1 identity digest (`telemetry/storage/observation_envelope.ex`) has generation_time and nothing per frame,
   so N frames collapse into one identity.
6. Colliding envelopes skip the batched insert and take the per-row `SELECT ... FOR UPDATE` path
   (`telemetry/storage/observation_identity_states.ex`). Persistence slows, the next merge is bigger, and so on. The
   15 s connection kill was the worst batch of this loop.

## Who saw 1 of N in that window

- History in the canonical view, which is the default (`SelectionPolicy`): QuestDB `sample_history` filtered by
  `list_for_selection`. That covers point history, the M26 verifier plot, dashboard history and exploration.
- Alarms, limits, derived telemetry and the semantic runtime read the live stream. They evaluated every sample, but
  with equal observed_at. Limits ordered the ties by the `sample_id` hash, i.e. arbitrarily. Not observed to change a
  decision on 11-14 (001's sc_mode was constant; `telemetry_limit_events` is empty).
- Follow-up (domain's item 3): order ties by a `frame_ordinal` on the Sample (seq_count unwrapped per apid, else the
  journal offset or frame seq).

## Tests

- Domain's:
  - Two frames sharing a receipt stamp with no count give 2 identities.
  - The same frame replayed from the journal gives 1 identity at revision 2.
  - The same `{apid, seq, gen_time}` via two journal offsets gives 1 identity.
  - A seq-count wrap with a different gen_time gives 2 identities.
- The director's:
  - TCP backpressure loses nothing, and receipt_time isn't shifted.
  - The journal path pauses rather than drops.
  - A test transport with `push_back?: false` drops with a count plus an attention item.
- Why no cutover (the director's two):
  - A replay run's identities never equal the live ones for the same frames (`observation_envelope_test.exs`).
  - A journal cursor regression is refused (`ingress_journal/file_system_test.exs`).
- Error class: a raised `DBConnection.ConnectionError` gives `error_class == "DBConnection.ConnectionError"`, and
  the batch is retried, not dropped (`ingress_persistence_projector_test.exs`).
- Where they live: `protocol/tm_frame_ingress_test.exs`, `runtime/ingress_journal_time_tags_test.exs` (the merge,
  which fails on the old code with every frame at the first record's time), `runtime/tcp_socket_backpressure_test.exs`
  (end to end, nothing lost), `telemetry/storage/observation_identity_v2_test.exs`, `ingress/receive_backpressure_test.exs`.
- Note: `config/test.exs` takes one journal record per processing batch (production takes 8), so no test merged
  records before this change. That's how the bug went unseen; the merge test sets 8 explicitly.

## Test-config values that switch off a production path (director's sweep; listed, not changed)

`processing_max_batch_entries: 1` is how the merge bug hid. Every `config/test.exs` value that differs from what
production runs is listed below for the director to decide. "Hides a path" means production code that no test reaches
with this value (unless a test overrides it explicitly).

**apps/cadence/config/test.exs**

| Key | Test | Production (config.exs / code default) | Hides a path? |
|---|---|---|---|
| `ingress_journal.processing_max_batch_entries` | 1 | 8 | **Yes, the journal merge** (this bug). Now pinned by `ingress_journal_time_tags_test.exs` at prod's size, read from config.exs |
| `ingress_journal.processing_max_batch_bytes` | 256 KiB | 2 MiB | Partly: the byte cap is never what ends a batch in tests (moot while entries = 1) |
| `ingress_journal.max_bytes` / `segment_bytes` | 64 MiB / 1 MiB | 8 GiB / 256 MiB | No for logic; more segment rolls in tests than prod (fine). Journal-full is reached only by unit tests with explicit opts |
| `ingress_journal.durability` | `:page_cache` | `:sync` | **Yes, fsync per append** is never exercised under the runtime (its latency is part of backpressure). Follow-up 4 (director 11-14): the seal/recovery path runs under `:sync` in `ingress_journal/file_system_test.exs`, whose setup uses `durability: :sync`: "sealing requires both consumers, persists their positions, and closes admission", "recovers published records and truncates a torn tail" and "replays acknowledged entries after a crash before cursor checkpoint". The runtime path stays on `:page_cache` (lead: no runtime-level harness) |
| `ingress_journal.checkpoint_interval_ms` | 25 | 250 | No (faster, same path) |
| `ingress_journal.enabled?` | true | **false** (config.exs; dev/:4011 turns it on) | Inverse: the journal-less TCP path, the **production default**, runs only where a test opts out. Worth a check that it has its own coverage |
| `start_background_jobs` | false | true | **Yes**: background jobs never start under the app; tests drive jobs directly |
| `control_supervisor.start_mission_recovery?` | false | true (code default) | **Yes**: boot recovery of missions never runs in the app's tree |
| `event_bus.delivery` | `:sync` (+ sandbox allow) | `:async` (code default) | **Yes**: async delivery ordering/races never exercised. Follow-up 3 (director 11-14): `platform/async_fact_delivery_test.exs` runs the ingest → verifier (`Control.RuntimeFactConsumer`) and ingest → latest values / limits (`Projections.TelemetryFactConsumer`) flows on an `:async` bus: the publisher never waits on a busy consumer, every fact arrives in order, a failed refresh doesn't stop later ones, and an async consumer reaches the DB via the sandbox hook. The bulk stays `:sync` |
| `contact_scheduler.enabled` | false | true | **Yes**: the scheduler's own loop; tests call it directly |
| `contact_scheduler_global_safety.enabled` | false | false | No (same) |
| `provider_reservation_reconciler.enabled` | false | true (5 s poll) | **Yes**: the reconcile loop |
| `provider_event_ingestion.enabled` | false | true (code default, `control/supervisor.ex`) | **Yes**: ingestion loop |
| `provider_local_credentials.enabled` | true | not set in config.exs (dev.exs sets true) | Inverse: tests use a dev-only credential backend |
| `command_dispatcher.enabled` | false | true | **Yes**: the dispatcher loop (dispatch tests call it directly) |
| `command_verifier_scheduler.enabled` | false | true | **Yes**: verifier timeouts are only fired by tests that drive them (relevant to tonight's P9CS) |
| `password_hash_iterations` | 1 000 | 100 000 | No (cost only) |
| `ingress_archive.module` | Postgres | FileSystem | **Yes**: the production archive backend is only reached by its own unit tests |
| `protocol_record_archive.module` | Postgres | FileSystem | **Yes**, same |
| `telemetry_current_value_store.module` | Postgres | ETS | **Yes**: production's hot-path store is not the one the runtime tests use |
| `telemetry_storage.writer` | `OutageTelemetryWriter` (Postgres) | QuestDB | **Yes**: the QuestDB writer only via its own/smoke tests |
| `telemetry_history_store.module` | Postgres | QuestDB | **Yes**: production history reads (incl. canonical selection) not under runtime tests |
| `data_sources.persisted?` / `bootstrap_defaults?` | false / false | true / true | **Yes**: data-source bootstrap |
| `dashboard_source_circuit_breaker.enabled?` | false | true | **Yes**: the breaker |
| `data_source_health_events.enabled?` | false | true | **Yes** |
| `data_source_probe_scheduler.enabled?` | false | true (60 s) | **Yes** |
| `data_source_watermark_events.enabled?` | false | true | **Yes** |
| `Repo.pool_size` | schedulers × 2 (sandbox) | per env | No (sandbox) |

**apps/cadence_web/config/test.exs**

| Key | Test | Production | Hides a path? |
|---|---|---|---|
| `dashboard_live_refresh_ms` | 60 000 | 1 000 | **Yes**: live dashboard refresh ticks effectively never fire in tests |
| `dashboard_engine_source_execution.source_execution_max_concurrency` | 1 | 4 (`SourceExecutionPolicy` default) | **Yes**: concurrent source execution |
| `dashboard_engine_source_execution.source_execution_timeout_ms` | `:infinity` | 5 000 ms (`SourceExecutionPolicy` default) | **Yes**: the source timeout path |
| `live_vue.enable_props_diff` | false unless `CADENCE_BROWSER_PROPS_DIFF` | live_vue's default (not set in config.exs) | Documented: browser tests in a separate VM cover the incremental protocol |
| provider live opts (fake client/backend) | fakes | real | Expected (external services) |

**apps/cadence_simulator/config/test.exs**: `provider_http.enabled` false = config.exs false. No difference.

Most of the "Yes" rows are deliberate (loops tests drive by hand, external stores). The ones that look like
tonight's bug, a *data-path* setting that changes how production batches or orders data, are: the journal batch size
(fixed here), `durability`, `event_bus.delivery`, and the Postgres stand-ins for QuestDB/ETS/FileSystem in the
telemetry hot path. Director to decide each.

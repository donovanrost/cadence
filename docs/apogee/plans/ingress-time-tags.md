# Ingress time tags and observation identity v2 (api-ops; domain reviews)

Status: approved design, build starting 11-14 after the 01:00Z freeze. Ships on ui/apogee-spa, with develop and main ports.
Rulings: DECISIONS #83 (backpressure and drops), domain's identity rule, and the director's replay plan (versioned digest).

## Release note

- **Fixed: telemetry time tags under load.** When persistence fell behind, the journal consumer merged several seconds of
  journal entries into one evidence record stamped with the *first* entry's receipt time. Every frame without on-board
  time got that one time tag, and then the frames of a point collapsed into one observation identity. Canonical
  history (the default view) showed 1 of N samples. Seen on 11-14 00:38:36–00:40:40Z for spacecraft 001 and 009 at
  8:1. Every frame now keeps the receipt time of the journal entry its first byte arrived in.
- **Changed: observation identity v2.** An identity is one measurement. A CCSDS packet's `{:seq, apid, seq_count}` is
  always in the digest. A frame with no sequence count whose generation time is the receipt fallback gets
  `{:pos, journal stream, byte offset}` (or `{:pos, session, frame seq}` without a journal). On-board time with no
  count is unchanged. The envelope carries `generation_time_source` (onboard | receipt) and
  `identity_digest_version`.
- **Replays of data ingested before the cutover.** Each mission records its v2 cutover (the `ingested_at` of its
  first v2 row). A replay of a pre-cutover range computes v1, so it lands as revisions of the existing identities, with
  no migration. If the replay path can't see a frame's original ingest time, the replay of a pre-cutover range is
  refused with a clear error instead. **Rows ingested before the cutover stay as they were**, including the collapsed
  identities from 11-14 00:38–00:40Z. QuestDB still has every physical row.
- **Backpressure (#83).**
  - Journal path: never drops. The consumer pauses, the backlog is counted, and an attention item is raised as the
    journal nears full.
  - TCP without a journal (the production default): stops reading when the bounded buffer is full, so TCP flow
    control holds the sender. Lossless; only stamps beyond the buffer arrive late.
  - The shared receive buffer takes `push_back?`. A transport that can't push back drops with a count and an attention
    item, never silently. No such transport exists today (only `tcp_socket`), so this is a seam pinned by one test
    transport. No UDP adapter is built.
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
- Replay:
  - A pre-cutover replay lands as revisions (v1).
  - A post-cutover replay lands as v2.
  - Or, as the fallback, the guard refuses the pre-cutover range.
- Error class: a raised `DBConnection.ConnectionError` gives `error_class == "DBConnection.ConnectionError"`.

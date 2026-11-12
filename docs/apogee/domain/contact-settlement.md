# Contact settlement: ending a contact never waits on the TSDB (DECISIONS #71)

Status: built 2026-11-11 (see "As built" below). Replay is the next item.
Portable: Contacts/Runtime only, no Apogee-only modules; develop has the same bug.

## The bug

Completing or stopping a realized contact ran inside the contact scheduler:

```
Contacts.Scheduler (GenServer)
  → Contacts.reconcile → ContactLifecycle.complete_realized
  → Runtime.stop_realized_contact_sync
  → ContactCoordinator.quiesce → PathCoordinator.quiesce
  → ProviderIngressExecutor / IngressPersistenceProjector .quiesce
```

Every hop is `GenServer.call(…, :infinity)`. Quiesce waits until the path's persistence queue
is empty, and the projector retries a failing write every 100 ms forever. So **a TSDB outage
spanning one contact's LOS blocks the scheduler**. Nothing else is realized, completed or
expired for any contact it owns until the TSDB is back.

`complete_realized` also writes `:completed` before it stops the runtime. The next reconcile
only looks at active contacts, so a stop that fails is never retried, and the runtime outlives
its contact.

Seen on qa, 2026-11-11, while the host slept:

- 010's contact was completed at 12:35:58Z, with QuestDB unreachable (all 202
  `persistence_failed` were `Req.TransportError`).
- The scheduler then sat in 010's quiesce, and 010's runtime kept logging until 17:09:08Z.
- 037's 13:10:59Z pass was never realized. It was expired at 17:09:20Z, 12 s after 010's
  queue drained.

The host sleep made the outage. The freeze is the bug.

## Design

1. **The scheduler never waits on a runtime.** Complete and stop record the lifecycle
   transition, then hand the runtime to a supervised per-contact settler and return.
   The scheduler doesn't call quiesce.
2. **Intake stops at LOS.** The settler first stops the path's transport and provider
   runtimes, so nothing new is accepted for an ended contact. Journal, journal consumer,
   executor and projector keep running.
3. **Settling is a visible phase.** The realized contact records `settlement:
   %{state: settling | settled | unsettled, …}`.
   - `settled`: the journal processing cursor reached the end and every queue is empty. The
     remaining processes stop.
   - The settling deadline is long (hours, with backoff on the projector's retries). Nothing
     waits on it. It bounds resources and isn't a timeout.
   - When it expires, the processes stop and the realized contact records `unpersisted_journal:
     [%{path_id, provider_binding_id, from_offset, to_offset, entries, bytes}]` (durable), with
     state `unsettled`.
4. **Nothing is dropped.** The journal advances its processing cursor only on semantic
   persistence. It reclaims a segment only when every consumer's durable cursor has passed it,
   and when full it refuses new writes rather than evicting. So an unsettled backlog stays on
   disk. A test pins this: no segment named in `unpersisted_journal` is reclaimed.
5. **Replay settled journal** (follow-up, right after this, before #36). A settle-only path
   runtime opens the journal, recovers its cursors and drains `unpersisted_journal` to the
   TSDB, then clears it. It starts automatically from reconcile once the TSDB is healthy, so
   stranded data doesn't need a human. Until then, `unsettled` is the honest state.
6. **Attention.** An `unsettled` contact raises an attention item naming the contact,
   spacecraft and backlog size (entries and bytes). It clears when replay settles it.
7. **Sweep.** Reconcile also finds realized contacts in `completed | stopped` whose runtime
   is still running and isn't settling, and hands them to a settler (idempotent). A failed
   stop gets retried.

## Tests

- A TSDB outage spans contact A's LOS. Contact B realizes and completes on schedule meanwhile.
  A reads `settling`, then `settled` when the TSDB returns. No telemetry is lost.
- The settling deadline expires: A is `unsettled` with `unpersisted_journal`, its processes
  stopped, its segments still on disk, and the attention item names it and the backlog.
- Sweep: a completed contact with a live runtime is settled on the next reconcile.
- Journal GC never reclaims a segment beyond the processing cursor.

## As built

- `ContactLifecycle.complete_realized` / `stop_realized_transition` record the end with
  `settlement: %{state: "settling", started_at, deadline_at}` and call
  `ContactSettler.settle/1`, which returns at once. Nothing on the scheduler's path quiesces.
- `Cadence.Contacts.ContactSettler`: one registered, temporary GenServer per contact under a
  `DynamicSupervisor` in `Control.Supervisor` (unlinked fallback when that supervisor isn't
  there, e.g. after a code reload). It runs the existing quiesce (transports and providers
  first, so intake stops at LOS) in a monitored worker, with a deadline timer:
  - drained: stop the runtime, `settled`;
  - deadline or quiesce error: read the backlog (`Runtime.ContactBacklog`: each journal's
    durable processing cursor to its tail, plus the projectors' last errors), stop the runtime
    without quiescing (`Runtime.terminate_realized_contact`), `unsettled` with `reason`,
    `failure_kind` (`telemetry_storage_unavailable` when storing failed, else nil for a slow
    drain, or `settle_failed`), `failure_message`, `unpersisted_journal` and `backlog` totals.
  - Runtime not running when the settler starts: `settled` with `runtime: "absent"`. Its
    journal on disk wasn't inspected. **Replay must inspect these** (and contacts ended before
    #71), since a node restart mid-settle lands here.
  - Already `settled`/`unsettled`: `settle/1` is a no-op, so a second stop can't hide a backlog.
- Deadline: `config :cadence, :contact_settlement, deadline_ms:` (default 6 h). The projector
  backs off 100 ms doubling to `:ingress_persistence_projector, retry_max_ms:` (default 30 s).
- Sweep: every reconcile hands `settling` contacts with no settler, and pre-#71 ended contacts
  whose runtime still runs, to a settler (`settling_realized_contact_ids` in the summary).
- Attention source `contact_settlement` (`ContactSettlementAttention`, ux U37): one item per
  `unsettled` contact, P2, no acknowledge (the controller 404s it), `retry: "automatic"`,
  `expires_at: nil`; resolves as `replayed` when replay sets `settlement.replayed_at`.
- Journal snapshot gains `processing_backlog: %{from_offset, to_offset, bytes, entries}`.
- Known: while a path quiesces, its `PathCoordinator` is busy in the quiesce call, so a path
  snapshot of a settling contact waits. Nothing on the scheduler's path takes one.

- Test env: the telemetry writer is `Cadence.OutageTelemetryWriter` (Postgres read model
  unless a test turns an outage on); the runtime reads its storage policy at boot, so a test
  can't swap writers per test. The Postgres record archive (test-only; dev and prod use the
  file-system archives) now inserts frames and packets with `on_conflict: :nothing`, like raw
  evidence and anomalies, so a batch retried after a failed telemetry write doesn't hit its own
  committed rows.

Tests: `contact_settlement_test.exs` (outage across A's LOS while B realizes, completes and
settles; deadline expiry with the backlog on disk and the attention item; the sweep),
`file_system_test.exs` (no reclaim past the processing cursor, across a restart),
`attention_api_test.exs` (acknowledge/resolve 404).

## Replay settled journal (design approved by director 2026-11-11; build after the #65 armed pass)

Goal: stranded telemetry reaches the TSDB without a human. Nothing new is needed on disk: an
ended contact's journals live at a path derived from `{mission, realized contact, path,
binding}`, with checkpointed cursors, and recovery already resumes from the durable processing
cursor.

1. **Replay runtime = the contact runtime without intake.** `RealizedContactRuntimeSpec`
   gains `intake: false`. `PathCoordinator` then starts journal, persistence projector,
   executor, journal consumer and archive consumer as now, but no provider adapter and no
   transports. The consumer resumes from the durable cursor and drains through the normal
   executor and projector; nothing about decoding or persistence forks.
2. **The settler settles it.** Replay is `start (intake: false)` then the existing settler with
   the same quiesce, deadline (shorter: 30 min default), backlog read and terminate.
   - Drained: `settled`, plus `replayed_at` (resolves the attention item as `replayed`).
   - Not drained: back to `unsettled`, the backlog re-read, `attempts + 1`, and
     `next_attempt_at` = now + backoff (5 min doubling to 2 h). The attention item then shows
     `next_attempt_at` (ux U37).
3. **Who replays.** Reconcile's sweep, at most one replay per mission at a time:
   - `unsettled` contacts whose `next_attempt_at` has passed;
   - `settled` with `runtime: "absent"` and no `inspected_at`, and contacts ended before #71
     (`settlement` nil, ended): only if a journal directory exists for one of their downlink
     provider bindings. A replay with nothing to drain settles at once and records
     `inspected_at`, so each is inspected once.
   No TSDB health probe is needed: a failing replay just backs off, and the first attempt after
   storage returns drains it.
4. **Bounded.** One replay per mission at a time; pre-#71 contacts are checked oldest first, a
   few per reconcile; a replay never runs while the same contact's settler runs.
5. **Tests.** Unsettled contact (deadline test setup), outage off, reconcile: replayed,
   `settled` + `replayed_at`, samples stored exactly once (idempotent persistence), attention
   resolved as `replayed`. Still failing: back to `unsettled` with `next_attempt_at`. A
   pre-#71 contact with a journal backlog on disk is found and drained; one without a
   journal directory is skipped.

6. **Give up after 6 failed replays** (about half a day with the backoff). The contact stays
   `unsettled` with `replay: "stopped"`; the attention item turns to needs-operator
   (`retry: "manual"`, `next_attempt_at: nil`, `attempts: 6`) and offers one operator action:
   retry replay now (`POST /attention/contact_settlement/:id/retry`), which resets the count.
   The backlog stays on disk either way.

Director (2026-11-11): 30 min deadline per replay, backoff 5 min doubling to 2 h, one replay
per mission at a time, stop after 6 failures.

**Built 2026-11-12 (1d6be29f).** As designed, with these specifics:
`RealizedContactRuntimeSpec.intake?`; `ContactSettler.replay/2` (registered per mission);
`ContactSettlement.next_replay/4` and `record_replay/4`; `IngressJournal.FileSystem.stored_streams/1`
reads each stream's `stream.term` context without opening it. A contact ended before #71 reads
`state: "inspecting"` while its replay runs, so the settle sweep leaves it alone; a drained one
reads `settled` with `inspected_at` (`replayed_at` only when it had been `unsettled`). Journal
stream directories are never deleted, so `stored_streams/1` grows with every journaled contact;
fine at this scale, a cleanup policy is future work.

## Journal off (2026-11-12)

The ingress journal is opt-in (`config.exs`: `enabled?: false`; `CADENCE_INGRESS_JOURNAL_ENABLED`
in `runtime.exs`). With it off there is nothing on disk: a frame that fails processing is
dropped, and a TSDB outage's backlog lives only in the projector's memory, lost when the runtime
stops. Settlements record `journal: "disabled"`, and an unsettled one carries `backlog.queued`
and `backlog.lost: true`; such an item closes only by an operator's acknowledge (ux "Mark as
seen", recorded with who and when), never by replay. qa's dev stack runs with it on since
2026-11-12 00:57Z.

Trade-off for the prod default (the user's call): on costs disk (bounded by `max_bytes`, 8 GiB per
stream by default) and a synchronous append per received chunk (`durability: :sync`, an fsync
per batch; `:page_cache` trades a host crash's last writes for less IO). Off loses whatever
didn't reach the TSDB when processing fails or a node stops mid-outage, and #71's
nothing-dropped guarantee doesn't hold.

## Not covered by c732a2ba

c732a2ba is partition-owner initialization backoff in `MissionCoordinator`. It doesn't touch
the contact scheduler or quiesce.

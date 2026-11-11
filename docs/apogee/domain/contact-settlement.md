# Contact settlement: ending a contact never waits on the TSDB (DECISIONS #71)

Status: design approved by director (2026-11-11), implementation after the #65 live run.
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

## Not covered by c732a2ba

c732a2ba is partition-owner initialization backoff in `MissionCoordinator`. It doesn't touch
the contact scheduler or quiesce.

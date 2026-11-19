# group-requests.md §10 Q5: lock duration under `with_command_catalog` (domain review)

**Short answer:** the 5,000 bound is fine. Validating and creating 5,000 members *inside*
`with_command_catalog` is not. Validate outside the lock, then do a short locked commit.

## What the lock is

- `Activations.with_locked_command_basis/3` (`L/activations.ex:79`) is a `Repo.transaction` with
  the **default 15 s timeout**. It holds `SELECT … FOR SHARE` on the mission's
  `mission_active_binding_sets` row.
- Other command authoring can run alongside (both are share locks).
- **An activation can't.** `persist_activation` updates that row, so it waits for every share
  holder. Activations now have a 120 s timeout (fleet snapshot work). A long group submit
  therefore delays any configuration activation of that mission, and a slow one fails it.

## Cost of the current plan

Per member, the exact-preview path is `RequestAuthoring.preview` + `create`. Measured on similar
paths, that is roughly 5–20 ms on an idle machine and several times that under today's load
(load average 40+). At N×K = 5,000 that comes to **25–100 s or more inside one share-locked
transaction**. It exceeds the 15 s timeout and holds a pool connection the whole time. Chunks of
25 bound the size of each validation, not the lock.

## Recommendation

1. **Preflight (no lock, read-only, chunked):**
   - Resolve each target's basis (`for_target`). That's an indexed `entry_for_source` lookup
     now, with fleet snapshot v2.
   - Cache `command_authoring_basis` per mission-model manifest: targets share a few manifests,
     and you can group by `FleetSnapshot.commanding_entries/1`.
   - Run the exact validation for every member and produce the **preflight digest** over
     `{activation_id, generation, catalog token, [validated member payloads]}`. You already have
     the digest; make it cover the validated payloads.
2. **Submit (locked, short):** inside `with_command_catalog`:
   - Check that the snapshot token / activation identity still matches the digest's. If not,
     return `409 preflight_stale`, as designed.
   - Bulk-insert the group, the members and the queue entries with `insert_all` in chunks of
     500, with no per-member re-validation.
   - Target: **≤ 2 s of lock at 5,000 members.** Pass an explicit
     `Repo.transaction(timeout: 30_000)` to `with_locked_command_basis` as headroom; that needs
     an opts arg there, so I'll add it if you want.
3. **Decide:** same shape. Re-check the digest under the lock, then bulk-insert the approval
   rows and enqueue. No per-member preview.
4. **Test:** add one 5,000-member submit test asserting the transaction finishes. Measure lock
   time with `:timer.tc` around the locked fun and log it. Keep it as a targeted test, given the
   machine load rule.

With that, the bounds N ≤ 1,000 / K ≤ 16 / N×K ≤ 5,000 are OK from the domain side.

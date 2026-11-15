# Release checklist (develop and main deploys)

Run before deploying a branch to an environment. Each line names why it exists.

## Before the deploy

1. **Release-target SCIDs (#97, DECISIONS #84 background).** Run
   `docs/how-to/check-release-target-scids-before-deploy.md` (on main since 9e6ee41e). A binding or
   gateway without a SCID makes queued commands for that spacecraft WAIT (the lane skips that
   contact), and an operator-named release to it is refused and cancelled. Fix the data first, or
   don't deploy.
2. **No live pass, nothing starting soon, nothing armed** (qa runbook pre-flight, 15df1aac2): no
   active realized contact, nothing starting within 15 minutes, no armed command group. A stop during
   a live pass replays its journal on boot (issue 60).
3. **Ingress journal disk** (on by default, DECISIONS #95). Every downlink's received bytes are
   journaled before processing, at `CADENCE_INGRESS_JOURNAL_PATH` (default
   `/var/lib/cadence/ingress_journal`): put it on a persistent volume, not the container's writable
   layer. Size: about the downlink's own byte rate plus a little framing, ~50 MB per contact-hour
   per downlink at the dev simulator's rate (one 8-minute pass ≈ 7 MB); scale with your links' bit
   rates. A contact's stream is deleted 72 h after the contact settles, and only once every byte
   is in the ingress archive (JournalReclaim). So the volume must hold 72 h of contact plus any
   undrained backlog: `CADENCE_INGRESS_JOURNAL_MAX_BYTES` (default 8 GiB) caps it, and a full journal
   refuses new bytes (`ingress_journal_full`, the capacity_exhausted event), so size the cap and the
   volume to the 72 h figure with headroom. To run without it, set
   `CADENCE_INGRESS_JOURNAL_ENABLED=false` (supported; without it a stop during a pass loses that
   pass's unprocessed bytes).
4. **Struct changes** (runbook gate, 84aaa0811): if the release adds or removes a struct field, plan
   a node restart, not an in-node reload; in-flight processes hold the old struct.

## The deploy

5. **Graceful stop, journal sealed, never a kill** (ingest identity v2, DECISIONS #83). A kill can
   re-persist one in-flight batch under the new identity digest.
6. **After a `mix.lock` change**, run `mix deps.get` in each app (`apps/cadence`,
   `apps/cadence_web`, `apps/cadence_simulator`).

## After the deploy

7. **No replay of telemetry ingested before identity v2** without a decision (DECISIONS #83);
   replaying it would give new identities next to the old ones.
8. **Smoke:** sign-in, Now loads, one contact's telemetry arrives with distinct receipt times, and
   `persistence_failed` stays at 0.

Add a line here whenever a release note says "before deploying" or "after deploying".

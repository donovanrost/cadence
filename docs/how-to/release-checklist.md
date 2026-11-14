# Release checklist (develop and main deploys)

Run before deploying a branch to an environment. Each line names why it exists.

## Before the deploy

1. **Release-target SCIDs (#97, DECISIONS #84 background).** Run
   `docs/how-to/check-release-target-scids-before-deploy.md` (on main since 9e6ee41e). With a
   gateway or spacecraft missing its SCID, the release target guard fails closed: queued commands
   wait (the lane skips that contact), and an operator-named release is refused and cancelled.
   Commanding to that spacecraft stops until the data is fixed. Fix the data first, or don't deploy.
2. **No live pass, nothing starting soon, nothing armed** (qa runbook pre-flight, 15df1aac2): no
   active realized contact, nothing starting within 15 minutes, no armed command group. A stop during
   a live pass replays its journal on boot (issue 60).
3. **Struct changes** (runbook gate, 84aaa0811): if the release adds or removes a struct field, plan
   a node restart, not an in-node reload; in-flight processes hold the old struct.

## The deploy

4. **Graceful stop, journal sealed, never a kill** (ingest identity v2, DECISIONS #83). A kill can
   re-persist one in-flight batch under the new identity digest.
5. **After a `mix.lock` change**, run `mix deps.get` in each app (`apps/cadence`,
   `apps/cadence_web`, `apps/cadence_simulator`).

## After the deploy

6. **No replay of telemetry ingested before identity v2** without a decision (DECISIONS #83);
   replaying it would give new identities next to the old ones.
7. **Smoke:** sign-in, Now loads, one contact's telemetry arrives with distinct receipt times, and
   `persistence_failed` stays at 0.

Add a line here whenever a release note says "before deploying" or "after deploying".

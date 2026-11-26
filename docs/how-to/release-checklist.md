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
   journaled before processing, one stream per contact path, under `CADENCE_INGRESS_JOURNAL_PATH`
   (default `/var/lib/cadence/ingress_journal`): put it on a persistent volume, not the
   container's writable layer. A contact's stream is deleted 72 h after the contact settles, and
   only once every byte is in the ingress archive (JournalReclaim).
   - **Per stream:** `CADENCE_INGRESS_JOURNAL_MAX_BYTES` (default 8 GiB) caps ONE stream; a full
     stream refuses only its contact's bytes (`ingress_journal_full`; Now shows it at 80 %). The
     default is far above one pass (an 8-minute pass at the dev simulator's rate is about 7 MB).
   - **The volume:** nothing caps the SUM of all streams. When the volume fills, every stream's
     appends fail and telemetry from every pass is lost at once. Size the VOLUME by the rule:
     bytes ≈ Σ over downlinks (link byte rate × contact seconds within 72 h) × 1.5, plus the
     largest undrained backlog you expect (an archive outage).
   - **Worked example:** N craft × passes/day × pass seconds × 3 days × byte rate × 1.5. At the dev
     simulator's rate (~14 KB/s, ~50 MB per contact-hour) with 5 passes of 8 min a day: 10 craft ≈
     0.8 GiB, 100 craft ≈ 10 GiB, 500 craft ≈ 49 GiB; 500 craft at a 2 Mbit/s S-band link ≈ 880 GiB.
   - **Dev:** the default path in a checkout is the repository's `var/ingress_journal`, on the host's
     own disk (the disk that filled on 11-14); fine at 10 craft, but watch host free space.
   To run without it, set `CADENCE_INGRESS_JOURNAL_ENABLED=false` (supported; then a stop during a
   pass loses that pass's unprocessed bytes).
4. **Struct changes** (runbook gate, 84aaa0811): if the release adds or removes a struct field, plan
   a node restart, not an in-node reload; in-flight processes hold the old struct.
5. **Mission-model compiler version** (#559, mission-composition-design.md §3). If the release
   bumps the mission-model `compiler_version`, every composition gets a NEW candidate revision at
   the next compile, and approval never carries over from the old version. Craft keep running their
   approved older compile, so nothing is refused, unless the release also drops the old version from
   the runtime's runnable list. In that case every pin with no approved runnable revision is refused
   ('re-approval needed after a Cadence update') until an org admin approves the candidates. Say in
   the release notes which it is. If old versions stay runnable, approve the candidates at the
   team's pace; if they don't, approve them right after the deploy, before the next generation.

## The deploy

6. **Graceful stop, journal sealed, never a kill** (ingest identity v2, DECISIONS #83). A kill can
   re-persist one in-flight batch under the new identity digest.
7. **After a `mix.lock` change**, run `mix deps.get` in each app (`apps/cadence`,
   `apps/cadence_web`, `apps/cadence_simulator`).

## After the deploy

8. **No replay of telemetry ingested before identity v2** without a decision (DECISIONS #83);
   replaying it would give new identities next to the old ones.
9. **Smoke:** sign-in, Now loads, one contact's telemetry arrives with each frame stored once under
   its own identity, and `persistence_failed` stays at 0. Receipt times can tie: a receipt time is
   stamped per socket read, so frames from one read share it (#491).

Add a line here whenever a release note says "before deploying" or "after deploying".

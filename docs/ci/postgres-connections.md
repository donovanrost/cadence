# Proposal: local Postgres connection headroom

Status: **(A) applied** 11-14 07:55Z (director's approval; qa's go in restart 1). `max_connections` is now 200.
Written after the 05:47Z 100/100 incident, for lead, the director and qa.
This is about the shared local Postgres only; CI has its own Postgres per job and is not affected.

## Facts (checked 05:50Z)

- One Homebrew `postgresql@14` serves everything on this box (`/opt/homebrew/var/postgresql@14`):
  `max_connections = 100`, 3 of them reserved for superusers, so 97 are usable. Other projects'
  databases (gekko, lattice, dealdesk, …) live on the same server; none were connected.
- **The two dev nodes hold 60 connections between them, idle.** Each runs with `POOL_SIZE=30` in its
  environment (`:4011` → `cadence_apogee_dev`, and the main checkout → `cadence_dev`); the config default is 10
  (`apps/cadence_web/config/runtime.exs`).
- **Each full test suite holds 16.** The test pool is `System.schedulers_online() * 2`
  (`apps/cadence/config/test.exs`), which is 16 on this 8-core box. The activation, workflow and
  fleet-run locks also open short-lived single connections on top of that.
- So the headroom is 97 − 60 = **37: two full suites plus 5**. A third suite, an iex session or
  `ecto.create` on top of that hits the limit. At the limit, the `:4011` pool can't reconnect and qa's guard
  queries fail. That's what happened at 05:47Z (partitions 7 and 12, 16 each).

## Options

| | Change | Frees | Cost / risk |
| --- | --- | --- | --- |
| **A (recommended)** | `ALTER SYSTEM SET max_connections = 200`, then restart Postgres (fast stop; see the runbook below) | Headroom 37 → 137 (about 8 full suites; load etiquette caps us well below that anyway) | One Postgres restart (~5 s). Every connection drops: the dev nodes' pools reconnect on their own, but any in-flight request, test run or iex session fails. **It needs a qa slot with no armed pass.** Memory is fine: the box has 16 GiB, an idle backend costs a few MB, and `shared_buffers` (128 MB) is unchanged. It's one config line, and it's reversible the same way. |
| B | An overridable test pool: `pool_size: String.to_integer(System.get_env("CADENCE_TEST_POOL_SIZE", "#{System.schedulers_online() * 2}"))`, with partition owners setting 8 locally | 8 per suite | An app config change (its own commit). It only helps if everyone sets the variable. Async tests queue for a connection, since `max_cases` is still 16; with `queue_target: 5_000` that should mean slower, not failing, but it needs a measured run. CI is unchanged (4-core runners already get 8). |
| C | Dev nodes `POOL_SIZE` 30 → 10–15 | 30–40 with no Postgres restart | Each node needs a restart: `:4011` is qa's slot and the main checkout is the user's. 30 was presumably chosen for load: the runbook's live-feed note shows ingest stalling under load. qa's call, not mine. |

## Recommendation

**A, done inside qa's post-LOS restart slot** (the planned L4/L8/matrix/backpressure restart): restart Postgres
just before `:4011` comes back up, so the node starts on fresh connections and there's only one disruption. Keep
the runbook's headroom rule (start a full suite only below ~70 connections, and never in an armed window). After
the change, the threshold becomes ~170.

B is a fallback if a Postgres restart is refused. C stays qa's decision.

## Runbook for A (approved: devops runs it on qa's go, inside restart 1, just before `:4011` comes back)

1. **Preflight.** List every connected client:
   `select datname, application_name, client_addr, state, now() - xact_start as xact_age, left(query, 60) from pg_stat_activity where backend_type = 'client backend' order by datname`.
   Ecto pools (`:4011` → `cadence_apogee_dev`, `:4001` main checkout → `cadence_dev`) reconnect on their own.
   **Abort if a non-Cadence client (another project's database) is mid-work** (an active state or an open
   transaction), or if any test partition is mid-run. Also check advisory locks
   (`select pid, objid from pg_locks where locktype = 'advisory'`). A fleet-planning run, a data-management
   workflow or an activation execution holds one on a single connection with `backoff_type: :stop`, so a
   restart fails that operation. Wait for it to finish.
2. `psql -U postgres -c "ALTER SYSTEM SET max_connections = 200"` (written to `postgresql.auto.conf`).
3. `pg_ctl -D /opt/homebrew/var/postgresql@14 stop -m fast`. launchd (`KeepAlive`) starts it again on its own;
   poll `pg_isready` for up to 60 s, and if it isn't back, run `brew services start postgresql@14`.
   **Not `brew services restart`:** that sends SIGTERM, which is Postgres's *smart* shutdown. Smart shutdown waits
   for every client to disconnect and refuses new connections in the meantime. With `:4001`'s pool still open it
   hangs until launchd's 20 s exit timeout, then gets SIGKILLed, so startup would need crash recovery. Fast
   mode disconnects clients, checkpoints (at most `shared_buffers`, 128 MB) and exits cleanly.
   Expected downtime: ~3–10 s. Past starts after a clean shutdown took 1.2 s and 6 s (`postgresql@14.log`).
4. `psql -U postgres -Atc "show max_connections"` → 200.
5. Check that `:4001` reconnected (`cadence_dev` connections in `pg_stat_activity`, and an HTTP 200 from :4001).
   `:4011` comes back afterwards in qa's restart.

**What `:4001` (main checkout) sees:** each pooled connection is closed by the server
(`57P01 terminating connection due to administrator command`). A query in flight at that moment fails, and an
open LiveView may remount. DBConnection reconnects every pool connection on its own, with backoff (default 1–30 s,
randomized exponential), so the app doesn't crash or need a restart. The exception is the lock connections in
the preflight note.

**To revert:** `ALTER SYSTEM RESET max_connections`, then restart Postgres again (back to the
`postgresql.conf` value of 100).

## Applied

11-14, in qa's restart 1, with `:4011` stopped at 07:54:36Z:

- **Preflight, 07:54:52Z:** only `cadence_dev` (`:4001`) was connected, with 30 idle connections. There were no open
  transactions, no advisory locks and no non-Cadence clients.
- **The change:** `ALTER SYSTEM SET max_connections = 200`, then a fast stop at 07:55:03Z. Postgres shut down
  cleanly at 07:55:04Z; launchd started a new postmaster, which was ready at 07:55:05.08Z with no crash recovery.
  **Downtime was about 2 s.**
- **Afterwards:** `show max_connections` returned 200. `:4001` reconnected (30 idle connections to `cadence_dev`)
  and answered HTTP 302 on `/`.
- `postgresql.auto.conf` now holds `max_connections = '200'`. To revert, see above.

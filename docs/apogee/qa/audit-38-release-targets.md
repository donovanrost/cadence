# qa #38 audit: release attempts on another spacecraft's uplink

Run by api-ops on 2026-11-10 against `cadence_apogee_dev` (qa's :4011 stack), DECISIONS #66 item 4.
It lists every command release attempt. The verdict compares the request's target endpoint
(`spacecraft_runtime:<spacecraft>`) with the realized contact's `source_endpoint_refs`, and checks
that the route named in `path_id` is the target's.

**Result: 4 of 5 release attempts went out on another spacecraft's contact and uplink route.**
3MKNW (004 SET_MODE on 004's own route, 2026-11-09 18:26Z) is the only correct one.

| attempted (UTC) | group | command | target | released on (contact / route) | verification | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 11-09 12:17:24 | I2DO | NOOP | earendil-001 | earendil-009 / route-spacecraft-earendil-009-uplink | not_required | **WRONG SPACECRAFT** |
| 11-09 18:26:36 | 3MKNW | SET_MODE | earendil-004 | earendil-004 / route-spacecraft-earendil-004-uplink | not_required | ok |
| 11-10 02:22:10 | 4FSOI | NOOP | earendil-004 | earendil-007 / route-spacecraft-earendil-007-uplink | timed_out | **WRONG SPACECRAFT** |
| 11-10 02:22:10 | 4FSOI | SET_MODE | earendil-004 | earendil-007 / route-spacecraft-earendil-007-uplink | satisfied (on 007's telemetry) | **WRONG SPACECRAFT** |
| 11-10 02:22:10 | 4FSOI | NOOP | earendil-004 | earendil-007 / route-spacecraft-earendil-007-uplink | satisfied (on 007's telemetry) | **WRONG SPACECRAFT** |

The `satisfied` verifications on 4FSOI were evaluated against 007's telemetry (DECISIONS #66,
item 3). They don't show that 004 executed anything.

## Query

```sql
-- qa #38 audit: release attempts whose contact/route isn't the request's target spacecraft.
select a.attempted_at,
       a.command_release_attempt_id                         as attempt,
       r.command_group_id                                   as grp,
       a.command_name,
       a.lifecycle_state                                    as attempt_state,
       a.verification_state,
       a.source_endpoint_ref                                as target_endpoint,
       c.source_endpoint_refs                               as contact_endpoints,
       a.path_id,
       a.transport_binding_id,
       case
         when a.source_endpoint_ref = any(c.source_endpoint_refs)
              and position(replace(a.source_endpoint_ref, 'spacecraft_runtime:', '') in coalesce(a.path_id, '')) > 0
           then 'ok'
         when a.source_endpoint_ref = any(c.source_endpoint_refs) then 'route?'
         else 'WRONG SPACECRAFT'
       end                                                  as verdict
from command_release_attempts a
left join command_requests r on r.command_request_id = a.command_request_id
left join realized_contacts c on c.realized_contact_id = a.realized_contact_id
order by a.attempted_at;
```

## Raw output

```
        attempted_at        |                 attempt                  |              grp               | command_name | attempt_state | verification_state |              target_endpoint               |              contact_endpoints               |                   path_id                   |                       transport_binding_id                       |     verdict      
----------------------------+------------------------------------------+--------------------------------+--------------+---------------+--------------------+--------------------------------------------+----------------------------------------------+---------------------------------------------+------------------------------------------------------------------+------------------
 2026-11-09 12:17:24.042019 | command_release_attempt_bp7lvyewsq_1X7CP | command_group_bp7lvyewsq_I2DO  | NOOP         | released      | not_required       | spacecraft_runtime:spacecraft-earendil-001 | {spacecraft_runtime:spacecraft-earendil-009} | route-spacecraft-earendil-009-uplink:uplink | uplink-gateway:route-spacecraft-earendil-009-uplink:2c3d814fab47 | WRONG SPACECRAFT
 2026-11-09 18:26:36.801249 | command_release_attempt_s4fczoe6f4_3ZPX9 | command_group_bp7lvyewsq_3MKNW | SET_MODE     | released      | not_required       | spacecraft_runtime:spacecraft-earendil-004 | {spacecraft_runtime:spacecraft-earendil-004} | route-spacecraft-earendil-004-uplink:uplink | uplink-gateway:route-spacecraft-earendil-004-uplink:6276a3dac229 | ok
 2026-11-10 02:22:10.051914 | command_release_attempt_nzltu33tti_H4VV  | command_group_brs6fn2wcu_4FSOI | NOOP         | released      | timed_out          | spacecraft_runtime:spacecraft-earendil-004 | {spacecraft_runtime:spacecraft-earendil-007} | route-spacecraft-earendil-007-uplink:uplink | uplink-gateway:route-spacecraft-earendil-007-uplink:198a37caa876 | WRONG SPACECRAFT
 2026-11-10 02:22:10.251065 | command_release_attempt_nzltu33tti_H6EF  | command_group_brs6fn2wcu_4FSOI | SET_MODE     | released      | satisfied          | spacecraft_runtime:spacecraft-earendil-004 | {spacecraft_runtime:spacecraft-earendil-007} | route-spacecraft-earendil-007-uplink:uplink | uplink-gateway:route-spacecraft-earendil-007-uplink:198a37caa876 | WRONG SPACECRAFT
 2026-11-10 02:22:10.385481 | command_release_attempt_nzltu33tti_H6OO  | command_group_brs6fn2wcu_4FSOI | NOOP         | released      | satisfied          | spacecraft_runtime:spacecraft-earendil-004 | {spacecraft_runtime:spacecraft-earendil-007} | route-spacecraft-earendil-007-uplink:uplink | uplink-gateway:route-spacecraft-earendil-007-uplink:198a37caa876 | WRONG SPACECRAFT
(5 rows)

```

## Correction: 4FSOI's verifications withdrawn (DECISIONS #66)

Run by domain on 2026-11-10 06:26Z against `cadence_apogee_dev`, reviewed by api-ops, as
directed. 4FSOI's "satisfied" verifiers matched **transport records from 007's uplink** (007's
COP-1 acknowledgments), not telemetry. They show that 007 accepted the frames, not that 004 did
anything. History is kept, not deleted:

| Row | Before | After |
| --- | --- | --- |
| verifiers H55V (start, 4FSOJ), H6FA/H6F9 (start/completion, 4FSOK), H6PJ/H6PI (start/completion, 4FSOL) | satisfied | failed, `failure_reason` `verified_on_wrong_spacecraft`; `matched_record_id` kept; `metadata.correction` holds the previous state |
| attempts H6EF (SET_MODE), H6OO (NOOP) | verification satisfied | failed; `metadata.verification_correction` |
| requests 4FSOK (SET_MODE), 4FSOL (NOOP) | verification satisfied | failed; `metadata.verification_correction` |
| group 4FSOI timeline | — | system `note` `command_group_event_note_38_correction_4FSOI` explaining why |

- 4FSOJ (NOOP) stays `timed_out`. I2DO's attempt was `not_required`, so there was nothing to
  correct.
- The model has no `unknown` verification state (verifier lifecycle: pending, satisfied, failed,
  timed_out, canceled), so `failed` is the representable withdrawal.
- The SQL bypassed the settle hooks, so the group's `completed` event stays as written
  (`verified: 2`), and the note explains it.
- The group read now shows `verify_failed` for 4FSOK and 4FSOL.
- **Expected side effect:** Now's action queue lists 4FSOK and 4FSOL as P1 `command_failed`
  (occurred around 02:22Z on 11-10) until the 24 h failure lookback passes. These aren't new
  failures.

Output:

```
UPDATE 5   (verifier instances)
UPDATE 2   (release attempts)
UPDATE 2   (command requests)
INSERT 0 1 (group note)
COMMIT
```

Script (idempotent; `-v finish=ROLLBACK` for a dry run):

```sql
-- qa #38 / DECISIONS #66 one-off correction on cadence_apogee_dev.
-- 4FSOI (target EARENDIL-004) released on EARENDIL-007's contact and uplink route. Its
-- "satisfied" verifiers matched 007's transport records (007's COP-1 acknowledgments), so they
-- don't show that 004 did anything. Withdraw those verifications without deleting history:
--   * verifier instances: satisfied -> failed, failure_reason verified_on_wrong_spacecraft,
--     matched_record_* kept, previous state recorded in metadata;
--   * requests/attempts verified by them: verification_state satisfied -> failed, previous state
--     recorded in metadata;
--   * a system `note` on the group timeline saying why.
-- The model has no "unknown" verification state (verifier lifecycle: pending | satisfied |
-- failed | timed_out | canceled), so `failed` is the representable withdrawal.
-- I2DO's attempt was verification not_required: nothing to correct.
-- Run: psql -d cadence_apogee_dev -v ON_ERROR_STOP=1 -v finish=ROLLBACK -f correct-38-4fsoi.sql
--      (finish=COMMIT for the real run). Re-running is a no-op (guards on current state).

begin;

create temp table c38_attempts on commit drop as
select unnest(array[
  'command_release_attempt_nzltu33tti_H4VV',
  'command_release_attempt_nzltu33tti_H6EF',
  'command_release_attempt_nzltu33tti_H6OO'
]) as attempt_id;

\echo '== before'
select v.command_verifier_instance_id, v.command_release_attempt_id, v.phase, v.lifecycle_state,
       v.matched_record_kind, v.matched_record_id
from command_verifier_instances v
where v.command_release_attempt_id in (select attempt_id from c38_attempts)
order by 2, 3;

with correction as (
  select jsonb_build_object(
    'reason', 'verified_on_wrong_spacecraft',
    'previous_lifecycle_state', 'satisfied',
    'decision', 'DECISIONS #66',
    'report', 'qa #38',
    'corrected_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ) as doc
)
update command_verifier_instances v
set lifecycle_state = 'failed',
    failure_reason = 'verified_on_wrong_spacecraft',
    metadata_document = jsonb_set(
      coalesce(v.metadata_document, '{"value": {}}'::jsonb),
      '{value,correction}', (select doc from correction), true),
    updated_at = now() at time zone 'utc'
where v.command_release_attempt_id in (select attempt_id from c38_attempts)
  and v.lifecycle_state = 'satisfied'
returning v.command_verifier_instance_id, v.phase, v.lifecycle_state, v.failure_reason;

with correction as (
  select jsonb_build_object(
    'reason', 'verified_on_wrong_spacecraft',
    'previous_verification_state', 'satisfied',
    'decision', 'DECISIONS #66',
    'report', 'qa #38',
    'corrected_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ) as doc
)
update command_release_attempts a
set verification_state = 'failed',
    metadata_document = jsonb_set(
      coalesce(a.metadata_document, '{"value": {}}'::jsonb),
      '{value,verification_correction}', (select doc from correction), true),
    updated_at = now() at time zone 'utc'
where a.command_release_attempt_id in (select attempt_id from c38_attempts)
  and a.verification_state = 'satisfied'
returning a.command_release_attempt_id, a.verification_state;

with correction as (
  select jsonb_build_object(
    'reason', 'verified_on_wrong_spacecraft',
    'previous_verification_state', 'satisfied',
    'decision', 'DECISIONS #66',
    'report', 'qa #38',
    'corrected_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ) as doc
)
update command_requests r
set verification_state = 'failed',
    metadata_document = jsonb_set(
      coalesce(r.metadata_document, '{"value": {}}'::jsonb),
      '{value,verification_correction}', (select doc from correction), true),
    updated_at = now() at time zone 'utc'
where r.command_request_id in (
        select a.command_request_id from command_release_attempts a
        where a.command_release_attempt_id in (select attempt_id from c38_attempts))
  and r.verification_state = 'satisfied'
returning r.command_request_id, r.command_name, r.verification_state;

insert into command_group_events (event_id, command_group_id, mission_id, kind, actor_document, at, payload_document)
select 'command_group_event_note_38_correction_4FSOI', g.command_group_id, g.mission_id, 'note',
       '{"value": {"actor_kind": "system", "reason": "qa #38 correction"}}'::jsonb,
       now() at time zone 'utc',
       jsonb_build_object('value', jsonb_build_object('note',
         'Correction (qa #38, DECISIONS #66): this group was released on EARENDIL-007''s pass and ' ||
         'uplink route, not EARENDIL-004''s. The SET_MODE and NOOP that read "verified" were ' ||
         'acknowledged by 007, not 004, so their verification is withdrawn (failed: ' ||
         'verified_on_wrong_spacecraft). Nothing in this group is known to have reached 004.'))
from command_groups g
where g.command_group_id = 'command_group_brs6fn2wcu_4FSOI'
on conflict (event_id) do nothing
returning event_id, kind, at;

\echo '== after'
select v.command_verifier_instance_id, v.command_release_attempt_id, v.phase, v.lifecycle_state,
       v.failure_reason, v.matched_record_id
from command_verifier_instances v
where v.command_release_attempt_id in (select attempt_id from c38_attempts)
order by 2, 3;

select r.command_request_id, r.command_name, r.lifecycle_state, r.verification_state
from command_requests r where r.command_group_id = 'command_group_brs6fn2wcu_4FSOI' order by 1;

:finish;
```

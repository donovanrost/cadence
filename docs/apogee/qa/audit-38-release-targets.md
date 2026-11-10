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

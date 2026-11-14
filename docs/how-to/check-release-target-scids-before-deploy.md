---
title: Check Release Target SCIDs Before Deploying the #38 Guard
tags: [how-to, operations, commanding, deploy]
status: active
created: 2026-11-14
updated: 2026-11-14
---

# Check Release Target SCIDs Before Deploying the #38 Guard

**Release note.** From this release a command goes out only over its own spacecraft's contact,
uplink path and gateway (SAFETY #38, DECISIONS #66). The gateway binding's `scid` must equal the
target spacecraft's SCID, and a spacecraft or gateway with no SCID is refused. **Before you
deploy, run the check below against the environment's database and fix every row it returns.**

What a gap does after the deploy:

- **Queued commands wait.** The lane only picks passes that pass the guard. A command whose
  spacecraft or gateway has no SCID, or a mismatched one, stays queued with no release target. It
  is not canceled. It releases once the configuration is fixed and a usable pass is active.
- **An operator naming the contact gets a refusal, and the command is canceled.** Releasing an
  entry on a named contact (`release_command_queue_entry`, the REST release) checks the guard before
  anything is sent. A refusal fails the attempt (`release_failed`, "refused: …") and cancels the
  request and its queue entry, as on develop. Nothing is transmitted.

## The check (read-only)

```
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f check.sql
```

Every query must return zero rows. A SCID is valid when it's an integer or a whole-number string.

```sql
set default_transaction_read_only = on;

-- 1. Spacecraft with no SCID (release_target_scid_unknown). Every one of their commands is refused.
select organization_id, mission_id, spacecraft_id, display_name
from mission_spacecraft
where scid is null
order by organization_id, mission_id, spacecraft_id;

-- 2. Uplink gateway transport profiles with no valid SCID (uplink_gateway_scid_unknown) once realized.
select organization_id, mission_id, transport_profile_id, version, lifecycle_state,
       coalesce(configuration -> 'value', configuration) -> 'scid' as scid
from contact_transport_profiles
-- the column holds JsonDocument.wrap_value(configuration): {"value": {...}}
where family_key = 'uplink_gateway'
  and coalesce(coalesce(configuration -> 'value', configuration) ->> 'scid', '') !~ '^-?[0-9]+$'
order by organization_id, mission_id, transport_profile_id, version;

-- 3. Defined or active contacts whose uplink gateway binding snapshot has no valid SCID.
--    The release reads these snapshots, not the profiles: fix the profile and re-realize.
select rc.organization_id, rc.mission_id, rc.realized_contact_id, rc.lifecycle_state,
       p ->> 'path_id' as path_id, b ->> 'transport_binding_id' as transport_binding_id,
       b -> 'configuration' -> 'scid' as scid
from realized_contacts rc
cross join lateral jsonb_array_elements(coalesce(rc.path_documents -> 'items', '[]'::jsonb)) p
cross join lateral jsonb_array_elements(coalesce(p -> 'transport_bindings', '[]'::jsonb)) b
where rc.lifecycle_state in ('defined', 'active')
  and b ->> 'family_key' = 'uplink_gateway'
  and coalesce(b -> 'configuration' ->> 'scid', '') !~ '^-?[0-9]+$'
order by rc.organization_id, rc.mission_id, rc.realized_contact_id;

-- 4. Defined or active contacts whose gateway SCID is valid but isn't the SCID of the spacecraft
--    the contact serves (release_gateway_not_target_spacecraft).
select rc.organization_id, rc.mission_id, rc.realized_contact_id,
       b ->> 'transport_binding_id' as transport_binding_id,
       (b -> 'configuration' ->> 'scid')::bigint as gateway_scid,
       sc.spacecraft_id, sc.scid as spacecraft_scid
from realized_contacts rc
cross join lateral jsonb_array_elements(coalesce(rc.path_documents -> 'items', '[]'::jsonb)) p
cross join lateral jsonb_array_elements(coalesce(p -> 'transport_bindings', '[]'::jsonb)) b
cross join lateral unnest(rc.source_endpoint_refs) as ref(source_endpoint_id)
join mission_source_endpoints se
  on se.mission_id = rc.mission_id and se.source_endpoint_id = ref.source_endpoint_id
join mission_spacecraft sc
  on sc.mission_id = se.mission_id and sc.spacecraft_id = se.spacecraft_id
where rc.lifecycle_state in ('defined', 'active')
  and b ->> 'family_key' = 'uplink_gateway'
  and coalesce(b -> 'configuration' ->> 'scid', '') ~ '^-?[0-9]+$'
  and sc.scid is distinct from (b -> 'configuration' ->> 'scid')::bigint
order by rc.organization_id, rc.mission_id, rc.realized_contact_id;
```

## Fixing what it finds

1. **Spacecraft with no SCID:** set the spacecraft's SCID.
2. **Gateway profile with no SCID:** add `scid` to the uplink gateway profile's configuration.
3. and 4. **Open contacts:** a realized contact keeps the bindings it was realized with. Fix the
   profile (2), then end the contact and re-realize it, or let it end and the next pass realizes
   with the fixed binding.

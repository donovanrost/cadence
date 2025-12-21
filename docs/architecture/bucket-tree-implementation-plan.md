# Plan: Hierarchical Buckets for Access Control and Fast Queries

## Goal

Refactor buckets to be a tree structure that unifies:
- Access control inheritance (org → mission → target group → target)
- Settings inheritance
- Fast subtree queries for timeline (all recordings under mission X or target group Y)

## Decisions

- **Target groups:** Migrate into bucket system (DELETE target_groups tables and schemas)
- **Path format:** String materialized path (e.g., `"org_1.mission_2.tg_3.target_4"`)
- **Shifts/Anomalies:** Time-based queries, not part of the tree hierarchy

## Context

**This is a greenfield project with no users.** We can:
- Modify existing migrations directly
- Drop and recreate the database freely
- Delete obsolete migrations entirely

## Architecture

```
buckets (tree)
├── id
├── parent_id        ← tree structure
├── path             ← materialized path for fast subtree queries
├── bucket_type      ← "organization", "mission", "target_group", "target"
├── bucketable_type  ← polymorphic reference to the entity
├── bucketable_id
└── ...existing fields...

recordings
├── bucket_id        ← points to target's bucket
├── organization_id  ← KEEP for tenant isolation
└── REMOVE: mission_id, target_id (derived from bucket path)
```

**Example Tree:**
```
Organization "Acme Space" (bucket, path: "org_abc123")
└── Mission "Artemis" (bucket, path: "org_abc123.miss_def456")
    ├── Target Group "Constellation A" (bucket, path: "org_abc123.miss_def456.tg_ghi789")
    │   ├── Target "Sat-1" (bucket, path: "org_abc123.miss_def456.tg_ghi789.tgt_jkl012")
    │   └── Target "Sat-2" (bucket, path: "org_abc123.miss_def456.tg_ghi789.tgt_mno345")
    └── Target "Ground-1" (bucket, path: "org_abc123.miss_def456.tgt_pqr678")
```

**Query Pattern:**
```sql
-- All recordings for mission (and all targets under it)
SELECT * FROM recordings r
JOIN buckets b ON r.bucket_id = b.id
WHERE b.path LIKE 'org_abc123.miss_def456.%'
```

---

## Implementation Phases

### Phase 1: Modify Existing Migrations

**Edit `priv/repo/migrations/20251220205344_create_recordings_infrastructure.exs`:**

1. Add tree structure to `buckets` table:
```elixir
# In buckets table creation, add:
add :parent_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)
add :path, :string  # e.g., "org_abc.miss_def.tgt_ghi"

# Add indexes:
create index(:buckets, [:path])
create index(:buckets, [:parent_id])
```

2. Remove from `recordings` table:
```elixir
# REMOVE these lines:
add :mission_id, references(:missions, ...)  # derive from bucket path
add :target_id, references(:targets, ...)    # derive from bucket_id

# REMOVE these indexes:
create index(:recordings, [:mission_id, :timestamp])
create index(:recordings, [:target_id, :timestamp])
```

3. Remove `target_id` from recordables:
   - `command_dispatcheds` - remove `add :target_id, :binary_id`
   - `alarm_triggereds` - remove `add :target_id, :binary_id`
   - `procedure_starteds` - remove `add :target_id, :binary_id`
   - `command_queueds` - remove `add :target_id, :binary_id`

4. Remove `target_group_ids` from `bucket_memberships`:
```elixir
# REMOVE this line:
add :target_group_ids, {:array, :binary_id}, default: []
```

5. At the end, add bucket_id to targets:
```elixir
# Add bucket_id to targets (buckets must exist first)
alter table(:targets) do
  add :bucket_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)
end
create index(:targets, [:bucket_id])
```

**DELETE these migrations entirely:**
- `priv/repo/migrations/20251115205053_create_target_groups.exs`

---

### Phase 2: Update Schemas

**`lib/cadence/buckets/bucket.ex`:**
- Add `parent_id`, `path` fields
- Add `belongs_to :parent, Bucket`
- Add `has_many :children, Bucket, foreign_key: :parent_id`
- Update `@bucket_types` to include "target" (already has "target_group")

**`lib/cadence/buckets/bucket_membership.ex`:**
- Remove `target_group_ids` field (Line 52)
- Remove from `@optional_fields` (Line 64)

**`lib/cadence/targets/target.ex`:**
- Add `belongs_to :bucket, Bucket`
- Remove `many_to_many :target_groups` (Lines 59-60)

**`lib/cadence/missions/mission.ex`:**
- Remove `has_many :target_groups` (Line 54)

**`lib/cadence/recordings/recording.ex`:**
- Remove `mission_id`, `target_id` fields (Lines 56, 67)
- Remove `belongs_to :mission`, `belongs_to :target` (Lines 82-86)
- Update changeset required/optional fields

**Recordable schemas - Remove target_id:**
- `lib/cadence/recordings/recordables/command_dispatched.ex` (Lines 20, 27)
- `lib/cadence/recordings/recordables/alarm_triggered.ex` (Lines 20, 30)
- `lib/cadence/recordings/recordables/procedure_started.ex` (Lines 18, 27)
- `lib/cadence/recordings/recordables/command_queued.ex` (Lines 15, 25)

**DELETE these schema files:**
- `lib/cadence/targets/target_group.ex`
- `lib/cadence/targets/target_group_membership.ex`

---

### Phase 3: Update Contexts

**`lib/cadence/buckets.ex`:**
- Add tree functions:
  - `build_path/1` - Generates path from parent chain
  - `get_ancestors/1` - Returns all ancestors up to root
  - `get_descendants/1` - Returns all children recursively
  - `in_subtree?/2` - Checks if bucket is under another
- Update `create_bucket/1` to auto-generate path
- Replace `target_in_groups?/2` (Lines 305-309) with bucket hierarchy check
- Update `can_command_target?/3` (Lines 273-289) to use bucket ancestry

**`lib/cadence/targets.ex`:**
- DELETE all target_group functions (Lines 268-386):
  - `list_target_groups/1`
  - `get_target_group!/1`
  - `get_target_group_by_slug/2`
  - `create_target_group/1`
  - `update_target_group/2`
  - `delete_target_group/1`
  - `change_target_group/2`
  - `add_target_to_group/2`
  - `remove_target_from_group/2`
  - `get_group_targets/2`
- Add new bucket-based functions:
  - `list_target_buckets/1` - List target groups as buckets
  - `create_target_bucket/2` - Create target group bucket
  - `move_target_to_bucket/2` - Move target between groups

**`lib/cadence/recordings.ex`:**
- Update `list_recordings/4` (Lines 191-211) - Filter by bucket path prefix
- Update `list_recordings_before/3` (Lines 227-265) - Filter by path prefix
- Update `list_aggregate_recordings/3` (Lines 422-448) - Use bucket_id
- Replace `mission_id` param with `path_prefix` option
- Remove `target_id` filtering (derive from bucket)

**`lib/cadence/timeline.ex`:**
- Update `list_events/4` (Lines 63-102) - Accept path_prefix instead of mission_id
- Update `list_events_before/3` (Lines 223-252) - Use path_prefix
- Update `list_scheduled_commands/5` (Lines 181-208) - Filter by bucket subtree
- Remove `target_ids` option (use bucket descendants)

**`lib/cadence/commands.ex`:**
- Update `list_command_history/2` (Lines 475-481)
- Update `get_target_command_history/3` (Lines 486-490)

**`lib/cadence/interfaces.ex`:**
- Remove `target_groups` preload (Line 408)

---

### Phase 4: Update Recording Creation Sites

**`lib/cadence/commands/target_dispatcher.ex`:**
- Line 847: Remove `target_id` from CommandDispatched recordable
- Lines 852-860: Replace `mission_id`, `target_id` with `bucket_id: target.bucket_id`
- Lines 876-885: Update CommandSent recording_attrs
- Lines 901-910: Update CommandVerified recording_attrs
- Lines 924-933: Update CommandVerificationFailed recording_attrs

**`lib/cadence/commands/target_queue.ex`:**
- Lines 475-486: Remove target_id from CommandQueued, use bucket_id
- Line 826: Update CommandDequeued recording

**`lib/cadence/alarms.ex`:**
- Update all alarm recordable creation to use bucket_id instead of mission_id/target_id

**`lib/cadence/procedures.ex`:**
- Lines 763-785: Remove target_id from ProcedureStarted, use bucket_id

---

### Phase 5: Update LiveView and UI

**`lib/cadence_web/live/ops_console_v2_live/index.ex`:**
- Line 88: Replace `Targets.list_target_groups(mission)` with bucket query
- Line 123: Update `target_groups` assignment
- Line 165: Update `data-target-groups` encoding
- Lines 1580, 1623, 1674, 1715: Update event target_group handling
- Line 1820: Update or remove `target_group_json/1` helper

**`lib/cadence/timeline/event.ex`:**
- Line 22, 41: Consider if `target_group` field still needed (may derive from bucket)

---

### Phase 6: Update Test Fixtures

**`test/support/fixtures/targets_fixtures.ex`:**
- Lines 105-123: Delete `target_group_fixture/1` or replace with bucket fixture
- Add `target_bucket_fixture/1` for creating target group buckets

**`test/cadence/targets_test.exs`:**
- Update/remove target_group tests
- Add bucket hierarchy tests

---

### Phase 7: Run Database Reset and Verify

```bash
mix ecto.reset  # Drop, create, migrate
mix compile --warnings-as-errors
mix test
```

---

## Complete File Inventory

### Migrations

| Action | File |
|--------|------|
| EDIT | `priv/repo/migrations/20251220205344_create_recordings_infrastructure.exs` |
| DELETE | `priv/repo/migrations/20251115205053_create_target_groups.exs` |

### Schemas

| Action | File | Changes |
|--------|------|---------|
| UPDATE | `lib/cadence/buckets/bucket.ex` | Add parent_id, path, associations |
| UPDATE | `lib/cadence/buckets/bucket_membership.ex` | Remove target_group_ids |
| UPDATE | `lib/cadence/targets/target.ex` | Add bucket_id, remove target_groups |
| UPDATE | `lib/cadence/missions/mission.ex` | Remove target_groups association |
| UPDATE | `lib/cadence/recordings/recording.ex` | Remove mission_id, target_id |
| UPDATE | `lib/cadence/recordings/recordables/command_dispatched.ex` | Remove target_id |
| UPDATE | `lib/cadence/recordings/recordables/alarm_triggered.ex` | Remove target_id |
| UPDATE | `lib/cadence/recordings/recordables/procedure_started.ex` | Remove target_id |
| UPDATE | `lib/cadence/recordings/recordables/command_queued.ex` | Remove target_id |
| DELETE | `lib/cadence/targets/target_group.ex` | - |
| DELETE | `lib/cadence/targets/target_group_membership.ex` | - |

### Contexts

| Action | File | Changes |
|--------|------|---------|
| UPDATE | `lib/cadence/buckets.ex` | Add tree functions, update access control |
| UPDATE | `lib/cadence/targets.ex` | Remove target_group functions, add bucket functions |
| UPDATE | `lib/cadence/recordings.ex` | Update queries for bucket path |
| UPDATE | `lib/cadence/timeline.ex` | Update filtering for bucket path |
| UPDATE | `lib/cadence/commands.ex` | Update history queries |
| UPDATE | `lib/cadence/commands/target_dispatcher.ex` | Use bucket_id in recordings |
| UPDATE | `lib/cadence/commands/target_queue.ex` | Use bucket_id in recordings |
| UPDATE | `lib/cadence/alarms.ex` | Use bucket_id in recordings |
| UPDATE | `lib/cadence/procedures.ex` | Use bucket_id in recordings |
| UPDATE | `lib/cadence/interfaces.ex` | Remove target_groups preload |

### LiveViews

| Action | File | Changes |
|--------|------|---------|
| UPDATE | `lib/cadence_web/live/ops_console_v2_live/index.ex` | Replace target_groups with buckets |
| UPDATE | `lib/cadence/timeline/event.ex` | Update target_group field |

### Tests

| Action | File | Changes |
|--------|------|---------|
| UPDATE | `test/support/fixtures/targets_fixtures.ex` | Replace target_group_fixture |
| UPDATE | `test/cadence/targets_test.exs` | Update for bucket hierarchy |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Query performance with LIKE | Add GIN trigram index if needed |
| Test fixtures need buckets | Update test factories first |
| Many files to change | Work phase by phase, compile frequently |
| Access control regression | Write tests for `can_command_target?` before changing |

**Greenfield advantage:** No data migration complexity, no backwards compatibility concerns.

## Testing Strategy

1. Add unit tests for bucket tree functions (build_path, ancestors, descendants)
2. Write access control tests before refactoring `can_command_target?`
3. Add integration tests for recording queries with bucket path filtering
4. Run `mix ecto.reset && mix test` after each phase
5. Run `mix compile --warnings-as-errors` to catch unused code

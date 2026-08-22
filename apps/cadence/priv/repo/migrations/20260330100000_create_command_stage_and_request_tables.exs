defmodule Cadence.Repo.Migrations.CreateCommandStageAndRequestTables do
  use Ecto.Migration

  def up do
    create table(:command_stages, primary_key: false) do
      add(:command_stage_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:stage_name, :string, null: false)
      add(:description, :string)
      add(:owner_document, :map, null: false, default: %{})
      add(:visibility, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:command_stages, [:mission_id, :command_stage_id],
        name: :command_stages_scope_idx
      )
    )

    create(
      unique_index(:command_stages, [:organization_id, :mission_id, :command_stage_id],
        name: :command_stages_org_scope_idx
      )
    )

    create(index(:command_stages, [:organization_id, :mission_id, :inserted_at]))

    create table(:staged_command_items, primary_key: false) do
      add(:staged_command_item_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:command_stage_id, :string, null: false)
      add(:source_endpoint_ref, :string, null: false)
      add(:command_snapshot_id, :string, null: false)
      add(:command_id, :string, null: false)
      add(:argument_values_document, :map, null: false, default: %{})
      add(:priority, :integer, null: false, default: 3)
      add(:not_before, :utc_datetime_usec)
      add(:expires_at, :utc_datetime_usec)
      add(:notes, :string)
      add(:item_order, :integer, null: false, default: 0)
      add(:lifecycle_state, :string, null: false)
      add(:submitted_command_request_id, :string)
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:staged_command_items, [:mission_id, :staged_command_item_id],
        name: :staged_command_items_scope_idx
      )
    )

    create(
      unique_index(:staged_command_items, [:organization_id, :mission_id, :staged_command_item_id],
        name: :staged_command_items_org_scope_idx
      )
    )

    create(index(:staged_command_items, [:organization_id, :mission_id, :command_stage_id, :item_order]))
    create(index(:staged_command_items, [:organization_id, :mission_id, :source_endpoint_ref]))
    create(index(:staged_command_items, [:organization_id, :mission_id, :command_snapshot_id]))

    create table(:command_requests, primary_key: false) do
      add(:command_request_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:source_endpoint_ref, :string, null: false)
      add(:command_snapshot_id, :string, null: false)
      add(:command_id, :string, null: false)
      add(:command_name, :string, null: false)
      add(:command_display_name, :string)
      add(:lifecycle_state, :string, null: false)
      add(:priority, :integer, null: false, default: 3)
      add(:not_before, :utc_datetime_usec)
      add(:expires_at, :utc_datetime_usec)
      add(:requested_by_document, :map, null: false, default: %{})
      add(:source_command_stage_id, :string)
      add(:source_staged_command_item_id, :string)
      add(:argument_values_document, :map, null: false, default: %{})
      add(:resolved_argument_values_document, :map, null: false, default: %{})
      add(:significance, :string)
      add(:critical, :boolean, null: false, default: false)
      add(:hazardous, :boolean, null: false, default: false)
      add(:subsystem, :string)
      add(:group_name, :string)
      add(:preferred_uplink_service, :string)
      add(:release_policy_hint, :string)
      add(:apid, :integer)
      add(:service_type, :integer)
      add(:service_subtype, :integer)
      add(:opcode_document, :map, null: false, default: %{})
      add(:requested_at, :utc_datetime_usec, null: false)
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:command_requests, [:mission_id, :command_request_id],
        name: :command_requests_scope_idx
      )
    )

    create(
      unique_index(:command_requests, [:organization_id, :mission_id, :command_request_id],
        name: :command_requests_org_scope_idx
      )
    )

    create(index(:command_requests, [:organization_id, :mission_id, :requested_at]))
    create(index(:command_requests, [:organization_id, :mission_id, :source_endpoint_ref]))
    create(index(:command_requests, [:organization_id, :mission_id, :source_command_stage_id]))

    execute("""
    ALTER TABLE command_stages
    ADD CONSTRAINT command_stages_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE staged_command_items
    ADD CONSTRAINT staged_command_items_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE command_requests
    ADD CONSTRAINT command_requests_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON command_stages
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON staged_command_items
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON command_requests
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    ALTER TABLE command_stages
    ADD CONSTRAINT command_stages_scope_idx_uniq
    UNIQUE USING INDEX command_stages_scope_idx
    """)

    execute("""
    ALTER TABLE command_stages
    ADD CONSTRAINT command_stages_org_scope_idx_uniq
    UNIQUE USING INDEX command_stages_org_scope_idx
    """)

    execute("""
    ALTER TABLE staged_command_items
    ADD CONSTRAINT staged_command_items_scope_idx_uniq
    UNIQUE USING INDEX staged_command_items_scope_idx
    """)

    execute("""
    ALTER TABLE staged_command_items
    ADD CONSTRAINT staged_command_items_org_scope_idx_uniq
    UNIQUE USING INDEX staged_command_items_org_scope_idx
    """)

    execute("""
    ALTER TABLE command_requests
    ADD CONSTRAINT command_requests_scope_idx_uniq
    UNIQUE USING INDEX command_requests_scope_idx
    """)

    execute("""
    ALTER TABLE command_requests
    ADD CONSTRAINT command_requests_org_scope_idx_uniq
    UNIQUE USING INDEX command_requests_org_scope_idx
    """)

    execute("""
    ALTER TABLE staged_command_items
    ADD CONSTRAINT staged_command_items_stage_fk
    FOREIGN KEY (organization_id, mission_id, command_stage_id)
    REFERENCES command_stages (organization_id, mission_id, command_stage_id)
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON command_requests
    """)

    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON staged_command_items
    """)

    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON command_stages
    """)

    execute("""
    ALTER TABLE staged_command_items
    DROP CONSTRAINT IF EXISTS staged_command_items_stage_fk
    """)

    execute("""
    ALTER TABLE command_requests
    DROP CONSTRAINT IF EXISTS command_requests_org_mission_fk
    """)

    execute("""
    ALTER TABLE staged_command_items
    DROP CONSTRAINT IF EXISTS staged_command_items_org_mission_fk
    """)

    execute("""
    ALTER TABLE command_stages
    DROP CONSTRAINT IF EXISTS command_stages_org_mission_fk
    """)

    execute("""
    ALTER TABLE command_requests
    DROP CONSTRAINT IF EXISTS command_requests_org_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE command_requests
    DROP CONSTRAINT IF EXISTS command_requests_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE staged_command_items
    DROP CONSTRAINT IF EXISTS staged_command_items_org_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE staged_command_items
    DROP CONSTRAINT IF EXISTS staged_command_items_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE command_stages
    DROP CONSTRAINT IF EXISTS command_stages_org_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE command_stages
    DROP CONSTRAINT IF EXISTS command_stages_scope_idx_uniq
    """)

    drop_if_exists(index(:command_requests, [:organization_id, :mission_id, :source_command_stage_id]))
    drop_if_exists(index(:command_requests, [:organization_id, :mission_id, :source_endpoint_ref]))
    drop_if_exists(index(:command_requests, [:organization_id, :mission_id, :requested_at]))

    drop_if_exists(
      index(:command_requests, [:organization_id, :mission_id, :command_request_id],
        name: :command_requests_org_scope_idx
      )
    )

    drop_if_exists(
      index(:command_requests, [:mission_id, :command_request_id],
        name: :command_requests_scope_idx
      )
    )

    drop(table(:command_requests))

    drop_if_exists(index(:staged_command_items, [:organization_id, :mission_id, :command_snapshot_id]))
    drop_if_exists(index(:staged_command_items, [:organization_id, :mission_id, :source_endpoint_ref]))
    drop_if_exists(index(:staged_command_items, [:organization_id, :mission_id, :command_stage_id, :item_order]))

    drop_if_exists(
      index(:staged_command_items, [:organization_id, :mission_id, :staged_command_item_id],
        name: :staged_command_items_org_scope_idx
      )
    )

    drop_if_exists(
      index(:staged_command_items, [:mission_id, :staged_command_item_id],
        name: :staged_command_items_scope_idx
      )
    )

    drop(table(:staged_command_items))

    drop_if_exists(index(:command_stages, [:organization_id, :mission_id, :inserted_at]))

    drop_if_exists(
      index(:command_stages, [:organization_id, :mission_id, :command_stage_id],
        name: :command_stages_org_scope_idx
      )
    )

    drop_if_exists(
      index(:command_stages, [:mission_id, :command_stage_id], name: :command_stages_scope_idx)
    )

    drop(table(:command_stages))
  end
end

defmodule Cadence.Repo.Migrations.CreateCommandApprovalAndQueueTables do
  use Ecto.Migration

  def up do
    create table(:command_approvals, primary_key: false) do
      add(:command_approval_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:command_request_id, :string, null: false)
      add(:decision, :string, null: false)
      add(:decided_by_document, :map, null: false, default: %{})
      add(:decided_at, :utc_datetime_usec, null: false)
      add(:reason, :string)
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:command_approvals, [:mission_id, :command_approval_id],
        name: :command_approvals_scope_idx
      )
    )

    create(
      unique_index(:command_approvals, [:organization_id, :mission_id, :command_approval_id],
        name: :command_approvals_org_scope_idx
      )
    )

    create(index(:command_approvals, [:organization_id, :mission_id, :command_request_id, :decided_at]))

    create table(:command_queue_entries, primary_key: false) do
      add(:command_queue_entry_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:command_request_id, :string, null: false)
      add(:source_endpoint_ref, :string, null: false)
      add(:queue_lane_key, :string, null: false)
      add(:priority, :integer, null: false, default: 3)
      add(:queue_sequence, :bigint, null: false)
      add(:not_before, :utc_datetime_usec)
      add(:expires_at, :utc_datetime_usec)
      add(:lifecycle_state, :string, null: false)
      add(:enqueued_by_document, :map, null: false, default: %{})
      add(:enqueued_at, :utc_datetime_usec, null: false)
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:command_queue_entries, [:mission_id, :command_queue_entry_id],
        name: :command_queue_entries_scope_idx
      )
    )

    create(
      unique_index(:command_queue_entries, [:organization_id, :mission_id, :command_queue_entry_id],
        name: :command_queue_entries_org_scope_idx
      )
    )

    create(
      unique_index(:command_queue_entries, [:organization_id, :mission_id, :command_request_id],
        name: :command_queue_entries_request_org_scope_idx
      )
    )

    create(index(:command_queue_entries, [:organization_id, :mission_id, :source_endpoint_ref]))

    create(
      index(
        :command_queue_entries,
        [:organization_id, :mission_id, :queue_lane_key, :lifecycle_state, :priority, :queue_sequence]
      )
    )

    execute("""
    ALTER TABLE command_approvals
    ADD CONSTRAINT command_approvals_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE command_queue_entries
    ADD CONSTRAINT command_queue_entries_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE command_approvals
    ADD CONSTRAINT command_approvals_request_fk
    FOREIGN KEY (organization_id, mission_id, command_request_id)
    REFERENCES command_requests (organization_id, mission_id, command_request_id)
    """)

    execute("""
    ALTER TABLE command_queue_entries
    ADD CONSTRAINT command_queue_entries_request_fk
    FOREIGN KEY (organization_id, mission_id, command_request_id)
    REFERENCES command_requests (organization_id, mission_id, command_request_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON command_approvals
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON command_queue_entries
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    ALTER TABLE command_approvals
    ADD CONSTRAINT command_approvals_scope_idx_uniq
    UNIQUE USING INDEX command_approvals_scope_idx
    """)

    execute("""
    ALTER TABLE command_approvals
    ADD CONSTRAINT command_approvals_org_scope_idx_uniq
    UNIQUE USING INDEX command_approvals_org_scope_idx
    """)

    execute("""
    ALTER TABLE command_queue_entries
    ADD CONSTRAINT command_queue_entries_scope_idx_uniq
    UNIQUE USING INDEX command_queue_entries_scope_idx
    """)

    execute("""
    ALTER TABLE command_queue_entries
    ADD CONSTRAINT command_queue_entries_org_scope_idx_uniq
    UNIQUE USING INDEX command_queue_entries_org_scope_idx
    """)

    execute("""
    ALTER TABLE command_queue_entries
    ADD CONSTRAINT command_queue_entries_request_org_scope_idx_uniq
    UNIQUE USING INDEX command_queue_entries_request_org_scope_idx
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON command_queue_entries
    """)

    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON command_approvals
    """)

    drop(table(:command_queue_entries))
    drop(table(:command_approvals))
  end
end

defmodule Cadence.Repo.Migrations.CreateCommandGroups do
  use Ecto.Migration

  # Group command requests (docs/apogee/domain/group-requests.md): one reviewed, approved and
  # abortable unit of N targets x K commands. Members stay ordinary command_requests.
  def up do
    create table(:command_groups, primary_key: false) do
      add(:command_group_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:state, :string, null: false)
      add(:title, :string, null: false)
      add(:log_entry, :text)
      add(:requested_by_document, :map, null: false, default: %{})
      add(:requested_at, :utc_datetime_usec, null: false)
      add(:requested_approver_user_id, :string)
      add(:operation_id, :string)
      add(:sent_back_from, :string)
      add(:target_query_document, :map, null: false, default: %{})
      add(:targets_document, :map, null: false, default: %{})
      add(:resolved_at, :utc_datetime_usec, null: false)
      add(:commands_document, :map, null: false, default: %{})
      add(:release_document, :map, null: false, default: %{})
      add(:basis_document, :map, null: false, default: %{})
      add(:policy_document, :map, null: false, default: %{})
      add(:preflight_document, :map, null: false, default: %{})
      add(:member_count, :integer, null: false)
      add(:decided_by_document, :map)
      add(:decided_at, :utc_datetime_usec)
      add(:decision_document, :map)
      add(:aborted_by_document, :map)
      add(:aborted_at, :utc_datetime_usec)
      add(:abort_reason, :text)
      add(:abort_result_document, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:command_groups, [:mission_id, :state]))

    create(
      unique_index(:command_groups, [:mission_id, :operation_id],
        where: "operation_id IS NOT NULL",
        name: :command_groups_operation_idx
      )
    )

    create table(:command_group_events, primary_key: false) do
      add(:event_id, :string, primary_key: true)

      add(
        :command_group_id,
        references(:command_groups,
          column: :command_group_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:actor_document, :map)
      add(:at, :utc_datetime_usec, null: false)
      add(:payload_document, :map, null: false, default: %{})
    end

    create(index(:command_group_events, [:command_group_id, :at]))

    alter table(:command_requests) do
      add(:command_group_id, :string)
      add(:group_target_index, :integer)
      add(:group_position, :integer)
    end

    create(
      unique_index(:command_requests, [:command_group_id, :group_target_index, :group_position],
        where: "command_group_id IS NOT NULL",
        name: :command_requests_group_member_idx
      )
    )

    for table <- [:command_groups, :command_group_events] do
      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end
  end

  def down do
    drop(index(:command_requests, [], name: :command_requests_group_member_idx))

    alter table(:command_requests) do
      remove(:command_group_id)
      remove(:group_target_index)
      remove(:group_position)
    end

    drop(table(:command_group_events))
    drop(table(:command_groups))
  end
end

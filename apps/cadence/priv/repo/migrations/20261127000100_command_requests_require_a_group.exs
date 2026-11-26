defmodule Cadence.Repo.Migrations.CommandRequestsRequireAGroup do
  use Ecto.Migration

  # #708: every command request is a command group's member (DECISIONS #61, #62), so the group
  # columns are required and the group is a real foreign key. There is no backfill: a standalone
  # request cannot be made any more, and an existing database is dropped and reseeded. The stage
  # source columns go too: only a stage's submit set them, and it is deleted (their index goes with
  # the column).
  def up do
    alter table(:command_requests) do
      remove(:source_command_stage_id)
      remove(:source_staged_command_item_id)
      modify(:command_group_id, :string, null: false)
      modify(:group_target_index, :integer, null: false)
      modify(:group_position, :integer, null: false)
    end

    execute("""
    ALTER TABLE command_requests
    ADD CONSTRAINT command_requests_command_group_fk
    FOREIGN KEY (command_group_id) REFERENCES command_groups (command_group_id)
    """)

    drop(index(:command_requests, [], name: :command_requests_group_member_idx))

    create(
      unique_index(:command_requests, [:command_group_id, :group_target_index, :group_position],
        name: :command_requests_group_member_idx
      )
    )
  end

  def down do
    drop(index(:command_requests, [], name: :command_requests_group_member_idx))

    create(
      unique_index(:command_requests, [:command_group_id, :group_target_index, :group_position],
        where: "command_group_id IS NOT NULL",
        name: :command_requests_group_member_idx
      )
    )

    execute("ALTER TABLE command_requests DROP CONSTRAINT command_requests_command_group_fk")

    alter table(:command_requests) do
      modify(:command_group_id, :string, null: true)
      modify(:group_target_index, :integer, null: true)
      modify(:group_position, :integer, null: true)
      add(:source_command_stage_id, :string)
      add(:source_staged_command_item_id, :string)
    end

    create(
      index(:command_requests, [:organization_id, :mission_id, :source_command_stage_id],
        name: :command_requests_organization_id_mission_id_source_command_stag
      )
    )
  end
end

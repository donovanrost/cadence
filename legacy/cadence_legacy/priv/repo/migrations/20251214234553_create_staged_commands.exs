defmodule Cadence.Repo.Migrations.CreateStagedCommands do
  use Ecto.Migration

  def change do
    create table(:staged_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :meta_command_id,
          references(:mdb_meta_commands, type: :binary_id, on_delete: :delete_all),
          null: false

      # Denormalized command name for display if meta_command is deleted
      add :command_name, :string, null: false

      # Queue settings
      add :priority, :integer, null: false, default: 3

      # Client-generated ID for optimistic UI deduplication
      add :client_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    # Primary lookup: all staged commands for a mission
    create index(:staged_commands, [:mission_id])

    # Multi-tenant scoping
    create index(:staged_commands, [:organization_id, :mission_id])

    # Client ID lookup for deduplication (unique per mission)
    create unique_index(:staged_commands, [:mission_id, :client_id],
             where: "client_id IS NOT NULL",
             name: "staged_commands_mission_client_id_unique"
           )
  end
end

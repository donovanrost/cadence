defmodule Cadence.Repo.Migrations.CreateStagedCommandTargets do
  use Ecto.Migration

  def change do
    create table(:staged_command_targets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :staged_command_id,
          references(:staged_commands, type: :binary_id, on_delete: :delete_all),
          null: false

      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all), null: false

      # Denormalized target name for display if target is deleted
      add :target_name, :string, null: false

      # Per-target command parameters
      add :params, :map, default: %{}

      # Position for ordering within the staged command
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Find all targets for a staged command
    create index(:staged_command_targets, [:staged_command_id])

    # Prevent duplicate target in same staged command
    create unique_index(:staged_command_targets, [:staged_command_id, :target_id])
  end
end

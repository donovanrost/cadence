defmodule Cadence.Repo.Migrations.CreateMdbCommandVerifiers do
  use Ecto.Migration

  def change do
    create table(:mdb_command_verifiers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :meta_command_id, references(:mdb_meta_commands, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string
      add :description, :text

      # Verification stage
      add :stage, :string, null: false

      # Condition that indicates this stage is reached (MatchCriteria embedded JSON)
      add :match_criteria, :map

      # Alternative: simple telemetry item to watch
      add :telemetry_item_ref, :string
      add :expected_value, :string
      add :comparison, :string

      # Timeout waiting for this stage
      add :timeout_ms, :integer

      # For :executing stage, expected progress updates
      add :progress_parameter_ref, :string

      # Actions on success/failure/timeout
      add :on_success_action, :string
      add :on_failure_action, :string
      add :on_timeout_action, :string

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_command_verifiers, [:meta_command_id])
  end
end

defmodule Cadence.Repo.Migrations.CreateMdbTransmissionConstraints do
  use Ecto.Migration

  def change do
    create table(:mdb_transmission_constraints, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :meta_command_id,
          references(:mdb_meta_commands, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string
      add :description, :text

      # Condition that must be true (MatchCriteria embedded JSON)
      add :match_criteria, :map, null: false

      # Timeout for condition to become true
      add :timeout_ms, :integer

      # Can this constraint be suspended by operator?
      add :suspendable, :boolean, default: false

      # What happens if constraint fails: block, warn
      add :on_failure, :string, default: "block"

      # Order of evaluation
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_transmission_constraints, [:meta_command_id])
  end
end

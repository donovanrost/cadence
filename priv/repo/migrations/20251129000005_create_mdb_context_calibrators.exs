defmodule Cadence.Repo.Migrations.CreateMdbContextCalibrators do
  use Ecto.Migration

  def change do
    create table(:mdb_context_calibrators, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :data_type_id, references(:mdb_data_types, type: :binary_id, on_delete: :delete_all), null: false
      add :algorithm_id, references(:mdb_algorithms, type: :binary_id, on_delete: :delete_all), null: false

      # Condition that must be true for this calibrator to apply (embedded JSON)
      # MatchCriteria structure
      add :match_criteria, :map, null: false

      # Priority (lower = higher priority)
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_context_calibrators, [:data_type_id])
    create index(:mdb_context_calibrators, [:algorithm_id])
  end
end

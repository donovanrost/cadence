defmodule Cadence.Repo.Migrations.CreateMdbParameters do
  use Ecto.Migration

  def change do
    create table(:mdb_parameters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :definition_set_id,
          references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text
      add :short_description, :string

      # Type reference
      add :data_type_id, references(:mdb_data_types, type: :binary_id, on_delete: :restrict)
      # Name reference for import resolution
      add :data_type_ref, :string

      # Parameter source: telemetry, derived, constant, local
      add :parameter_source, :string, default: "telemetry"

      # For derived parameters
      add :derivation_expression, :text
      # on_parameter_update, on_container_update, periodic
      add :derivation_trigger, :string
      add :derivation_trigger_refs, {:array, :string}, default: []

      # System-level parameters
      add :system_parameter, :boolean, default: false

      # Persistence (for stale data handling)
      add :persistence, :integer
      add :stale_timeout_ms, :integer

      # Significance: none, watch, warning, distress, critical, severe
      add :significance, :string, default: "none"

      # Recording/logging
      add :record_to_archive, :boolean, default: true
      add :record_rate_limit_hz, :float

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_parameters, [:organization_id])
    create index(:mdb_parameters, [:mission_id])
    create index(:mdb_parameters, [:definition_set_id])
    create index(:mdb_parameters, [:data_type_id])

    create unique_index(:mdb_parameters, [:definition_set_id, :name],
             name: :mdb_parameters_definition_set_name_index
           )
  end
end

defmodule Cadence.Repo.Migrations.CreatePhase7DerivedLatestValueProjection do
  use Ecto.Migration

  def change do
    create table(:derived_telemetry_latest_values) do
      add :mission_id, :string, null: false
      add :spacecraft_scope_id, :string, null: false, default: ""
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false

      add :derived_sample_id,
          references(:derived_telemetry_samples,
            column: :derived_sample_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :derived_definition_id, :string, null: false
      add :derived_definition_version, :integer, null: false
      add :trigger_sample_id, :string, null: false
      add :value, :map, null: false
      add :quality_state, :string, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :derived_telemetry_latest_values,
             [:mission_id, :spacecraft_scope_id, :point_id],
             name: :derived_telemetry_latest_values_scope_idx
           )

    create index(:derived_telemetry_latest_values, [:mission_id, :point_name])

    create table(:derived_telemetry_latest_value_rebuild_runs, primary_key: false) do
      add :rebuild_run_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :status, :string, null: false
      add :rebuilt_value_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:derived_telemetry_latest_value_rebuild_runs, [:mission_id, :inserted_at])
  end
end

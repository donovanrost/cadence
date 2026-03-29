defmodule Cadence.Repo.Migrations.CreatePhase6DerivedLimitsAndLimitStateProjection do
  use Ecto.Migration

  def change do
    create table(:governed_derived_telemetry_definitions) do
      add :mission_id, :string, null: false
      add :derived_definition_id, :string, null: false
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :expression, :string, null: false
      add :version, :integer, null: false
      add :source_point_ids, {:array, :string}, null: false, default: []
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :governed_derived_telemetry_definitions,
             [:mission_id, :derived_definition_id, :version],
             name: :governed_derived_telemetry_definitions_scope_idx
           )

    create index(:governed_derived_telemetry_definitions, [:mission_id, :point_id])

    create table(:governed_limit_definitions) do
      add :mission_id, :string, null: false
      add :limit_definition_id, :string, null: false
      add :point_id, :string, null: false
      add :version, :integer, null: false
      add :limit_set_name, :string, null: false
      add :thresholds, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :governed_limit_definitions,
             [:mission_id, :limit_definition_id, :version],
             name: :governed_limit_definitions_scope_idx
           )

    create index(:governed_limit_definitions, [:mission_id, :point_id])

    create table(:derived_telemetry_evaluation_runs, primary_key: false) do
      add :derived_run_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :status, :string, null: false
      add :evaluated_sample_count, :integer, null: false, default: 0
      add :emitted_sample_count, :integer, null: false, default: 0
      add :definition_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:derived_telemetry_evaluation_runs, [:mission_id, :inserted_at])

    create table(:derived_telemetry_samples, primary_key: false) do
      add :derived_sample_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :derived_definition_id, :string, null: false
      add :derived_definition_version, :integer, null: false

      add :trigger_sample_id,
          references(:telemetry_samples, column: :sample_id, type: :string, on_delete: :delete_all),
          null: false

      add :value, :map, null: false
      add :quality_state, :string, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:derived_telemetry_samples, [:mission_id, :receipt_time])
    create index(:derived_telemetry_samples, [:mission_id, :point_id, :receipt_time])
    create index(:derived_telemetry_samples, [:trigger_sample_id])

    create table(:telemetry_limit_evaluation_runs, primary_key: false) do
      add :limit_run_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :status, :string, null: false
      add :evaluated_sample_count, :integer, null: false, default: 0
      add :emitted_event_count, :integer, null: false, default: 0
      add :definition_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:telemetry_limit_evaluation_runs, [:mission_id, :inserted_at])

    create table(:telemetry_limit_events, primary_key: false) do
      add :limit_event_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :source_sample_type, :string, null: false
      add :sample_id, :string, null: false
      add :limit_definition_id, :string, null: false
      add :limit_definition_version, :integer, null: false
      add :limit_set_name, :string, null: false
      add :evaluated_value, :map, null: false
      add :limit_state, :string, null: false
      add :normalized_state, :string, null: false
      add :violation, :boolean, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:telemetry_limit_events, [:mission_id, :receipt_time])
    create index(:telemetry_limit_events, [:mission_id, :point_id, :receipt_time])
    create index(:telemetry_limit_events, [:mission_id, :source_sample_type, :sample_id])

    create table(:telemetry_latest_limit_states) do
      add :limit_event_id,
          references(:telemetry_limit_events,
            column: :limit_event_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :mission_id, :string, null: false
      add :spacecraft_scope_id, :string, null: false, default: ""
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :source_sample_type, :string, null: false
      add :sample_id, :string, null: false
      add :limit_definition_id, :string, null: false
      add :limit_definition_version, :integer, null: false
      add :limit_set_name, :string, null: false
      add :evaluated_value, :map, null: false
      add :limit_state, :string, null: false
      add :normalized_state, :string, null: false
      add :violation, :boolean, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :telemetry_latest_limit_states,
             [:mission_id, :spacecraft_scope_id, :point_id],
             name: :telemetry_latest_limit_states_scope_idx
           )

    create index(:telemetry_latest_limit_states, [:mission_id, :point_name])

    create table(:telemetry_latest_limit_state_rebuild_runs, primary_key: false) do
      add :rebuild_run_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :status, :string, null: false
      add :rebuilt_state_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:telemetry_latest_limit_state_rebuild_runs, [:mission_id, :inserted_at])
  end
end

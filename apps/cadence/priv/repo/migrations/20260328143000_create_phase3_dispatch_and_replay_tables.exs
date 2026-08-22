defmodule Cadence.Repo.Migrations.CreatePhase3DispatchAndReplayTables do
  use Ecto.Migration

  def change do
    create table(:application_dispatch_decisions, primary_key: false) do
      add :dispatch_decision_id, :string, primary_key: true

      add :packet_id,
          references(:protocol_packet_records,
            column: :packet_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :status, :string, null: false
      add :matched_rule_ids, :map, null: false, default: %{"items" => []}
      add :anomalies, :map, null: false, default: %{"items" => []}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:application_dispatch_decisions, [:packet_id])
    create index(:application_dispatch_decisions, [:evidence_id])

    create table(:application_dispatch_work_items) do
      add :dispatch_decision_id,
          references(:application_dispatch_decisions,
            column: :dispatch_decision_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :binding_rule_id, :string, null: false
      add :handler_key, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:application_dispatch_work_items, [:dispatch_decision_id])

    create table(:replay_runs, primary_key: false) do
      add :replay_run_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :status, :string, null: false
      add :replayed_evidence_count, :integer, null: false, default: 0
      add :replayed_packet_count, :integer, null: false, default: 0
      add :replayed_sample_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_runs, [:mission_id, :inserted_at])

    create table(:replay_dispatch_decisions, primary_key: false) do
      add :dispatch_decision_id, :string, primary_key: true

      add :replay_run_id,
          references(:replay_runs, column: :replay_run_id, type: :string, on_delete: :delete_all),
          null: false

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :packet_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :status, :string, null: false
      add :matched_rule_ids, :map, null: false, default: %{"items" => []}
      add :anomalies, :map, null: false, default: %{"items" => []}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_dispatch_decisions, [:replay_run_id])

    create table(:replay_dispatch_work_items) do
      add :dispatch_decision_id,
          references(:replay_dispatch_decisions,
            column: :dispatch_decision_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :binding_rule_id, :string, null: false
      add :handler_key, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_dispatch_work_items, [:dispatch_decision_id])

    create table(:replay_telemetry_samples, primary_key: false) do
      add :sample_id, :string, primary_key: true

      add :replay_run_id,
          references(:replay_runs, column: :replay_run_id, type: :string, on_delete: :delete_all),
          null: false

      add :packet_id, :string, null: false

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :packet_definition_id, :string, null: false
      add :packet_definition_version, :integer, null: false
      add :raw_value, :map, null: false
      add :engineering_value, :map, null: false
      add :quality_state, :string, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_telemetry_samples, [:replay_run_id, :point_id])
  end
end

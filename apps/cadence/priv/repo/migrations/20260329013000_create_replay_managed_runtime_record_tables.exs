defmodule Cadence.Repo.Migrations.CreateReplayManagedRuntimeRecordTables do
  use Ecto.Migration

  def change do
    create table(:replay_managed_capability_records, primary_key: false) do
      add :capability_record_id, :string, primary_key: true

      add :replay_run_id,
          references(:replay_runs, column: :replay_run_id, type: :string, on_delete: :delete_all),
          null: false

      add :mission_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :event_kind, :string, null: false
      add :packet_id, :string

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          )

      add :timer_key, :string
      add :emitted_record_kinds, :map, null: false, default: %{"items" => []}
      add :emitted_record_count, :integer, null: false
      add :action_request_count, :integer, null: false
      add :state_snapshot, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_managed_capability_records, [:replay_run_id, :recorded_at])
    create index(:replay_managed_capability_records, [:replay_run_id, :capability_instance_id])

    create table(:replay_managed_action_requests, primary_key: false) do
      add :action_request_id, :string, primary_key: true

      add :replay_run_id,
          references(:replay_runs, column: :replay_run_id, type: :string, on_delete: :delete_all),
          null: false

      add :mission_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :action_kind, :string, null: false
      add :packet_id, :string

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          )

      add :request_document, :map, null: false, default: %{}
      add :requested_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_managed_action_requests, [:replay_run_id, :requested_at])
    create index(:replay_managed_action_requests, [:replay_run_id, :capability_instance_id])

    create table(:replay_managed_timer_events, primary_key: false) do
      add :timer_event_id, :string, primary_key: true

      add :replay_run_id,
          references(:replay_runs, column: :replay_run_id, type: :string, on_delete: :delete_all),
          null: false

      add :mission_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :timer_key, :string, null: false
      add :event_kind, :string, null: false
      add :packet_id, :string

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          )

      add :due_at, :utc_datetime_usec
      add :occurred_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:replay_managed_timer_events, [:replay_run_id, :occurred_at])
    create index(:replay_managed_timer_events, [:replay_run_id, :capability_instance_id])
  end
end

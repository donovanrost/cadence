defmodule Cadence.Repo.Migrations.CreateManagedRuntimeRecordTables do
  use Ecto.Migration

  def change do
    create table(:managed_capability_records, primary_key: false) do
      add :capability_record_id, :string, primary_key: true
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
      add :evidence_id, :string
      add :timer_key, :string
      add :emitted_record_kinds, :map, null: false, default: %{}
      add :emitted_record_count, :integer, null: false
      add :action_request_count, :integer, null: false
      add :state_snapshot, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:managed_capability_records, [:mission_id, :capability_instance_id, :recorded_at])
    create index(:managed_capability_records, [:packet_id])
    create index(:managed_capability_records, [:evidence_id])

    create table(:managed_action_requests, primary_key: false) do
      add :action_request_id, :string, primary_key: true
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
      add :evidence_id, :string
      add :request_document, :map, null: false, default: %{}
      add :requested_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:managed_action_requests, [:mission_id, :capability_instance_id, :requested_at])
    create index(:managed_action_requests, [:packet_id])
    create index(:managed_action_requests, [:evidence_id])

    create table(:managed_timer_events, primary_key: false) do
      add :timer_event_id, :string, primary_key: true
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
      add :evidence_id, :string
      add :due_at, :utc_datetime_usec
      add :occurred_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:managed_timer_events, [:mission_id, :capability_instance_id, :occurred_at])
    create index(:managed_timer_events, [:packet_id])
    create index(:managed_timer_events, [:evidence_id])
  end
end

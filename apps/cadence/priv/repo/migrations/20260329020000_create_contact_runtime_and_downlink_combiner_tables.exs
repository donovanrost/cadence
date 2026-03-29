defmodule Cadence.Repo.Migrations.CreateContactRuntimeAndDownlinkCombinerTables do
  use Ecto.Migration

  def change do
    create table(:transport_capability_records, primary_key: false) do
      add :transport_record_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :path_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :event_kind, :string, null: false
      add :timer_key, :string
      add :emitted_record_kinds, :map, null: false, default: %{}
      add :emitted_record_count, :integer, null: false
      add :action_request_count, :integer, null: false
      add :state_snapshot, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:transport_capability_records, [:mission_id, :realized_contact_id, :path_id])
    create index(:transport_capability_records, [:mission_id, :capability_instance_id])

    create table(:transport_action_requests, primary_key: false) do
      add :action_request_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :path_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :action_kind, :string, null: false
      add :request_document, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :requested_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:transport_action_requests, [:mission_id, :realized_contact_id, :path_id])
    create index(:transport_action_requests, [:mission_id, :capability_instance_id])

    create table(:transport_timer_events, primary_key: false) do
      add :timer_event_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :path_id, :string, null: false
      add :capability_instance_id, :string, null: false
      add :family_key, :string, null: false
      add :activation_id, :string, null: false
      add :binding_set_id, :string, null: false
      add :binding_set_version, :integer, null: false
      add :partition_affinity, :string, null: false
      add :partition_value, :string, null: false
      add :timer_key, :string, null: false
      add :event_kind, :string, null: false
      add :due_at, :utc_datetime_usec
      add :occurred_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:transport_timer_events, [:mission_id, :realized_contact_id, :path_id])
    create index(:transport_timer_events, [:mission_id, :capability_instance_id])

    create table(:downlink_observations, primary_key: false) do
      add :observation_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :path_id, :string, null: false
      add :source_endpoint_ref, :string
      add :observation_key, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :quality_score, :integer, null: false, default: 0
      add :observed_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:downlink_observations, [:mission_id, :realized_contact_id, :observation_key])
    create index(:downlink_observations, [:mission_id, :realized_contact_id, :path_id])

    create table(:combined_downlink_records, primary_key: false) do
      add :merged_record_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :observation_key, :string, null: false
      add :source_endpoint_ref, :string
      add :selected_path_id, :string, null: false
      add :selected_observation_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :selected_reason, :string, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:combined_downlink_records, [:mission_id, :realized_contact_id, :observation_key])

    create table(:downlink_diagnostics, primary_key: false) do
      add :diagnostic_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :realized_contact_id, :string, null: false
      add :observation_key, :string, null: false
      add :path_id, :string, null: false
      add :selected_path_id, :string, null: false
      add :observation_id, :string, null: false
      add :competing_observation_id, :string
      add :diagnostic_kind, :string, null: false
      add :recorded_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:downlink_diagnostics, [:mission_id, :realized_contact_id, :observation_key])
    create index(:downlink_diagnostics, [:mission_id, :realized_contact_id, :path_id])
  end
end

defmodule Cadence.Repo.Migrations.CreateDataSourceHealthEvents do
  use Ecto.Migration

  def change do
    create table(:data_source_health_events, primary_key: false) do
      add(:source_health_event_id, :string, primary_key: true)
      add(:source_health_key, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:logical_source, :string, null: false)
      add(:data_source_id, :string, null: false)
      add(:source_binding_id, :string)
      add(:realm, :string)
      add(:replay_run_id, :string)
      add(:dataset, :string)
      add(:event_type, :string, null: false)
      add(:source_health, :string, null: false)
      add(:previous_source_health, :string)
      add(:reason, :string)
      add(:observed_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:data_source_health_events, [:source_health_key, :observed_at],
        name: :data_source_health_events_key_observed_idx
      )
    )

    create(
      index(:data_source_health_events, [:organization_id, :mission_id, :logical_source],
        name: :data_source_health_events_scope_idx
      )
    )

    create(
      index(:data_source_health_events, [:data_source_id],
        name: :data_source_health_events_data_source_idx
      )
    )

    create table(:data_source_health_statuses, primary_key: false) do
      add(:source_health_key, :string, primary_key: true)
      add(:source_health_event_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:logical_source, :string, null: false)
      add(:data_source_id, :string, null: false)
      add(:source_binding_id, :string)
      add(:realm, :string)
      add(:replay_run_id, :string)
      add(:dataset, :string)
      add(:event_type, :string, null: false)
      add(:source_health, :string, null: false)
      add(:previous_source_health, :string)
      add(:reason, :string)
      add(:observed_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:transition_count, :integer, null: false, default: 1)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:data_source_health_statuses, [:organization_id, :mission_id, :logical_source],
        name: :data_source_health_statuses_scope_idx
      )
    )

    create(
      index(:data_source_health_statuses, [:data_source_id],
        name: :data_source_health_statuses_data_source_idx
      )
    )

    create(
      index(:data_source_health_events, [:organization_id, :mission_id, :replay_run_id],
        name: :data_source_health_events_replay_idx
      )
    )

    create(
      index(:data_source_health_statuses, [:organization_id, :mission_id, :replay_run_id],
        name: :data_source_health_statuses_replay_idx
      )
    )
  end
end

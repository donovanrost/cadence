defmodule Cadence.Repo.Migrations.CreateTelemetryBackfillLifecycleEvents do
  use Ecto.Migration

  def change do
    create table(:telemetry_backfill_lifecycle_events, primary_key: false) do
      add(:backfill_lifecycle_event_id, :string, primary_key: true)
      add(:backfill_run_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:realm, :string, null: false)
      add(:replay_run_id, :string)
      add(:data_source_id, :string)
      add(:binding_id, :string)
      add(:observable_id, :string)
      add(:point_id, :string)
      add(:spacecraft_id, :string)
      add(:event_type, :string, null: false)
      add(:source_from, :utc_datetime_usec)
      add(:source_to, :utc_datetime_usec)
      add(:receipt_from, :utc_datetime_usec)
      add(:receipt_to, :utc_datetime_usec)
      add(:sample_count, :integer)
      add(:authority, :string, null: false)
      add(:reason, :string)
      add(:actor_id, :string)
      add(:actor_kind, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:telemetry_backfill_lifecycle_events, [:organization_id, :mission_id, :occurred_at],
        name: :telemetry_backfill_lifecycle_events_scope_idx
      )
    )

    create(
      index(
        :telemetry_backfill_lifecycle_events,
        [:organization_id, :mission_id, :data_source_id, :binding_id, :occurred_at],
        name: :telemetry_backfill_lifecycle_events_source_idx
      )
    )

    create(
      index(
        :telemetry_backfill_lifecycle_events,
        [:organization_id, :mission_id, :observable_id, :source_from, :source_to],
        name: :telemetry_backfill_lifecycle_events_observable_idx
      )
    )

    create(
      index(:telemetry_backfill_lifecycle_events, [:backfill_run_id, :occurred_at],
        name: :telemetry_backfill_lifecycle_events_run_idx
      )
    )

    create(
      index(:telemetry_backfill_lifecycle_events, [:organization_id, :mission_id, :replay_run_id],
        name: :telemetry_backfill_lifecycle_events_replay_idx
      )
    )
  end
end

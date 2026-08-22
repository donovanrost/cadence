defmodule Cadence.Repo.Migrations.CreateMissionEventRebuildRuns do
  use Ecto.Migration

  def change do
    create table(:mission_event_rebuild_runs, primary_key: false) do
      add(:rebuild_run_id, :string, primary_key: true)
      add(:mission_id, :string, null: false)
      add(:status, :string, null: false)
      add(:rebuilt_event_count, :integer, null: false, default: 0)
      add(:failure_reason, :map)
      add(:metadata, :map, null: false, default: %{})
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_event_rebuild_runs, [:mission_id, :started_at]))
  end
end

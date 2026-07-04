defmodule Cadence.Repo.Migrations.AddReplayRunToDashboardSourceWatermarks do
  use Ecto.Migration

  def change do
    alter table(:dashboard_source_watermark_events) do
      add(:replay_run_id, :string)
    end

    alter table(:dashboard_source_watermark_statuses) do
      add(:replay_run_id, :string)
    end

    create(
      index(:dashboard_source_watermark_events, [:mission_id, :replay_run_id],
        name: :dashboard_source_watermark_events_replay_run_idx
      )
    )

    create(
      index(:dashboard_source_watermark_statuses, [:mission_id, :replay_run_id],
        name: :dashboard_source_watermark_statuses_replay_run_idx
      )
    )
  end
end

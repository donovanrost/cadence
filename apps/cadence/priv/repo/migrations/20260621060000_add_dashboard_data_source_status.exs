defmodule Cadence.Repo.Migrations.AddDashboardDataSourceStatus do
  use Ecto.Migration

  def change do
    alter table(:dashboard_data_sources) do
      add(:status, :string, null: false, default: "active")
      add(:current_event_id, :string)
      add(:disabled_at, :utc_datetime_usec)
    end

    create(
      index(:dashboard_data_sources, [:status, :organization_id, :mission_id],
        name: :dashboard_data_sources_status_scope_idx
      )
    )

    alter table(:dashboard_data_source_events) do
      add(:previous_status, :string)
      add(:current_status, :string, null: false, default: "active")
    end
  end
end

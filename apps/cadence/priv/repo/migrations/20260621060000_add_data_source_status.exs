defmodule Cadence.Repo.Migrations.AddDataSourceStatus do
  use Ecto.Migration

  def change do
    alter table(:data_source_definitions) do
      add(:status, :string, null: false, default: "active")
      add(:current_event_id, :string)
      add(:disabled_at, :utc_datetime_usec)
    end

    create(
      index(:data_source_definitions, [:status, :organization_id, :mission_id],
        name: :data_source_definitions_status_scope_idx
      )
    )

    alter table(:data_source_definition_events) do
      add(:previous_status, :string)
      add(:current_status, :string, null: false, default: "active")
    end
  end
end

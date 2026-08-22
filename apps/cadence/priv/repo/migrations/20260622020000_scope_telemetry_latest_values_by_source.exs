defmodule Cadence.Repo.Migrations.ScopeTelemetryLatestValuesBySource do
  use Ecto.Migration

  def change do
    alter table(:telemetry_latest_values) do
      add(:realm, :string, null: false, default: "")
      add(:data_source_id, :string, null: false, default: "")
      add(:binding_id, :string, null: false, default: "")
    end

    drop(index(:telemetry_latest_values, [:mission_id, :spacecraft_scope_id, :point_id],
           name: :telemetry_latest_values_scope_idx
         ))

    create(
      unique_index(
        :telemetry_latest_values,
        [:mission_id, :spacecraft_scope_id, :point_id, :realm, :data_source_id, :binding_id],
        name: :telemetry_latest_values_scope_idx
      )
    )

    create(
      index(:telemetry_latest_values, [:mission_id, :realm, :data_source_id, :binding_id],
        name: :telemetry_latest_values_source_idx
      )
    )
  end
end

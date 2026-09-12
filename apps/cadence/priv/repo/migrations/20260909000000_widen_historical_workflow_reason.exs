defmodule Cadence.Repo.Migrations.WidenHistoricalWorkflowReason do
  use Ecto.Migration

  def change do
    alter table(:telemetry_backfill_lifecycle_events) do
      modify(:reason, :text, from: :string)
    end
  end
end

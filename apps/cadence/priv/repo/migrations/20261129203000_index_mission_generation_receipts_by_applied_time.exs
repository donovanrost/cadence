defmodule Cadence.Repo.Migrations.IndexMissionGenerationReceiptsByAppliedTime do
  use Ecto.Migration

  def change do
    create(
      index(
        :mission_generation_receipts,
        [:organization_id, :mission_id, :applied_at, :generation],
        name: :mission_generation_receipts_applied_at_idx
      )
    )
  end
end

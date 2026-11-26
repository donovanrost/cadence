defmodule Cadence.Repo.Migrations.PinFleetRunRequirementHashes do
  use Ecto.Migration

  def change do
    alter table(:fleet_planning_run_requirement_refs) do
      add(:input_content_sha256, :string, null: false)
    end
  end
end

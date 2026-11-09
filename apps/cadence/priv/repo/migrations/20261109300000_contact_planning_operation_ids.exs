defmodule Cadence.Repo.Migrations.ContactPlanningOperationIds do
  use Ecto.Migration

  # Console scheduling actions are operation-journaled (DECISIONS #27): the
  # client's operation_id is persisted on the run or plan it produced, unique
  # per mission, so a replay on any node finds the existing result.
  def change do
    alter table(:fleet_planning_runs) do
      add(:operation_id, :string)
    end

    alter table(:contact_plans) do
      add(:operation_id, :string)
    end

    create(
      unique_index(:fleet_planning_runs, [:mission_id, :operation_id],
        where: "operation_id IS NOT NULL",
        name: :fleet_planning_runs_mission_operation_id_index
      )
    )

    create(
      unique_index(:contact_plans, [:mission_id, :operation_id],
        where: "operation_id IS NOT NULL",
        name: :contact_plans_mission_operation_id_index
      )
    )
  end
end

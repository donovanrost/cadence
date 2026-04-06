defmodule Cadence.Repo.Migrations.CreateSetupWorkflows do
  use Ecto.Migration

  def change do
    create table(:setup_workflows, primary_key: false) do
      add(:setup_workflow_id, :string, primary_key: true)

      add(:current_step, :string, null: false)

      add(
        :active_organization_id,
        references(:organizations, column: :organization_id, type: :string)
      )

      add(:created_by_user_id, references(:users, column: :user_id, type: :string))
      add(:completed_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:setup_workflows, [:current_step]))
    create(index(:setup_workflows, [:active_organization_id]))
  end
end

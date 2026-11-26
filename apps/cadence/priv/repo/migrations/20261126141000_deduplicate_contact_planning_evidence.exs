defmodule Cadence.Repo.Migrations.DeduplicateContactPlanningEvidence do
  use Ecto.Migration

  def up do
    alter table(:contact_opportunity_snapshots) do
      remove(:route_binding_document)
      remove(:provider_evidence_document)
    end

    create(index(:contact_opportunity_snapshots, [:contact_planning_run_id]))
  end

  def down do
    drop(index(:contact_opportunity_snapshots, [:contact_planning_run_id]))

    alter table(:contact_opportunity_snapshots) do
      add(:route_binding_document, :map, null: false, default: %{})
      add(:provider_evidence_document, :map, null: false, default: %{})
    end
  end
end

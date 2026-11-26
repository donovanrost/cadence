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

    execute("""
    UPDATE contact_opportunity_snapshots AS snapshot
    SET route_binding_document = search.route_binding_document,
        provider_evidence_document = snapshot.normalized_opportunity_document
    FROM contact_planning_searches AS search
    WHERE search.contact_planning_search_id = snapshot.contact_planning_search_id
    """)
  end
end

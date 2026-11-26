defmodule Cadence.Repo.Migrations.DeduplicateFleetDecisionScores do
  use Ecto.Migration

  def up do
    # Development data is disposable; old decision rows have no score-document identity.
    execute("DELETE FROM fleet_planning_decisions")

    create table(:fleet_planning_score_documents, primary_key: false) do
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, primary_key: true)
      add(:score_document_sha256, :string, primary_key: true)
      add(:score_document, :map, null: false)
    end

    execute("""
    ALTER TABLE fleet_planning_score_documents
    ADD CONSTRAINT fleet_planning_score_documents_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    alter table(:fleet_planning_decisions) do
      remove(:score_document)
      add(:score_document_sha256, :string, null: false)
    end

    execute("""
    ALTER TABLE fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_score_document_fk
    FOREIGN KEY (mission_id, score_document_sha256)
    REFERENCES fleet_planning_score_documents (mission_id, score_document_sha256)
    ON DELETE RESTRICT
    """)

    create(index(:fleet_planning_decisions, [:mission_id, :score_document_sha256]))
  end

  def down do
    execute("DELETE FROM fleet_planning_decisions")

    execute("""
    ALTER TABLE fleet_planning_decisions
    DROP CONSTRAINT fleet_planning_decisions_score_document_fk
    """)

    drop(index(:fleet_planning_decisions, [:mission_id, :score_document_sha256]))

    alter table(:fleet_planning_decisions) do
      remove(:score_document_sha256)
      add(:score_document, :map, null: false, default: %{})
    end

    drop(table(:fleet_planning_score_documents))
  end
end

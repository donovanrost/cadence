defmodule Cadence.Repo.Migrations.SemanticLivePoliciesMissionFk do
  use Ecto.Migration

  # #451 T3b review: the policies a mission's newest generation keeps belong to a mission of the
  # same organization, as every other per-mission table does.
  def up do
    execute("""
    ALTER TABLE semantic_live_policies
      ADD CONSTRAINT semantic_live_policies_org_mission_fk
      FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute(
      "ALTER TABLE semantic_live_policies DROP CONSTRAINT semantic_live_policies_org_mission_fk"
    )
  end
end

defmodule Cadence.Repo.Migrations.PinFleetRunRequirementHashes do
  use Ecto.Migration

  def up do
    alter table(:fleet_planning_run_requirement_refs) do
      add(:input_content_sha256, :string)
    end

    execute("""
    UPDATE fleet_planning_run_requirement_refs AS ref
    SET input_content_sha256 = pinned.input->>'content_sha256'
    FROM fleet_planning_runs AS run
    CROSS JOIN LATERAL jsonb_array_elements(run.input_document->'requirements') AS pinned(input)
    WHERE ref.fleet_planning_run_id = run.fleet_planning_run_id
      AND ref.contact_requirement_id = pinned.input->>'contact_requirement_id'
      AND ref.contact_requirement_version = (pinned.input->>'contact_requirement_version')::integer
    """)

    alter table(:fleet_planning_run_requirement_refs) do
      modify(:input_content_sha256, :string, null: false)
    end
  end

  def down do
    alter table(:fleet_planning_run_requirement_refs) do
      remove(:input_content_sha256)
    end
  end
end

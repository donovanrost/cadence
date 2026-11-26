defmodule Cadence.Repo.Migrations.ScopeTemplateVersionsSpacecraftIndex do
  use Ecto.Migration

  def change do
    drop(
      index(
        :contact_requirement_template_versions,
        [:organization_id, :mission_id, :spacecraft_id],
        name: :contact_requirement_template_versions_spacecraft_idx
      )
    )

    # Without the spacecraft predicate, the planner can use just the mission prefix to
    # check each occurrence's template-version FK and filter every version in the fleet.
    create(
      index(
        :contact_requirement_template_versions,
        [:organization_id, :mission_id, :spacecraft_id],
        name: :contact_requirement_template_versions_spacecraft_idx,
        where: "spacecraft_id IS NOT NULL"
      )
    )
  end
end

defmodule Cadence.Repo.Migrations.MakeLatestDashboardVersionsCurrent do
  @moduledoc """
  Dashboards no longer have a separate publish step: every saved version is
  current (see `Cadence.Dashboards.CurrentVersions`). Make each dashboard's
  latest saved version current, so drafts saved under the old workflow are not
  stranded behind an older published version.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE ops_dashboards AS d
    SET published_version = latest.version,
        published_at = COALESCE(d.published_at, now()),
        draft_version = NULL
    FROM (
      SELECT organization_id, mission_id, dashboard_id, MAX(version) AS version
      FROM dashboard_versions
      GROUP BY organization_id, mission_id, dashboard_id
    ) AS latest
    WHERE latest.organization_id = d.organization_id
      AND latest.mission_id = d.mission_id
      AND latest.dashboard_id = d.dashboard_id
      AND d.published_version IS DISTINCT FROM latest.version
    """)

    execute("""
    UPDATE dashboard_versions AS v
    SET snapshot_kind = 'publish'
    FROM ops_dashboards AS d
    WHERE v.organization_id = d.organization_id
      AND v.mission_id = d.mission_id
      AND v.dashboard_id = d.dashboard_id
      AND v.version = d.published_version
      AND v.snapshot_kind = 'draft_save'
    """)
  end

  # Publication pointers moved forward cannot be reconstructed; the versions remain.
  def down, do: :ok
end

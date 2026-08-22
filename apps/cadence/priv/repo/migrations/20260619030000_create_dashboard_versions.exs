defmodule Cadence.Repo.Migrations.CreateDashboardVersions do
  use Ecto.Migration

  def change do
    create table(:dashboard_versions, primary_key: false) do
      add(:dashboard_version_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:document, :map, null: false)
      add(:snapshot_kind, :string, null: false)
      add(:parent_version, :integer)
      add(:based_on_version, :integer)
      add(:schema_version, :integer, null: false, default: 1)
      add(:change_summary, :text)
      add(:created_by, :string)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:dashboard_versions, [:organization_id, :mission_id, :dashboard_id, :version],
        name: :dashboard_versions_scope_version_idx
      )
    )

    create(
      index(:dashboard_versions, [:organization_id, :mission_id, :dashboard_id],
        name: :dashboard_versions_scope_idx
      )
    )

    execute(
      """
      ALTER TABLE dashboard_versions
      ADD CONSTRAINT dashboard_versions_dashboard_fk
      FOREIGN KEY (dashboard_id)
      REFERENCES ops_dashboards (dashboard_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE dashboard_versions
      DROP CONSTRAINT IF EXISTS dashboard_versions_dashboard_fk
      """
    )
  end
end

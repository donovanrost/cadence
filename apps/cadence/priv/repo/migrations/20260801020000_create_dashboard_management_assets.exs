defmodule Cadence.Repo.Migrations.CreateDashboardManagementAssets do
  use Ecto.Migration

  def up do
    create table(:dashboard_shares, primary_key: false) do
      add(:dashboard_share_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:created_by, :string)
      add(:access_policy, :string, null: false, default: "mission_member")
      add(:data_visibility, :string, null: false, default: "authorized_runtime_data")
      add(:runtime_context, :map, null: false, default: %{})
      add(:expires_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:dashboard_shares, [:organization_id, :mission_id, :dashboard_id]))

    create table(:dashboard_snapshots, primary_key: false) do
      add(:dashboard_snapshot_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:dashboard_version, :integer, null: false)
      add(:created_by, :string)
      add(:runtime_context, :map, null: false, default: %{})
      add(:data_semantics, :string, null: false)
      add(:data_visibility, :string, null: false, default: "authorized_runtime_data")
      add(:document, :map, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:dashboard_snapshots, [:organization_id, :mission_id, :dashboard_id],
        name: :dashboard_snapshots_scope_dashboard_idx
      )
    )

    create table(:dashboard_library_items, primary_key: false) do
      add(:dashboard_library_item_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:latest_version, :integer, null: false, default: 1)
      add(:created_by, :string)
      add(:updated_by, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:dashboard_library_items, [:organization_id, :mission_id, :name],
        name: :dashboard_library_items_scope_name_idx
      )
    )

    create table(:dashboard_library_versions, primary_key: false) do
      add(:dashboard_library_version_id, :string, primary_key: true)
      add(:dashboard_library_item_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:widget_definition, :map, null: false)
      add(:compatibility, :map, null: false, default: %{})
      add(:change_summary, :text)
      add(:created_by, :string)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:dashboard_library_versions, [:dashboard_library_item_id, :version],
        name: :dashboard_library_versions_item_version_idx
      )
    )

    create table(:dashboard_playlists, primary_key: false) do
      add(:dashboard_playlist_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:dashboard_ids, {:array, :string}, null: false, default: [])
      add(:dwell_seconds, :integer, null: false, default: 30)
      add(:wallboard_mode, :boolean, null: false, default: false)
      add(:created_by, :string)
      add(:updated_by, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:dashboard_playlists, [:organization_id, :mission_id, :name],
        name: :dashboard_playlists_scope_name_idx
      )
    )

    create table(:dashboard_deployments, primary_key: false) do
      add(:dashboard_deployment_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:dashboard_version, :integer, null: false)
      add(:environment, :string, null: false)
      add(:artifact_digest, :string, null: false)
      add(:status, :string, null: false)
      add(:created_by, :string)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:dashboard_deployments, [:organization_id, :mission_id, :dashboard_id],
        name: :dashboard_deployments_scope_dashboard_idx
      )
    )

    for table <- [
          :dashboard_shares,
          :dashboard_snapshots,
          :dashboard_library_items,
          :dashboard_playlists,
          :dashboard_deployments
        ] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_org_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)

      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end

    for table <- [:dashboard_shares, :dashboard_snapshots] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_dashboard_fk
      FOREIGN KEY (dashboard_id)
      REFERENCES ops_dashboards (dashboard_id)
      ON DELETE CASCADE
      """)
    end

    execute("""
    ALTER TABLE dashboard_deployments
    ADD CONSTRAINT dashboard_deployments_dashboard_fk
    FOREIGN KEY (dashboard_id)
    REFERENCES ops_dashboards (dashboard_id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE dashboard_library_versions
    ADD CONSTRAINT dashboard_library_versions_item_fk
    FOREIGN KEY (dashboard_library_item_id)
    REFERENCES dashboard_library_items (dashboard_library_item_id)
    ON DELETE CASCADE
    """)
  end

  def down do
    drop(table(:dashboard_deployments))
    drop(table(:dashboard_playlists))
    drop(table(:dashboard_library_versions))
    drop(table(:dashboard_library_items))
    drop(table(:dashboard_snapshots))
    drop(table(:dashboard_shares))
  end
end

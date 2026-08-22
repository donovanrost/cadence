defmodule Cadence.Repo.Migrations.CreateDashboardInvestigationPresets do
  use Ecto.Migration

  def up do
    create table(:dashboard_investigation_presets, primary_key: false) do
      add(:dashboard_investigation_preset_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:name, :string, null: false)
      add(:description, :string)
      add(:schema, :string, null: false)
      add(:preset_kind, :string, null: false)
      add(:runtime_query, :map, null: false, default: %{})
      add(:payload, :map, null: false, default: %{})
      add(:primary_data_view, :string)
      add(:compare_data_view, :string)
      add(:affected_placement_ids, {:array, :string}, null: false, default: [])
      add(:created_by, :string)
      add(:updated_by, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :dashboard_id, :name],
        name: :dashboard_investigation_presets_dashboard_name_idx
      )
    )

    create(
      index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :dashboard_id, :inserted_at],
        name: :dashboard_investigation_presets_dashboard_idx
      )
    )

    create(
      index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :preset_kind],
        name: :dashboard_investigation_presets_kind_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_investigation_presets
    ADD CONSTRAINT dashboard_investigation_presets_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE dashboard_investigation_presets
    ADD CONSTRAINT dashboard_investigation_presets_dashboard_fk
    FOREIGN KEY (dashboard_id)
    REFERENCES ops_dashboards (dashboard_id)
    ON DELETE CASCADE
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON dashboard_investigation_presets
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON dashboard_investigation_presets
    """)

    execute("""
    ALTER TABLE dashboard_investigation_presets
    DROP CONSTRAINT IF EXISTS dashboard_investigation_presets_dashboard_fk
    """)

    execute("""
    ALTER TABLE dashboard_investigation_presets
    DROP CONSTRAINT IF EXISTS dashboard_investigation_presets_org_mission_fk
    """)

    drop_if_exists(
      index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :preset_kind],
        name: :dashboard_investigation_presets_kind_idx
      )
    )

    drop_if_exists(
      index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :dashboard_id, :inserted_at],
        name: :dashboard_investigation_presets_dashboard_idx
      )
    )

    drop_if_exists(
      index(
        :dashboard_investigation_presets,
        [:organization_id, :mission_id, :dashboard_id, :name],
        name: :dashboard_investigation_presets_dashboard_name_idx
      )
    )

    drop(table(:dashboard_investigation_presets))
  end
end

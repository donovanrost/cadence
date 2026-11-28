defmodule Cadence.Repo.Migrations.ReplaceSpacecraftConfigurationRevisions do
  use Ecto.Migration

  def up do
    create table(:spacecraft_configuration_artifacts, primary_key: false) do
      add(:organization_id, :text, primary_key: true)
      add(:mission_id, :text, primary_key: true)
      add(:sha256, :text, primary_key: true)
      add(:document, :map, null: false)
      add(:catalog_revision_id, :text)
      add(:composition_id, :text)
      add(:effective_revision_id, :text)
    end

    execute("""
    ALTER TABLE spacecraft_configuration_artifacts
      ADD CONSTRAINT spacecraft_configuration_artifacts_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id) ON DELETE CASCADE
    """)

    create(
      constraint(:spacecraft_configuration_artifacts, :configuration_artifact_without_endpoint,
        check: "NOT (document ? 'telemetry_source_endpoint_id')"
      )
    )

    create table(:spacecraft_configuration_assignments, primary_key: false) do
      add(:configuration_revision_id, :text, primary_key: true)
      add(:organization_id, :text, null: false)
      add(:mission_id, :text, null: false)
      add(:spacecraft_id, :text, null: false)
      add(:version, :integer, null: false)
      add(:artifact_sha256, :text, null: false)
      add(:source_endpoint_id, :text)
      add(:application_basis, :text, null: false)
      add(:created_by, :text, null: false)
      add(:change_set_id, :text)
      add(:change_set_revision, :integer)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :spacecraft_configuration_assignments,
        [
          :organization_id,
          :mission_id,
          :spacecraft_id,
          :version
        ],
        name: :spacecraft_configuration_assignments_version_idx
      )
    )

    create(
      unique_index(
        :spacecraft_configuration_assignments,
        [
          :organization_id,
          :mission_id,
          :spacecraft_id,
          :configuration_revision_id
        ],
        name: :spacecraft_configuration_assignments_head_idx
      )
    )

    create(
      constraint(:spacecraft_configuration_assignments, :positive_assignment_version,
        check: "version > 0"
      )
    )

    execute("""
    ALTER TABLE spacecraft_configuration_assignments
      ADD CONSTRAINT spacecraft_configuration_assignments_spacecraft_fk
      FOREIGN KEY (organization_id, mission_id, spacecraft_id)
      REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id) ON DELETE CASCADE,
      ADD CONSTRAINT spacecraft_configuration_assignments_artifact_fk
      FOREIGN KEY (organization_id, mission_id, artifact_sha256)
      REFERENCES spacecraft_configuration_artifacts (organization_id, mission_id, sha256)
    """)

    create table(:spacecraft_configuration_heads, primary_key: false) do
      add(:organization_id, :text, primary_key: true)
      add(:mission_id, :text, primary_key: true)
      add(:spacecraft_id, :text, primary_key: true)
      add(:configuration_revision_id, :text, null: false)
    end

    execute("""
    ALTER TABLE spacecraft_configuration_heads
      ADD CONSTRAINT spacecraft_configuration_heads_assignment_fk
      FOREIGN KEY (organization_id, mission_id, spacecraft_id, configuration_revision_id)
      REFERENCES spacecraft_configuration_assignments
        (organization_id, mission_id, spacecraft_id, configuration_revision_id) ON DELETE CASCADE
    """)

    execute("""
    CREATE FUNCTION refuse_spacecraft_configuration_history_update()
    RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'spacecraft configuration history is immutable' USING ERRCODE = 'check_violation';
    END;
    $$
    """)

    for table <- ~w(spacecraft_configuration_assignments spacecraft_configuration_artifacts) do
      execute("""
      CREATE TRIGGER configuration_history_immutable BEFORE UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION refuse_spacecraft_configuration_history_update()
      """)
    end

    drop(table(:spacecraft_configuration_revisions))
  end

  def down do
    raise Ecto.MigrationError,
          "spacecraft configuration revisions were replaced (#448); reset and reseed"
  end
end

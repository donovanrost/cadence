defmodule Cadence.Repo.Migrations.CreateSpacecraftConfigurationRevisions do
  use Ecto.Migration

  def change do
    create table(:spacecraft_configuration_revisions, primary_key: false) do
      add(:configuration_revision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:catalog_revision_id, :string)
      add(:document, :map, null: false)
      add(:content_sha256, :string, null: false)
      add(:application_basis, :string, null: false)
      add(:created_by, :string, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :spacecraft_configuration_revisions,
        [:organization_id, :mission_id, :spacecraft_id, :version],
        name: :spacecraft_configuration_revisions_version_idx
      )
    )

    create(
      index(:spacecraft_configuration_revisions, [
        :organization_id,
        :mission_id,
        :catalog_revision_id
      ])
    )

    execute(
      """
      ALTER TABLE spacecraft_configuration_revisions
      ADD CONSTRAINT spacecraft_configuration_revisions_spacecraft_fk
      FOREIGN KEY (organization_id, mission_id, spacecraft_id)
      REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE spacecraft_configuration_revisions
      DROP CONSTRAINT spacecraft_configuration_revisions_spacecraft_fk
      """
    )
  end
end

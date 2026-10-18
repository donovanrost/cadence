defmodule Cadence.Repo.Migrations.CreateScopedSettingsRevisions do
  use Ecto.Migration

  def change do
    create table(:scoped_settings_revisions, primary_key: false) do
      add(:revision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:scope_key, :string, null: false)
      add(:section_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:document, :map, null: false)
      add(:actor_id, :string, null: false)
      add(:actor_name, :string, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :scoped_settings_revisions,
        [:organization_id, :scope_key, :section_id, :version],
        name: :scoped_settings_revisions_version_idx
      )
    )

    create(
      constraint(:scoped_settings_revisions, :scoped_settings_positive_version,
        check: "version > 0"
      )
    )
  end
end

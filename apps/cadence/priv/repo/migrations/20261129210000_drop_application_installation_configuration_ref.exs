defmodule Cadence.Repo.Migrations.DropApplicationInstallationConfigurationRef do
  use Ecto.Migration

  # #669 b: an optional application declares no actions, so no action provider hands the host a
  # configuration reference to pin on its installation. The reference copied a version the
  # application's own configuration row already holds; nothing reads it, so no data moves.
  def up do
    drop(constraint(:application_installations, :application_installations_configuration_ref_check))

    alter table(:application_installations) do
      remove(:configuration_kind)
      remove(:configuration_id)
      remove(:configuration_version)
    end
  end

  def down do
    alter table(:application_installations) do
      add(:configuration_kind, :string)
      add(:configuration_id, :string)
      add(:configuration_version, :integer)
    end

    create(
      constraint(:application_installations, :application_installations_configuration_ref_check,
        check:
          "(configuration_kind IS NULL AND configuration_id IS NULL AND configuration_version IS NULL) OR " <>
            "(configuration_kind IS NOT NULL AND configuration_id IS NOT NULL AND configuration_version > 0)"
      )
    )
  end
end

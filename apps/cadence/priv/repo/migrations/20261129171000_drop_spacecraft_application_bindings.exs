defmodule Cadence.Repo.Migrations.DropSpacecraftApplicationBindings do
  use Ecto.Migration

  def up do
    drop(table(:spacecraft_application_bindings))
  end

  def down do
    raise Ecto.MigrationError,
          "spacecraft application bindings now resolve from configuration heads (#449)"
  end
end

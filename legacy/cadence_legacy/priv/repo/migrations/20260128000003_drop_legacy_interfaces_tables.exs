defmodule Cadence.Repo.Migrations.DropLegacyInterfacesTables do
  use Ecto.Migration

  def change do
    drop_if_exists table(:interface_protocols)
    drop_if_exists table(:interface_vcids)
    drop_if_exists table(:target_interfaces)
    drop_if_exists table(:interfaces)
  end
end

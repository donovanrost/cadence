defmodule Cadence.Repo.Migrations.RemoveLegacyProtocolFieldsFromInterfaces do
  use Ecto.Migration

  def up do
    # Remove legacy single-protocol fields from interfaces table
    # This is a breaking change - existing interfaces will need to be reconfigured
    alter table(:interfaces) do
      remove :protocol_type
      remove :protocol_config
      remove :protocol_direction
    end
  end

  def down do
    # Restore legacy fields if rolling back
    # Note: Data cannot be recovered automatically
    alter table(:interfaces) do
      add :protocol_type, :string
      add :protocol_config, :map, default: %{}
      add :protocol_direction, :string, default: "read_write"
    end
  end
end

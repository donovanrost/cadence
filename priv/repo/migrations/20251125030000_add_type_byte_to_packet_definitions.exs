defmodule Cadence.Repo.Migrations.AddTypeByteToPacketDefinitions do
  use Ecto.Migration

  def change do
    alter table(:packet_definitions) do
      add :type_byte, :integer
    end
  end
end

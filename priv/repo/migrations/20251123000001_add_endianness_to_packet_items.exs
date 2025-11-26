defmodule Cadence.Repo.Migrations.AddEndiannessToPacketItems do
  use Ecto.Migration

  def change do
    alter table(:packet_items) do
      add :endianness, :string, default: "big"
    end
  end
end

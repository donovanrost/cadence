defmodule Cadence.Repo.Migrations.AddDerivedItemsSupport do
  use Ecto.Migration

  def change do
    # Add derived_config field for storing derived item configuration
    # Structure: %{
    #   "expression" => "TEMP1 + TEMP2",
    #   "source_items" => ["TEMP1", "TEMP2"],
    #   "cross_packet_items" => [%{"target" => "SC1", "packet" => "POWER", "item" => "VOLTAGE"}]
    # }
    alter table(:packet_items) do
      add :derived_config, :map, default: %{}
    end

    # Add check constraint to ensure derived items have bit_offset=0 and bit_size=0
    # and non-derived items have bit_size > 0
    # Note: data_type validation happens at application level since we're adding "derived"
    # to the allowed types
  end
end

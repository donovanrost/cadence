defmodule Cadence.Repo.Migrations.CreatePacketItems do
  use Ecto.Migration

  def change do
    create table(:packet_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Belongs to packet definition
      add :packet_definition_id,
          references(:packet_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      # Item identification
      add :name, :string, null: false
      add :description, :text

      # Bit-level extraction (decommutation)
      add :bit_offset, :integer, null: false
      add :bit_length, :integer, null: false
      # uint, int, float, string, boolean
      add :data_type, :string, null: false

      # Conversion configuration
      # polynomial, state, segmented_polynomial
      add :conversion_type, :string
      add :conversion_config, :map, default: %{}

      # Units and formatting
      add :units, :string
      add :format_string, :string

      # Limits configuration
      add :has_limits, :boolean, default: false
      add :limits_config, :map, default: %{}

      # Display configuration
      add :display_order, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:packet_items, [:packet_definition_id])
    create unique_index(:packet_items, [:packet_definition_id, :name])
  end
end

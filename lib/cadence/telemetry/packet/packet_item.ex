defmodule Cadence.Telemetry.Packet.PacketItem do
  @moduledoc """
  Defines a single telemetry item within a packet.

  Each packet item describes a specific telemetry point including its location
  in the packet (bit offset and size), data type, conversion, limits, and display
  configuration.

  Note: Derived telemetry items are stored separately in the `derived_items` table
  as a mission-scoped runtime overlay. See `Cadence.Telemetry.Database.DerivedItem`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Telemetry.Packet.PacketDefinition
  alias Cadence.Telemetry.Conversions.Conversion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @data_types ["uint", "int", "float", "string", "boolean"]
  @endianness_values ["big", "little"]

  schema "packet_items" do
    # Belongs to packet definition
    belongs_to :packet_definition, PacketDefinition

    # Conversion - foreign key to conversions table
    belongs_to :conversion, Conversion

    # Item identification
    field :name, :string
    field :description, :string

    # Bit-level extraction (decommutation)
    field :bit_offset, :integer
    field :bit_size, :integer
    field :data_type, :string
    field :endianness, :string, default: "big"

    # Units and formatting
    field :units, :string
    field :format_string, :string

    # Limits configuration
    field :has_limits, :boolean, default: false
    field :limits_config, :map, default: %{}

    # Display configuration
    field :display_order, :integer
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a packet item.
  """
  def changeset(packet_item, attrs) do
    packet_item
    |> cast(attrs, [
      :packet_definition_id,
      :conversion_id,
      :name,
      :description,
      :bit_offset,
      :bit_size,
      :data_type,
      :endianness,
      :units,
      :format_string,
      :has_limits,
      :limits_config,
      :display_order,
      :metadata
    ])
    |> validate_required([:packet_definition_id, :name, :bit_offset, :bit_size, :data_type])
    |> validate_inclusion(:data_type, @data_types)
    |> validate_inclusion(:endianness, @endianness_values)
    |> validate_bit_fields()
    |> unique_constraint([:packet_definition_id, :name])
  end

  # Validate bit_offset and bit_size
  defp validate_bit_fields(changeset) do
    changeset
    |> validate_number(:bit_offset, greater_than_or_equal_to: 0)
    |> validate_number(:bit_size, greater_than: 0)
  end
end

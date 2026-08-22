defmodule Cadence.Telemetry.Packet.PacketDefinition do
  @moduledoc """
  Defines the structure and identification information for a telemetry packet.

  Packet definitions describe how to identify and parse telemetry packets from
  spacecraft. Each packet definition belongs to a mission and contains items
  that describe the telemetry points within the packet.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.DefinitionSet
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Telemetry.Packet.PacketItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "packet_definitions" do
    # Multi-tenancy scoping
    belongs_to :organization, Organization
    belongs_to :mission, Mission

    # Versioning - optional, for imported definitions
    belongs_to :definition_set, DefinitionSet

    # Packet identification
    field :name, :string
    field :description, :string

    # CCSDS/Packet fields for identification
    field :apid, :integer
    field :packet_id, :integer
    field :packet_type, :string
    field :type_byte, :integer

    # Protocol and framing information
    field :is_big_endian, :boolean, default: true
    field :has_sync_pattern, :boolean, default: false
    field :sync_pattern, :binary
    field :fixed_length, :integer

    # Metadata
    field :metadata, :map, default: %{}

    # Associations
    has_many :packet_items, PacketItem, foreign_key: :packet_definition_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a packet definition.
  """
  def changeset(packet_definition, attrs) do
    packet_definition
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :apid,
      :packet_id,
      :packet_type,
      :type_byte,
      :is_big_endian,
      :has_sync_pattern,
      :sync_pattern,
      :fixed_length,
      :metadata
    ])
    |> validate_required([:organization_id, :mission_id, :name])
    |> unique_constraint([:mission_id, :name])
    |> unique_constraint([:definition_set_id, :name],
      message: "Packet name must be unique within a definition set"
    )
    |> validate_number(:apid, greater_than_or_equal_to: 0, less_than: 2048)
  end
end

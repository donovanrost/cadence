defmodule Cadence.MissionDatabase.Stream do
  @moduledoc """
  Defines framing protocol for telemetry/command streams.

  A Stream describes how raw bytes are framed into packets and how
  packets are identified to their container definitions.

  ## Framing Protocols

  - **ccsds_aos**: CCSDS Advanced Orbiting Systems
  - **ccsds_packet**: CCSDS Space Packet Protocol
  - **ccsds_tc**: CCSDS Telecommand
  - **hdlc**: HDLC framing
  - **slip**: Serial Line IP
  - **length_prefixed**: Simple length-prefixed frames
  - **delimiter**: Delimiter-based framing
  - **fixed_length**: Fixed-length frames
  - **custom**: Custom framing module

  ## Example: CCSDS Stream

      %Stream{
        name: "PRIMARY_TLM",
        stream_type: :telemetry,
        framing_protocol: :ccsds_packet,
        sync_pattern: <<0x1A, 0xCF, 0xFC, 0x1D>>,
        error_detection: :crc16
      }

  ## Example: Length-Prefixed Stream

      %Stream{
        name: "CMD_UPLINK",
        stream_type: :command,
        framing_protocol: :length_prefixed,
        length_field_offset: 0,
        length_field_size: 16
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stream_types [:telemetry, :command, :bidirectional]

  @framing_protocols [
    :ccsds_aos,
    :ccsds_packet,
    :ccsds_tc,
    :hdlc,
    :slip,
    :length_prefixed,
    :delimiter,
    :fixed_length,
    :custom
  ]

  @error_detection_types [:none, :crc16, :crc32, :checksum]

  schema "mdb_streams" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string

    field :stream_type, Ecto.Enum, values: @stream_types
    field :framing_protocol, Ecto.Enum, values: @framing_protocols

    # Framing configuration
    field :sync_pattern, :binary
    field :frame_length, :integer
    field :length_field_offset, :integer
    field :length_field_size, :integer
    field :delimiter, :binary

    # Custom framing
    field :custom_framer_module, :string
    field :custom_framer_config, :map, default: %{}

    # Error detection
    field :error_detection, Ecto.Enum, values: @error_detection_types
    field :error_detection_offset, :integer
    field :error_detection_polynomial, :integer

    # Associated containers
    has_many :containers, Cadence.MissionDatabase.Container

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a Stream.
  """
  def changeset(stream, attrs) do
    stream
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :stream_type,
      :framing_protocol,
      :sync_pattern,
      :frame_length,
      :length_field_offset,
      :length_field_size,
      :delimiter,
      :custom_framer_module,
      :custom_framer_config,
      :error_detection,
      :error_detection_offset,
      :error_detection_polynomial,
      :extensions
    ])
    |> validate_required([
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :stream_type,
      :framing_protocol
    ])
    |> validate_inclusion(:stream_type, @stream_types)
    |> validate_inclusion(:framing_protocol, @framing_protocols)
    |> validate_framing_config()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_streams_definition_set_name_index
    )
  end

  defp validate_framing_config(changeset) do
    case get_field(changeset, :framing_protocol) do
      :fixed_length ->
        validate_required(changeset, [:frame_length])

      :length_prefixed ->
        changeset
        |> validate_required([:length_field_offset, :length_field_size])

      :delimiter ->
        validate_required(changeset, [:delimiter])

      :custom ->
        validate_required(changeset, [:custom_framer_module])

      _ ->
        changeset
    end
  end

  @doc """
  Returns the list of valid stream types.
  """
  def valid_stream_types, do: @stream_types

  @doc """
  Returns the list of valid framing protocols.
  """
  def valid_framing_protocols, do: @framing_protocols

  @doc """
  Returns the list of valid error detection types.
  """
  def valid_error_detection_types, do: @error_detection_types
end

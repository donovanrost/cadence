defmodule Cadence.CCSDS.SpacePacket do
  @moduledoc """
  Semantic CCSDS Space Packet value.

  The packet data field is kept opaque because secondary-header and user-data
  formats are mission-managed. `secondary_header?` only records whether the
  first part of `data` is such a managed secondary header.
  """

  @primary_header_size 6
  @minimum_data_size 1
  @maximum_data_size 65_536
  @idle_apid 0x7FF

  @type packet_type :: :telemetry | :command
  @type sequence_flag :: :continuation | :first | :last | :unsegmented

  @type t :: %__MODULE__{
          version: 0,
          packet_type: packet_type(),
          secondary_header?: boolean(),
          apid: 0..0x7FF,
          sequence_flag: sequence_flag(),
          sequence_count: 0..0x3FFF,
          data: binary()
        }

  defstruct version: 0,
            packet_type: :telemetry,
            secondary_header?: false,
            apid: nil,
            sequence_flag: :unsegmented,
            sequence_count: 0,
            data: <<>>

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    struct(__MODULE__, attrs)
  end

  @spec primary_header_size() :: 6
  def primary_header_size, do: @primary_header_size

  @spec minimum_size() :: 7
  def minimum_size, do: @primary_header_size + @minimum_data_size

  @spec maximum_size() :: 65_542
  def maximum_size, do: @primary_header_size + @maximum_data_size

  @spec idle_apid() :: 0x7FF
  def idle_apid, do: @idle_apid

  @spec idle?(t()) :: boolean()
  def idle?(%__MODULE__{apid: @idle_apid}), do: true
  def idle?(%__MODULE__{}), do: false

  @spec sequence_flag_value(sequence_flag()) :: 0..3
  def sequence_flag_value(:continuation), do: 0
  def sequence_flag_value(:first), do: 1
  def sequence_flag_value(:last), do: 2
  def sequence_flag_value(:unsegmented), do: 3

  @spec sequence_flag_from_value(0..3) :: sequence_flag()
  def sequence_flag_from_value(0), do: :continuation
  def sequence_flag_from_value(1), do: :first
  def sequence_flag_from_value(2), do: :last
  def sequence_flag_from_value(3), do: :unsegmented
end

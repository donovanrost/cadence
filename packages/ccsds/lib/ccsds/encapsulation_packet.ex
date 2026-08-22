defmodule CCSDS.EncapsulationPacket do
  @moduledoc """
  Semantic CCSDS 133.1-B-3 Encapsulation Packet.

  The Encapsulated Data field remains opaque. Protocol identification is
  carried by the three-bit EPI or, for EPI 6, the four-bit extension. Decoded
  values retain their wire header size so exact re-encoding is possible.
  """

  @type header_octets :: 1 | 2 | 4 | 8
  @type t :: %__MODULE__{
          version: 7,
          protocol_id: 0..7,
          protocol_id_extension: 0..15 | nil,
          user_defined: 0..15,
          ccsds_defined: 0,
          data: binary(),
          header_octets: header_octets() | nil
        }

  defstruct version: 7,
            protocol_id: nil,
            protocol_id_extension: nil,
            user_defined: 0,
            ccsds_defined: 0,
            data: <<>>,
            header_octets: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs),
    do: struct(__MODULE__, Map.new(attrs))

  @spec idle?(t()) :: boolean()
  def idle?(%__MODULE__{protocol_id: 0}), do: true
  def idle?(%__MODULE__{}), do: false

  @spec protocol(atom()) :: 0..7
  def protocol(:idle), do: 0
  def protocol(:ltp), do: 1
  def protocol(:internet_protocol_extension), do: 2
  def protocol(:cfdp), do: 3
  def protocol(:bundle_protocol), do: 4
  def protocol(:extended), do: 6
  def protocol(:private), do: 7
end

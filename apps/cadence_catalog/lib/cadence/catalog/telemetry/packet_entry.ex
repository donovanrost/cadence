defmodule Cadence.Catalog.Telemetry.PacketEntry do
  @moduledoc """
  Canonical telemetry packet entry that references points or nested packets.
  """

  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Telemetry.{MatchCriteria, Normalize, Packet, Point, Provenance}

  @type entry_kind :: :point_ref | :fixed_value | :nested_packet_ref | :array_point_ref
  @type bit_offset_from :: :packet_start | :previous_entry | :base_packet_end

  @type t :: %__MODULE__{
          packet_entry_id: binary(),
          entry_kind: entry_kind(),
          point_id: binary() | nil,
          nested_packet_id: binary() | nil,
          bit_offset: non_neg_integer() | nil,
          bit_offset_from: bit_offset_from(),
          fixed_value: binary() | nil,
          fixed_value_size_bits: pos_integer() | nil,
          array_size: pos_integer() | nil,
          array_size_ref: binary() | nil,
          include_condition: MatchCriteria.t() | nil,
          display_order: integer() | nil,
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :packet_entry_id,
    :entry_kind,
    :point_id,
    :nested_packet_id,
    :bit_offset,
    :fixed_value,
    :fixed_value_size_bits,
    :array_size,
    :array_size_ref,
    :include_condition,
    :display_order,
    :provenance,
    bit_offset_from: :packet_start,
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      packet_entry_id: Normalize.get(attrs, :packet_entry_id, Ids.new("packet_entry")),
      entry_kind: Normalize.get(attrs, :entry_kind, :point_ref) |> normalize_entry_kind(),
      point_id: point_ref(Normalize.get(attrs, :point_ref)),
      nested_packet_id: packet_ref(Normalize.get(attrs, :nested_packet_ref)),
      bit_offset: Normalize.get(attrs, :bit_offset),
      bit_offset_from:
        Normalize.get(attrs, :bit_offset_from, :packet_start) |> normalize_bit_offset_from(),
      fixed_value: Normalize.get(attrs, :fixed_value),
      fixed_value_size_bits: Normalize.get(attrs, :fixed_value_size_bits),
      array_size: Normalize.get(attrs, :array_size),
      array_size_ref: Normalize.get(attrs, :array_size_ref),
      include_condition: Normalize.nested(attrs, :include_condition, MatchCriteria),
      display_order: Normalize.get(attrs, :display_order),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp point_ref(%Point{point_id: point_id}), do: point_id
  defp point_ref(point_id) when is_binary(point_id), do: point_id
  defp point_ref(_other), do: nil

  defp packet_ref(%Packet{packet_id: packet_id}), do: packet_id
  defp packet_ref(packet_id) when is_binary(packet_id), do: packet_id
  defp packet_ref(_other), do: nil

  defp normalize_entry_kind(:point_ref), do: :point_ref
  defp normalize_entry_kind("point_ref"), do: :point_ref
  defp normalize_entry_kind(:fixed_value), do: :fixed_value
  defp normalize_entry_kind("fixed_value"), do: :fixed_value
  defp normalize_entry_kind(:nested_packet_ref), do: :nested_packet_ref
  defp normalize_entry_kind("nested_packet_ref"), do: :nested_packet_ref
  defp normalize_entry_kind(:array_point_ref), do: :array_point_ref
  defp normalize_entry_kind("array_point_ref"), do: :array_point_ref
  defp normalize_entry_kind(_other), do: :point_ref

  defp normalize_bit_offset_from(:packet_start), do: :packet_start
  defp normalize_bit_offset_from("packet_start"), do: :packet_start
  defp normalize_bit_offset_from(:previous_entry), do: :previous_entry
  defp normalize_bit_offset_from("previous_entry"), do: :previous_entry
  defp normalize_bit_offset_from(:base_packet_end), do: :base_packet_end
  defp normalize_bit_offset_from("base_packet_end"), do: :base_packet_end
  defp normalize_bit_offset_from(_other), do: :packet_start
end

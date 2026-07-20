defmodule Cadence.Catalog.Telemetry.Packet do
  @moduledoc """
  Canonical telemetry packet or container definition.
  """

  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Telemetry.{MatchCriteria, Normalize, PacketEntry, Provenance}

  @type byte_order :: :big_endian | :little_endian

  @type t :: %__MODULE__{
          packet_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          description: binary() | nil,
          short_description: binary() | nil,
          abstract: boolean(),
          base_packet_id: binary() | nil,
          apid: non_neg_integer() | nil,
          packet_type: non_neg_integer() | nil,
          byte_order: byte_order(),
          size_bits: pos_integer() | nil,
          max_size_bits: pos_integer() | nil,
          sync_pattern: binary() | nil,
          sync_pattern_offset_bits: non_neg_integer() | nil,
          expected_rate_hz: number() | nil,
          rate_tolerance_percent: number() | nil,
          match_criteria: MatchCriteria.t() | nil,
          entries: [PacketEntry.t()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :packet_id,
    :snapshot_id,
    :name,
    :description,
    :short_description,
    :base_packet_id,
    :apid,
    :packet_type,
    :size_bits,
    :max_size_bits,
    :sync_pattern,
    :sync_pattern_offset_bits,
    :expected_rate_hz,
    :rate_tolerance_percent,
    :match_criteria,
    :provenance,
    abstract: false,
    byte_order: :big_endian,
    entries: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      packet_id: Normalize.get(attrs, :packet_id, Ids.new("telemetry_packet")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      short_description: Normalize.get(attrs, :short_description),
      abstract: Normalize.get(attrs, :abstract, false),
      base_packet_id: Normalize.get(attrs, :base_packet_id),
      apid: Normalize.get(attrs, :apid),
      packet_type: Normalize.get(attrs, :packet_type),
      byte_order: Normalize.get(attrs, :byte_order, :big_endian) |> normalize_byte_order(),
      size_bits: Normalize.get(attrs, :size_bits),
      max_size_bits: Normalize.get(attrs, :max_size_bits),
      sync_pattern: Normalize.get(attrs, :sync_pattern),
      sync_pattern_offset_bits: Normalize.get(attrs, :sync_pattern_offset_bits),
      expected_rate_hz: Normalize.get(attrs, :expected_rate_hz),
      rate_tolerance_percent: Normalize.get(attrs, :rate_tolerance_percent),
      match_criteria: Normalize.nested(attrs, :match_criteria, MatchCriteria),
      entries: Normalize.nested_list(attrs, :entries, PacketEntry),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_byte_order(:big_endian), do: :big_endian
  defp normalize_byte_order("big_endian"), do: :big_endian
  defp normalize_byte_order(:little_endian), do: :little_endian
  defp normalize_byte_order("little_endian"), do: :little_endian
  defp normalize_byte_order(_other), do: :big_endian
end

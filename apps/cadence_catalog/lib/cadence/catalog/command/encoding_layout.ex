defmodule Cadence.Catalog.Command.EncodingLayout do
  @moduledoc """
  Canonical command uplink encoding layout.
  """

  alias Cadence.Catalog.Command.{EncodingEntry, Normalize, Provenance}
  alias Cadence.Catalog.Ids

  @type layout_kind :: :binary_container | :space_packet | :service_data_unit | :raw_payload
  @type byte_order :: :big_endian | :little_endian
  @type checksum_kind :: :crc16 | :crc32 | :checksum8 | :none | :custom

  @type t :: %__MODULE__{
          layout_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          description: binary() | nil,
          layout_kind: layout_kind(),
          base_layout_id: binary() | nil,
          byte_order: byte_order(),
          size_bits: pos_integer() | nil,
          max_size_bits: pos_integer() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          opcode_size_bits: pos_integer() | nil,
          checksum_kind: checksum_kind() | nil,
          entries: [EncodingEntry.t()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :layout_id,
    :snapshot_id,
    :name,
    :description,
    :base_layout_id,
    :size_bits,
    :max_size_bits,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    :opcode_size_bits,
    :checksum_kind,
    :provenance,
    layout_kind: :binary_container,
    byte_order: :big_endian,
    entries: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      layout_id: Normalize.get(attrs, :layout_id, Ids.new("command_layout")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      layout_kind:
        Normalize.get(attrs, :layout_kind, :binary_container) |> normalize_layout_kind(),
      base_layout_id: Normalize.get(attrs, :base_layout_id),
      byte_order: Normalize.get(attrs, :byte_order, :big_endian) |> normalize_byte_order(),
      size_bits: Normalize.get(attrs, :size_bits),
      max_size_bits: Normalize.get(attrs, :max_size_bits),
      apid: Normalize.get(attrs, :apid),
      service_type: Normalize.get(attrs, :service_type),
      service_subtype: Normalize.get(attrs, :service_subtype),
      opcode: Normalize.get(attrs, :opcode),
      opcode_size_bits: Normalize.get(attrs, :opcode_size_bits),
      checksum_kind: Normalize.get(attrs, :checksum_kind) |> normalize_checksum_kind(),
      entries: Normalize.nested_list(attrs, :entries, EncodingEntry),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_layout_kind(:binary_container), do: :binary_container
  defp normalize_layout_kind("binary_container"), do: :binary_container
  defp normalize_layout_kind(:space_packet), do: :space_packet
  defp normalize_layout_kind("space_packet"), do: :space_packet
  defp normalize_layout_kind(:service_data_unit), do: :service_data_unit
  defp normalize_layout_kind("service_data_unit"), do: :service_data_unit
  defp normalize_layout_kind(:raw_payload), do: :raw_payload
  defp normalize_layout_kind("raw_payload"), do: :raw_payload
  defp normalize_layout_kind(_other), do: :binary_container

  defp normalize_byte_order(:big_endian), do: :big_endian
  defp normalize_byte_order("big_endian"), do: :big_endian
  defp normalize_byte_order(:little_endian), do: :little_endian
  defp normalize_byte_order("little_endian"), do: :little_endian
  defp normalize_byte_order(_other), do: :big_endian

  defp normalize_checksum_kind(nil), do: nil
  defp normalize_checksum_kind(:crc16), do: :crc16
  defp normalize_checksum_kind("crc16"), do: :crc16
  defp normalize_checksum_kind(:crc32), do: :crc32
  defp normalize_checksum_kind("crc32"), do: :crc32
  defp normalize_checksum_kind(:checksum8), do: :checksum8
  defp normalize_checksum_kind("checksum8"), do: :checksum8
  defp normalize_checksum_kind(:none), do: :none
  defp normalize_checksum_kind("none"), do: :none
  defp normalize_checksum_kind(:custom), do: :custom
  defp normalize_checksum_kind("custom"), do: :custom
  defp normalize_checksum_kind(_other), do: nil
end

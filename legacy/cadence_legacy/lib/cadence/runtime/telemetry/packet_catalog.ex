defmodule Cadence.Runtime.Telemetry.PacketCatalog do
  @moduledoc """
  Builds packet catalogs from MissionDatabase containers.
  """

  @type catalog :: %{
          targets: map(),
          by_apid: map(),
          by_type: map()
        }

  @spec build_catalog(list(), list()) :: catalog()
  def build_catalog(containers, targets) when is_list(containers) and is_list(targets) do
    target_definition_sets =
      Enum.reduce(targets, %{}, fn target, acc ->
        identifier = Map.get(target, :identifier)
        target_id = Map.get(target, :id)
        name = Map.get(target, :name)
        definition_set_id = Map.get(target, :definition_set_id)

        if definition_set_id do
          acc
          |> maybe_put_target_key(identifier, definition_set_id)
          |> maybe_put_target_key(target_id, definition_set_id)
          |> maybe_put_target_key(name, definition_set_id)
        else
          acc
        end
      end)

    {by_apid, by_type} =
      Enum.reduce(containers, {%{}, %{}}, fn container, {apid_acc, type_acc} ->
        definition_set_id = Map.get(container, :definition_set_id)
        packet_map = build_packet_map_from_container(container)

        apid_acc =
          case Map.get(container, :apid) do
            apid when is_integer(apid) ->
              Map.put(apid_acc, {definition_set_id, apid}, packet_map)

            _ ->
              apid_acc
          end

        type_acc =
          case Map.get(container, :packet_type) do
            type_byte when is_integer(type_byte) ->
              Map.put(type_acc, {definition_set_id, type_byte}, packet_map)

            _ ->
              type_acc
          end

        {apid_acc, type_acc}
      end)

    %{
      targets: target_definition_sets,
      by_apid: by_apid,
      by_type: by_type
    }
  end

  @spec build_packet_map_from_container(map()) :: map()
  def build_packet_map_from_container(container) do
    items =
      container.container_entries
      |> Enum.filter(fn entry ->
        entry.entry_type == :parameter_ref and entry.parameter != nil
      end)
      |> Enum.sort_by(& &1.bit_offset)
      |> Enum.map(fn entry ->
        param = entry.parameter
        data_type = param.data_type
        encoding = data_type && data_type.encoding

        %{
          name: param.name,
          bit_offset: entry.bit_offset || 0,
          bit_size: encoding && encoding.size_in_bits,
          data_type: get_base_type_atom(data_type),
          endianness: get_endianness(encoding, container),
          description: param.description || param.short_description,
          conversion: build_conversion_from_calibrator(data_type)
        }
      end)

    field_specs =
      Enum.map(items, fn item ->
        %{
          name: item.name,
          bit_offset: item.bit_offset,
          bit_size: item.bit_size,
          data_type: item.data_type,
          endianness: item.endianness
        }
      end)

    items_by_name = Map.new(items, fn item -> {to_string(item.name), item} end)

    %{
      id: container.id,
      mission_id: container.mission_id,
      definition_set_id: container.definition_set_id,
      target_id: nil,
      name: container.name,
      type_byte: container.packet_type,
      apid: container.apid,
      description: container.description || container.short_description,
      items: items,
      items_by_name: items_by_name,
      field_specs: field_specs
    }
  end

  defp maybe_put_target_key(acc, key, definition_set_id) when is_binary(key) do
    Map.put(acc, key, definition_set_id)
  end

  defp maybe_put_target_key(acc, _key, _definition_set_id), do: acc

  defp normalize_endianness("big"), do: :big_endian
  defp normalize_endianness("little"), do: :little_endian
  defp normalize_endianness("big_endian"), do: :big_endian
  defp normalize_endianness("little_endian"), do: :little_endian
  defp normalize_endianness(nil), do: :big_endian
  defp normalize_endianness(atom) when is_atom(atom), do: atom

  defp get_endianness(nil, container), do: normalize_endianness(container.byte_order)

  defp get_endianness(%{byte_order: nil}, container),
    do: normalize_endianness(container.byte_order)

  defp get_endianness(%{byte_order: byte_order}, _container), do: normalize_endianness(byte_order)

  defp build_conversion_from_calibrator(nil), do: nil
  defp build_conversion_from_calibrator(%{default_calibrator: nil}), do: nil

  defp build_conversion_from_calibrator(%{default_calibrator: calibrator}) do
    calibrator
  end

  defp get_base_type_atom(nil), do: :uint

  defp get_base_type_atom(%{base_type: nil, encoding: encoding}),
    do: encoding_to_extractor_type(encoding)

  @base_type_map %{
    float: :float,
    string: :string,
    binary: :block,
    boolean: :uint,
    enumerated: :uint,
    aggregate: :block,
    array: :block,
    absolute_time: :uint,
    relative_time: :uint
  }

  defp get_base_type_atom(%{base_type: :integer, encoding: encoding}) do
    if encoding && encoding.signed, do: :int, else: :uint
  end

  defp get_base_type_atom(%{base_type: base_type}) do
    Map.get(@base_type_map, base_type, :uint)
  end

  defp encoding_to_extractor_type(nil), do: :uint
  defp encoding_to_extractor_type(%{encoding_type: :integer, signed: true}), do: :int
  defp encoding_to_extractor_type(%{encoding_type: :integer}), do: :uint
  defp encoding_to_extractor_type(%{encoding_type: :float}), do: :float
  defp encoding_to_extractor_type(%{encoding_type: :string}), do: :string
  defp encoding_to_extractor_type(%{encoding_type: :binary}), do: :block
  defp encoding_to_extractor_type(%{encoding_type: :boolean}), do: :uint
  defp encoding_to_extractor_type(_), do: :uint
end

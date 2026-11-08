defmodule Cadence.Runtime.ProtocolCheckpoint.Data do
  @moduledoc false
  alias CCSDS.Transport.COP1.FOP

  @max_bytes 2_097_152
  @max_items 16_384

  def encode(value) do
    document = pack(value, 0)
    if byte_size(Jason.encode!(document)) > @max_bytes, do: throw(:invalid_checkpoint_data)
    {:ok, document}
  rescue
    _ -> {:error, :invalid_checkpoint_data}
  catch
    :invalid_checkpoint_data -> {:error, :invalid_checkpoint_data}
  end

  def decode(document) do
    if byte_size(Jason.encode!(document)) > @max_bytes, do: throw(:invalid_checkpoint_data)
    {:ok, unpack(document, 0)}
  rescue
    _ -> {:error, :invalid_checkpoint_data}
  catch
    :invalid_checkpoint_data -> {:error, :invalid_checkpoint_data}
  end

  defp pack(_, depth) when depth > 32, do: throw(:invalid_checkpoint_data)
  defp pack(value, _) when is_nil(value) or is_boolean(value) or is_integer(value), do: value
  defp pack(value, _) when is_float(value), do: ["float", value]
  defp pack(value, _) when is_binary(value), do: ["bytes", Base.encode64(value)]
  defp pack(value, _) when is_atom(value), do: ["atom", Atom.to_string(value)]
  defp pack(%DateTime{} = value, _), do: ["datetime", DateTime.to_iso8601(value)]
  defp pack(%FOP{} = value, depth), do: ["cop1_fop_v1", pack(Map.from_struct(value), depth + 1)]
  defp pack(%_struct{}, _), do: throw(:invalid_checkpoint_data)

  defp pack(value, depth) when is_list(value) and length(value) <= @max_items,
    do: ["list", Enum.map(value, &pack(&1, depth + 1))]

  defp pack(value, depth) when is_tuple(value),
    do: ["tuple", pack(Tuple.to_list(value), depth + 1)]

  defp pack(value, depth) when is_map(value) and map_size(value) <= @max_items do
    pairs =
      Enum.map(value, fn {key, item} ->
        unless is_atom(key) or is_integer(key) or is_binary(key),
          do: throw(:invalid_checkpoint_data)

        [pack(key, depth + 1), pack(item, depth + 1)]
      end)

    ["map", Enum.sort(pairs)]
  end

  defp pack(_, _), do: throw(:invalid_checkpoint_data)

  defp unpack(_, depth) when depth > 32, do: throw(:invalid_checkpoint_data)
  defp unpack(value, _) when is_nil(value) or is_boolean(value) or is_integer(value), do: value
  defp unpack(["float", value], _) when is_float(value), do: value
  defp unpack(["bytes", value], _) when is_binary(value), do: Base.decode64!(value)
  # Existing atoms only: checkpoints cannot allocate atoms or instantiate arbitrary modules.
  defp unpack(["atom", value], _) when is_binary(value), do: String.to_existing_atom(value)

  defp unpack(["datetime", value], _) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end

  defp unpack(["cop1_fop_v1", fields], depth) do
    attrs = unpack(fields, depth + 1)
    true = MapSet.new(Map.keys(attrs)) == MapSet.new(Map.keys(Map.from_struct(%FOP{})))
    {:ok, state} = FOP.init(attrs)
    state
  end

  defp unpack(["list", values], depth) when is_list(values) and length(values) <= @max_items,
    do: Enum.map(values, &unpack(&1, depth + 1))

  defp unpack(["tuple", values], depth), do: values |> unpack(depth + 1) |> List.to_tuple()

  defp unpack(["map", pairs], depth) when is_list(pairs) and length(pairs) <= @max_items do
    decoded =
      Enum.map(pairs, fn [key, item] ->
        key = unpack(key, depth + 1)

        unless is_atom(key) or is_integer(key) or is_binary(key),
          do: throw(:invalid_checkpoint_data)

        {key, unpack(item, depth + 1)}
      end)

    result = Map.new(decoded)

    if map_size(result) != length(decoded) or Map.has_key?(result, :__struct__),
      do: throw(:invalid_checkpoint_data)

    result
  end

  defp unpack(_, _), do: throw(:invalid_checkpoint_data)
end

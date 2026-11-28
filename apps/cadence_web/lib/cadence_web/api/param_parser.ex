defmodule CadenceWeb.API.ParamParser do
  @moduledoc "Shared primitives for parsing product HTTP API parameters."

  @direction_values [:uplink, :downlink]

  def string_value(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  def optional_positive_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  def optional_datetime(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> datetime_from_value(value) |> wrap_datetime_result(key)
    end
  end

  def optional_integer(params, key) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value -> integer_from_value(value) |> wrap_integer_result(key)
    end
  end

  def positive_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> integer_from_value(value) |> ensure_positive_integer(key)
    end
  end

  def non_neg_integer(params, key, default) do
    case Map.get(params, key, default) do
      nil -> {:ok, default}
      value -> integer_from_value(value) |> ensure_non_neg_integer(key)
    end
  end

  def wrap_integer_result({:ok, integer}, _key), do: {:ok, integer}
  def wrap_integer_result(:error, key), do: {:error, {:invalid_param, key, :integer}}

  def wrap_datetime_result({:ok, datetime}, _key), do: {:ok, datetime}
  def wrap_datetime_result(:error, key), do: {:error, {:invalid_param, key, :datetime}}

  def ensure_positive_integer({:ok, integer}, _key) when integer > 0, do: {:ok, integer}

  def ensure_positive_integer(_result, key),
    do: {:error, {:invalid_param, key, :positive_integer}}

  def ensure_non_neg_integer({:ok, integer}, _key) when integer >= 0, do: {:ok, integer}
  def ensure_non_neg_integer(_result, key), do: {:error, {:invalid_param, key, :non_neg_integer}}

  def integer_from_value(value) when is_integer(value), do: {:ok, value}

  def integer_from_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  def integer_from_value(_value), do: :error

  def datetime_from_value(%DateTime{} = datetime), do: {:ok, datetime}

  def datetime_from_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> :error
    end
  end

  def datetime_from_value(_value), do: :error

  def optional_allowed_atom_param(params, key, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    parse_allowed_atom(Map.get(params, key), key, allowed)
  end

  def required_allowed_atom_param(params, key, allowed)
      when is_map(params) and is_binary(key) and is_list(allowed) do
    case Map.get(params, key) do
      nil -> {:error, {:invalid_param, key, :required}}
      value -> parse_allowed_atom(value, key, allowed)
    end
  end

  def parse_allowed_atom(nil, _key, _allowed), do: {:ok, nil}

  def parse_allowed_atom(value, key, allowed) when is_atom(value) do
    if Enum.member?(allowed, value) do
      {:ok, value}
    else
      {:error, {:invalid_param, key, :unknown_atom}}
    end
  end

  def parse_allowed_atom(value, key, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> {:error, {:invalid_param, key, :unknown_atom}}
      atom -> {:ok, atom}
    end
  end

  def parse_allowed_atom(_value, key, _allowed),
    do: {:error, {:invalid_param, key, :unknown_atom}}

  def direction(params) when is_map(params) do
    required_allowed_atom_param(params, "direction", @direction_values)
  end

  def optional_direction(params, key) when is_map(params) and is_binary(key) do
    optional_allowed_atom_param(params, key, @direction_values)
  end

  def map_value(params, key) do
    case Map.get(params, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  def required_packet_binary(params) when is_map(params) do
    packet_hex = string_value(params, "packet_hex")
    packet_base64 = string_value(params, "packet_base64")

    cond do
      is_binary(packet_hex) and is_binary(packet_base64) ->
        {:error, {:invalid_param, "packet_hex", :mutually_exclusive_with_packet_base64}}

      is_binary(packet_hex) ->
        decode_packet_hex(packet_hex)

      is_binary(packet_base64) ->
        decode_packet_base64(packet_base64)

      true ->
        {:error, {:invalid_param, "packet_hex_or_packet_base64", :required}}
    end
  end

  def required_frame_binary(params) when is_map(params) do
    frame_hex = string_value(params, "frame_hex")
    frame_base64 = string_value(params, "frame_base64")

    cond do
      is_binary(frame_hex) and is_binary(frame_base64) ->
        {:error, {:invalid_param, "frame_hex", :mutually_exclusive_with_frame_base64}}

      is_binary(frame_hex) ->
        decode_packet_hex(frame_hex)

      is_binary(frame_base64) ->
        decode_packet_base64(frame_base64)

      true ->
        {:error, {:invalid_param, "frame_hex_or_frame_base64", :required}}
    end
  end

  def decode_packet_hex(packet_hex) when is_binary(packet_hex) do
    normalized_hex =
      packet_hex
      |> String.replace(~r/[\s_]/u, "")
      |> String.replace_prefix("0x", "")
      |> String.replace_prefix("0X", "")

    case Base.decode16(normalized_hex, case: :mixed) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_hex", :hex}}
    end
  end

  def decode_packet_base64(packet_base64) when is_binary(packet_base64) do
    normalized_base64 = String.replace(packet_base64, ~r/\s+/u, "")

    case Base.decode64(normalized_base64) do
      {:ok, raw_packet} -> {:ok, raw_packet}
      :error -> {:error, {:invalid_param, "packet_base64", :base64}}
    end
  end

  def maybe_put_attr(map, _key, nil), do: map
  def maybe_put_attr(map, key, value), do: Map.put(map, key, value)

  def resolve_spacecraft_id(params, nil), do: {:ok, string_value(params, "spacecraft_id")}

  def resolve_spacecraft_id(params, scoped_spacecraft_id) when is_binary(scoped_spacecraft_id) do
    case string_value(params, "spacecraft_id") do
      nil -> {:ok, scoped_spacecraft_id}
      ^scoped_spacecraft_id -> {:ok, scoped_spacecraft_id}
      _other -> {:error, :scope_mismatch}
    end
  end
end

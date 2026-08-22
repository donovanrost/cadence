defmodule CCSDS.CFDP.Encoding do
  @moduledoc false

  @spec minimum_octets(non_neg_integer()) :: 1..8
  def minimum_octets(value) when is_integer(value) and value >= 0 do
    value
    |> :binary.encode_unsigned()
    |> byte_size()
    |> max(1)
  end

  @spec encode_uint(term(), 1..8, atom()) :: {:ok, binary()} | {:error, term()}
  def encode_uint(value, octets, field)
      when is_integer(value) and value >= 0 and octets in 1..8 do
    encoded = :binary.encode_unsigned(value)

    if byte_size(encoded) <= octets do
      {:ok, :binary.copy(<<0>>, octets - byte_size(encoded)) <> encoded}
    else
      {:error, {:field_exceeds_width, field, value, octets}}
    end
  end

  def encode_uint(value, _octets, field), do: {:error, {:invalid_field, field, value}}

  @spec decode_uint(binary(), pos_integer(), atom()) ::
          {:ok, non_neg_integer(), binary()} | {:error, term()}
  def decode_uint(binary, octets, field)
      when is_binary(binary) and is_integer(octets) and octets > 0 do
    if byte_size(binary) >= octets do
      <<encoded::binary-size(^octets), rest::binary>> = binary
      {:ok, :binary.decode_unsigned(encoded), rest}
    else
      {:error, {:truncated_field, field, octets, byte_size(binary)}}
    end
  end

  @spec encode_lv(term(), atom()) :: {:ok, binary()} | {:error, term()}
  def encode_lv(value, _field) when is_binary(value) and byte_size(value) <= 0xFF,
    do: {:ok, <<byte_size(value), value::binary>>}

  def encode_lv(value, field) when is_binary(value),
    do: {:error, {:field_exceeds_width, field, byte_size(value), 0xFF}}

  def encode_lv(value, field), do: {:error, {:invalid_field, field, value}}

  @spec decode_lv(binary(), atom()) :: {:ok, binary(), binary()} | {:error, term()}
  def decode_lv(<<length, rest::binary>>, field) do
    if byte_size(rest) >= length do
      <<value::binary-size(^length), trailing::binary>> = rest
      {:ok, value, trailing}
    else
      {:error, {:truncated_lv, field, length, byte_size(rest)}}
    end
  end

  def decode_lv(binary, field), do: {:error, {:truncated_lv_length, field, byte_size(binary)}}

  @spec validate_range(term(), integer(), integer(), atom()) :: :ok | {:error, term()}
  def validate_range(value, minimum, maximum, _field)
      when is_integer(value) and value >= minimum and value <= maximum,
      do: :ok

  def validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  @spec require_empty(binary(), atom()) :: :ok | {:error, term()}
  def require_empty(<<>>, _context), do: :ok

  def require_empty(rest, context),
    do: {:error, {:trailing_value_bytes, context, byte_size(rest)}}
end

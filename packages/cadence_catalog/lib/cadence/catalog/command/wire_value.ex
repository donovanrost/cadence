defmodule Cadence.Catalog.Command.WireValue do
  @moduledoc false
  alias Cadence.Catalog.Command.Compiler.ArgumentSpec
  alias Cadence.Catalog.Command.TypeEncoding

  @max_float32 3.4_028_234_663_852_886e38
  @max_float64 1.7_976_931_348_623_157e308

  def supported?(%ArgumentSpec{base_type: type, encoding: %TypeEncoding{} = encoding}) do
    encoding.byte_order in [:big_endian, :little_endian] and
      is_boolean(encoding.signed) and is_nil(encoding.dynamic_size_ref) and
      encoding.dynamic_size_adjustment == %{} and supported_type?(type, encoding)
  end

  def supported?(_), do: false

  def valid?(%ArgumentSpec{base_type: type, encoding: encoding}, value)
      when type in [:integer, :enumerated] do
    case integer(value, type) do
      {:ok, number} -> TypeEncoding.integer_fits?(number, encoding.size_bits, encoding.signed)
      _ -> false
    end
  end

  def valid?(%ArgumentSpec{base_type: :boolean}, value), do: is_boolean(value)

  def valid?(%ArgumentSpec{base_type: :float, encoding: encoding}, value) do
    max_value = if encoding.size_bits == 32, do: @max_float32, else: @max_float64
    is_number(value) and value >= -max_value and value <= max_value
  end

  def valid?(%ArgumentSpec{base_type: :binary, encoding: encoding}, value),
    do: is_binary(value) and byte_size(value) * 8 <= encoding.size_bits

  def valid?(%ArgumentSpec{base_type: :string, encoding: encoding}, value) do
    is_binary(value) and String.valid?(value) and string_fits?(value, encoding) and
      charset_fits?(value, encoding.charset)
  end

  def valid?(_, _), do: false

  def fixed?(value, bits) when is_integer(value),
    do: TypeEncoding.integer_fits?(value, bits, value < 0)

  def fixed?(value, _bits) when is_boolean(value), do: true

  def fixed?(value, bits) when is_binary(value),
    do: rem(bits, 8) == 0 and byte_size(value) * 8 <= bits

  def fixed?(_, _), do: false

  defp supported_type?(type, encoding) when type in [:integer, :enumerated] do
    encoding.encoding_type in [nil, :integer] and
      encoding.integer_encoding in [:unsigned, :twos_complement] and
      (encoding.integer_encoding != :twos_complement or encoding.signed) and
      byte_aligned_little_endian?(encoding)
  end

  defp supported_type?(:boolean, encoding),
    do:
      encoding.encoding_type in [nil, :integer, :boolean] and not encoding.signed and
        encoding.integer_encoding == :unsigned and byte_aligned_little_endian?(encoding)

  defp supported_type?(:float, encoding),
    do:
      encoding.encoding_type in [nil, :float] and encoding.size_bits in [32, 64] and
        encoding.float_encoding in [nil, :ieee754]

  defp supported_type?(:binary, encoding),
    do: encoding.encoding_type in [nil, :binary] and rem(encoding.size_bits, 8) == 0

  defp supported_type?(:string, encoding),
    do:
      encoding.encoding_type in [nil, :string] and rem(encoding.size_bits, 8) == 0 and
        encoding.string_termination in [nil, :fixed_length, :null] and
        is_nil(encoding.string_length_prefix_bits) and
        encoding.charset in [nil, "UTF-8", "UTF8", "utf-8", "utf8", "ASCII", "US-ASCII"]

  defp supported_type?(_, _), do: false

  defp byte_aligned_little_endian?(encoding),
    do: encoding.byte_order != :little_endian or rem(encoding.size_bits, 8) == 0

  defp integer(value, _) when is_integer(value), do: {:ok, value}

  defp integer(value, :enumerated) when is_binary(value) and byte_size(value) <= 4096 do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp integer(_, _), do: :error

  defp string_fits?(value, %{string_termination: :null, size_bits: bits}),
    do: byte_size(value) * 8 < bits and not String.contains?(value, <<0>>)

  defp string_fits?(value, encoding), do: byte_size(value) * 8 <= encoding.size_bits

  defp charset_fits?(value, charset) when charset in ["ASCII", "US-ASCII"],
    do: ascii?(value)

  defp charset_fits?(_, _), do: true

  defp ascii?(<<>>), do: true
  defp ascii?(<<byte, rest::binary>>) when byte < 128, do: ascii?(rest)
  defp ascii?(_), do: false
end

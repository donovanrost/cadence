defmodule Cadence.Catalog.Command.Decoder do
  @moduledoc """
  Decodes command payloads using portable compiled runtime definitions.

  Trailing transport padding is ignored; only the opcode and compiled layout
  bits are consumed.
  """

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.Invocation

  @type decoded :: %{
          runtime_definition: RuntimeDefinition.t(),
          arguments: map()
        }

  @spec decode([RuntimeDefinition.t()], binary()) :: {:ok, decoded()} | {:error, term()}
  def decode(runtime_definitions, payload)
      when is_list(runtime_definitions) and is_binary(payload) do
    matches = Enum.filter(runtime_definitions, &opcode_matches?(&1, payload))

    case matches do
      [] ->
        {:error, :command_opcode_not_found}

      [%RuntimeDefinition{} = runtime_definition] ->
        decode_runtime_definition(runtime_definition, payload)

      definitions ->
        {:error, {:ambiguous_command_opcode, Enum.map(definitions, & &1.command_id)}}
    end
  end

  defp opcode_matches?(
         %RuntimeDefinition{opcode: opcode, opcode_size_bits: size_bits},
         payload
       )
       when is_integer(opcode) and is_integer(size_bits) and size_bits > 0 and
              bit_size(payload) >= size_bits do
    <<candidate::unsigned-big-integer-size(^size_bits), _rest::bitstring>> = payload
    candidate == opcode
  end

  defp opcode_matches?(_runtime_definition, _payload), do: false

  defp decode_runtime_definition(%RuntimeDefinition{} = runtime_definition, payload) do
    opcode_size_bits = runtime_definition.opcode_size_bits || 0

    if bit_size(payload) >= opcode_size_bits do
      <<_opcode::bitstring-size(^opcode_size_bits), layout::bitstring>> = payload

      with {:ok, decoded_arguments} <- decode_arguments(runtime_definition, layout),
           {:ok, resolved_arguments} <-
             Invocation.resolve(runtime_definition, decoded_arguments) do
        {:ok,
         %{
           runtime_definition: runtime_definition,
           arguments: resolved_arguments
         }}
      end
    else
      {:error, {:command_payload_too_short, runtime_definition.command_id}}
    end
  end

  defp decode_arguments(%RuntimeDefinition{} = runtime_definition, layout) do
    specs_by_id = Map.new(runtime_definition.argument_specs, &{&1.argument_id, &1})

    runtime_definition.encoding_steps
    |> Enum.filter(&(&1.step_kind == :argument_ref))
    |> Enum.reduce_while({:ok, %{}}, fn %EncodingStep{} = step, {:ok, acc} ->
      with {:ok, %ArgumentSpec{} = spec} <- Map.fetch(specs_by_id, step.argument_id),
           {:ok, encoded_value} <- extract_bits(layout, step),
           {:ok, value} <- decode_value(encoded_value, spec) do
        {:cont, {:ok, Map.put(acc, spec.name, value)}}
      else
        :error -> {:halt, {:error, {:command_argument_spec_not_found, step.argument_id}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp extract_bits(layout, %EncodingStep{} = step) do
    required_bits = step.bit_offset + step.size_bits
    bit_offset = step.bit_offset
    size_bits = step.size_bits

    if bit_size(layout) >= required_bits do
      <<_prefix::bitstring-size(^bit_offset), value::bitstring-size(^size_bits),
        _rest::bitstring>> = layout

      {:ok, value}
    else
      {:error, {:command_payload_too_short, step.argument_id}}
    end
  end

  defp decode_value(value, %ArgumentSpec{base_type: base_type} = spec)
       when base_type in [:integer, :enumerated] do
    decode_integer(value, spec.encoding.signed, spec.encoding.byte_order)
  end

  defp decode_value(value, %ArgumentSpec{base_type: :float} = spec) do
    decode_float(value, spec.encoding.byte_order)
  end

  defp decode_value(value, %ArgumentSpec{base_type: :boolean}) do
    with {:ok, integer} <- decode_integer(value, false, :big_endian) do
      {:ok, integer != 0}
    end
  end

  defp decode_value(value, %ArgumentSpec{base_type: :string}) when is_binary(value) do
    {:ok, String.trim_trailing(value, <<0>>)}
  end

  defp decode_value(value, %ArgumentSpec{base_type: :binary}) when is_binary(value),
    do: {:ok, value}

  defp decode_value(_value, %ArgumentSpec{} = spec),
    do: {:error, {:unsupported_command_argument_type, spec.name, spec.base_type}}

  defp decode_integer(value, signed?, :little_endian) do
    size_bits = bit_size(value)

    if rem(size_bits, 8) == 0 do
      if signed? do
        <<integer::signed-little-integer-size(^size_bits)>> = value
        {:ok, integer}
      else
        <<integer::unsigned-little-integer-size(^size_bits)>> = value
        {:ok, integer}
      end
    else
      {:error, {:unsupported_little_endian_command_size, size_bits}}
    end
  end

  defp decode_integer(value, signed?, _byte_order) do
    size_bits = bit_size(value)

    if signed? do
      <<integer::signed-big-integer-size(^size_bits)>> = value
      {:ok, integer}
    else
      <<integer::unsigned-big-integer-size(^size_bits)>> = value
      {:ok, integer}
    end
  end

  defp decode_float(<<value::float-big-32>>, :big_endian), do: {:ok, value}
  defp decode_float(<<value::float-little-32>>, :little_endian), do: {:ok, value}
  defp decode_float(<<value::float-big-64>>, :big_endian), do: {:ok, value}
  defp decode_float(<<value::float-little-64>>, :little_endian), do: {:ok, value}

  defp decode_float(value, byte_order),
    do: {:error, {:unsupported_command_float_encoding, bit_size(value), byte_order}}
end

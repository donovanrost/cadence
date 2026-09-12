defmodule Cadence.Catalog.Command.WireEncoding do
  @moduledoc """
  Admission for the fixed-layout command wire format supported by Cadence.

  Validation precedes allocation. The complete padded output is limited to 1 MiB,
  with at most 4,096 argument specifications and encoding steps. Model-declared
  maximum sizes further constrain the layout; they cannot increase this bound.
  """
  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.{TypeEncoding, WireValue}

  @max_bits 8 * 1_048_576
  @max_entries 4096

  def definition(%RuntimeDefinition{} = definition) do
    with true <-
           finite_list?(definition.argument_specs) and finite_list?(definition.encoding_steps),
         true <- Enum.all?(definition.argument_specs, &valid_spec?/1),
         true <- unique?(definition.argument_specs, :argument_id),
         true <- unique?(definition.argument_specs, :name),
         true <- Enum.all?(definition.encoding_steps, &valid_step?/1),
         total = layout_bits(definition),
         true <- is_integer(total) and total in 0..@max_bits,
         true <- valid_maximum?(definition.max_size_bits, total),
         true <- valid_opcode?(definition, total),
         true <- valid_steps?(definition, total) do
      :ok
    else
      _ -> {:error, :unsupported_command_wire_definition}
    end
  end

  def definition(_), do: {:error, :unsupported_command_wire_definition}

  def validate(definition, values) when is_map(values) do
    with :ok <- definition(definition),
         :ok <- known_values(definition, values) do
      validate_values(definition, values)
    end
  end

  def validate(_, _), do: {:error, :invalid_command_wire_values}

  def layout_bits(%RuntimeDefinition{size_bits: bits}) when not is_nil(bits), do: bits

  def layout_bits(definition),
    do: Enum.reduce(definition.encoding_steps, 0, &max(&1.bit_offset + &1.size_bits, &2))

  defp known_values(definition, values) do
    specs = Map.new(definition.argument_specs, &{&1.name, &1})

    if map_size(values) <= @max_entries and Enum.all?(values, &known_value?(&1, specs)),
      do: :ok,
      else: {:error, :invalid_command_wire_values}
  end

  defp known_value?({name, value}, specs) do
    case Map.fetch(specs, name) do
      {:ok, spec} ->
        WireValue.valid?(spec, value) and (is_nil(spec.fixed_value) or value == spec.fixed_value)

      _ ->
        false
    end
  end

  defp validate_values(definition, values) do
    specs = Map.new(definition.argument_specs, &{&1.argument_id, &1})

    Enum.reduce_while(definition.encoding_steps, :ok, fn step, :ok ->
      case validate_step_value(step, specs, values) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_step_value(%{step_kind: :fixed_value}, _, _), do: :ok

  defp validate_step_value(step, specs, values) do
    spec = Map.fetch!(specs, step.argument_id)

    with {:ok, value} <- Map.fetch(values, spec.name),
         true <- WireValue.valid?(spec, value),
         true <- is_nil(spec.fixed_value) or value == spec.fixed_value do
      :ok
    else
      _ -> {:error, {:invalid_command_wire_value, spec.name}}
    end
  end

  defp valid_spec?(%ArgumentSpec{encoding: %TypeEncoding{size_bits: bits}} = spec) do
    is_binary(spec.argument_id) and spec.argument_id != "" and is_binary(spec.name) and
      spec.name != "" and width?(bits) and WireValue.supported?(spec) and
      default_valid?(spec, spec.default_value) and default_valid?(spec, spec.fixed_value)
  end

  defp valid_spec?(_), do: false
  defp default_valid?(_, nil), do: true
  defp default_valid?(spec, value), do: WireValue.valid?(spec, value)

  defp valid_step?(%EncodingStep{
         bit_offset: offset,
         size_bits: bits,
         bit_offset_from: :layout_start
       }),
       do: is_integer(offset) and offset in 0..@max_bits and width?(bits)

  defp valid_step?(_), do: false

  defp valid_steps?(definition, total) do
    specs = Map.new(definition.argument_specs, &{&1.argument_id, &1})

    definition.encoding_steps
    |> Enum.sort_by(& &1.bit_offset)
    |> Enum.reduce_while(0, fn step, previous_end ->
      step_end = step.bit_offset + step.size_bits

      if step.bit_offset >= previous_end and step_end <= total and step_matches?(step, specs),
        do: {:cont, step_end},
        else: {:halt, :invalid}
    end)
    |> is_integer()
  end

  defp step_matches?(%{step_kind: :fixed_value} = step, _),
    do: WireValue.fixed?(step.fixed_value, step.size_bits)

  defp step_matches?(%{step_kind: :argument_ref} = step, specs) do
    case Map.fetch(specs, step.argument_id) do
      {:ok, spec} -> spec.encoding.size_bits == step.size_bits
      _ -> false
    end
  end

  defp step_matches?(_, _), do: false

  defp valid_opcode?(%{opcode: nil}, total), do: padded_bits(total) <= @max_bits

  defp valid_opcode?(definition, total) do
    bits = definition.opcode_size_bits || 8

    width?(bits) and TypeEncoding.integer_fits?(definition.opcode, bits, false) and
      padded_bits(padded_bits(total) + bits) <= @max_bits
  end

  defp valid_maximum?(nil, _), do: true

  defp valid_maximum?(maximum, total),
    do: is_integer(maximum) and maximum > 0 and total <= maximum

  defp width?(bits), do: is_integer(bits) and bits in 1..@max_bits
  defp finite_list?(values), do: is_list(values) and length(values) <= @max_entries

  defp unique?(values, key),
    do: values |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq() |> length() == length(values)

  defp padded_bits(bits), do: div(bits + 7, 8) * 8
end

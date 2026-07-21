defmodule Cadence.Catalog.Command.Invocation do
  @moduledoc """
  Resolves and validates argument values against a compiled command definition.

  The result is keyed by argument name so it can be passed directly to command
  encoders and state-effect consumers.
  """

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, RuntimeDefinition}

  @spec resolve(RuntimeDefinition.t(), map()) :: {:ok, map()} | {:error, term()}
  def resolve(%RuntimeDefinition{} = runtime_definition, argument_values)
      when is_map(argument_values) do
    normalized_values = normalize_argument_values(argument_values)

    argument_specs_by_name =
      Map.new(runtime_definition.argument_specs, fn %ArgumentSpec{} = argument_spec ->
        {argument_spec.name, argument_spec}
      end)

    unknown_arguments =
      normalized_values
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(argument_specs_by_name, &1))

    if unknown_arguments == [] do
      resolve_specs(runtime_definition.argument_specs, normalized_values)
    else
      {:error, {:unknown_command_arguments, Enum.sort(unknown_arguments)}}
    end
  end

  def resolve(%RuntimeDefinition{} = runtime_definition, _argument_values),
    do: resolve(runtime_definition, %{})

  defp resolve_specs(argument_specs, normalized_values) do
    Enum.reduce_while(argument_specs, {:ok, %{}}, fn %ArgumentSpec{} = spec, {:ok, acc} ->
      case resolve_argument_value(spec, normalized_values) do
        {:ok, :skip} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, spec.name, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_argument_value(%ArgumentSpec{} = spec, normalized_values) do
    case Map.fetch(normalized_values, spec.name) do
      {:ok, provided_value} -> resolve_provided_argument_value(spec, provided_value)
      :error -> resolve_missing_argument_value(spec)
    end
  end

  defp resolve_provided_argument_value(%ArgumentSpec{} = spec, provided_value) do
    cond do
      not is_nil(spec.fixed_value) and provided_value != spec.fixed_value ->
        {:error,
         {:command_argument_fixed_value_conflict, spec.name, spec.fixed_value, provided_value}}

      not valid_argument_value?(provided_value, spec) ->
        {:error, {:invalid_command_argument_type, spec.name, spec.base_type, provided_value}}

      not is_nil(spec.fixed_value) ->
        {:ok, spec.fixed_value}

      true ->
        {:ok, provided_value}
    end
  end

  defp resolve_missing_argument_value(%ArgumentSpec{} = spec) do
    cond do
      not is_nil(spec.fixed_value) -> {:ok, spec.fixed_value}
      not is_nil(spec.default_value) -> {:ok, spec.default_value}
      spec.required -> {:error, {:missing_required_command_argument, spec.name}}
      true -> {:ok, :skip}
    end
  end

  defp valid_argument_value?(value, %ArgumentSpec{base_type: :integer}), do: is_integer(value)
  defp valid_argument_value?(value, %ArgumentSpec{base_type: :float}), do: is_number(value)
  defp valid_argument_value?(value, %ArgumentSpec{base_type: :string}), do: is_binary(value)
  defp valid_argument_value?(value, %ArgumentSpec{base_type: :binary}), do: is_binary(value)
  defp valid_argument_value?(value, %ArgumentSpec{base_type: :boolean}), do: is_boolean(value)

  defp valid_argument_value?(value, %ArgumentSpec{base_type: :enumerated}),
    do: is_integer(value) or is_binary(value)

  defp valid_argument_value?(_value, _argument_spec), do: false

  defp normalize_argument_values(argument_values) do
    Map.new(argument_values, fn {key, value} -> {to_string(key), value} end)
  end
end

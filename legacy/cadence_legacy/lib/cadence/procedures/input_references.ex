defmodule Cadence.Procedures.InputReferences do
  @moduledoc """
  Parses and validates input references in procedure step configurations.

  Input references use the syntax `${input.name}` where `name` is the name of
  an input defined in the procedure's parameters_schema.

  ## Examples

      iex> extract_references("Send ${input.command_name} to ${input.target}")
      ["command_name", "target"]

      iex> interpolate("Value is ${input.threshold}", %{"threshold" => 42})
      {:ok, "Value is 42"}

  """

  @input_pattern ~r/\$\{input\.([a-z_][a-z0-9_]*)\}/

  @doc """
  Extracts all input reference names from a string.

  Returns a list of input names (without the `${input.}` wrapper).
  """
  @spec extract_references(String.t()) :: [String.t()]
  def extract_references(string) when is_binary(string) do
    @input_pattern
    |> Regex.scan(string)
    |> Enum.map(fn [_full, name] -> name end)
    |> Enum.uniq()
  end

  def extract_references(_), do: []

  @doc """
  Extracts all input references from a step configuration map.

  Recursively walks the map/list structure and extracts references from all string values.
  """
  @spec extract_references_from_step(map()) :: [String.t()]
  def extract_references_from_step(step) when is_map(step) do
    step
    |> extract_from_value()
    |> Enum.uniq()
  end

  defp extract_from_value(map) when is_map(map) do
    Enum.flat_map(map, fn {_k, v} -> extract_from_value(v) end)
  end

  defp extract_from_value(list) when is_list(list) do
    Enum.flat_map(list, &extract_from_value/1)
  end

  defp extract_from_value(string) when is_binary(string) do
    extract_references(string)
  end

  defp extract_from_value(_), do: []

  @doc """
  Extracts all input references from all steps in a procedure.

  Returns a map of step_name => [input_names].
  """
  @spec extract_references_from_steps(map()) :: %{String.t() => [String.t()]}
  def extract_references_from_steps(steps) when is_map(steps) do
    steps
    |> Enum.map(fn {step_name, step_config} ->
      {step_name, extract_references_from_step(step_config)}
    end)
    |> Enum.reject(fn {_name, refs} -> refs == [] end)
    |> Map.new()
  end

  @doc """
  Validates that all input references in steps point to defined inputs.

  Returns :ok if all references are valid, or {:error, errors} with a list of
  error tuples {step_name, undefined_input_name}.
  """
  @spec validate_references(map(), map()) :: :ok | {:error, [{String.t(), String.t()}]}
  def validate_references(steps, inputs) when is_map(steps) and is_map(inputs) do
    defined_inputs = Map.keys(inputs) |> MapSet.new()

    errors =
      steps
      |> extract_references_from_steps()
      |> Enum.flat_map(fn {step_name, refs} ->
        refs
        |> Enum.reject(&MapSet.member?(defined_inputs, &1))
        |> Enum.map(&{step_name, &1})
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Interpolates input values into a string.

  Replaces all `${input.name}` patterns with the corresponding value from the
  inputs map. Values are converted to strings.

  Returns {:ok, result} or {:error, :missing_input, name} if an input is not found.
  """
  @spec interpolate(String.t(), map()) :: {:ok, String.t()} | {:error, :missing_input, String.t()}
  def interpolate(string, inputs) when is_binary(string) and is_map(inputs) do
    refs = extract_references(string)
    missing = Enum.find(refs, fn name -> not Map.has_key?(inputs, name) end)

    case missing do
      nil ->
        result =
          Regex.replace(@input_pattern, string, fn _full, name ->
            inputs |> Map.get(name) |> to_string()
          end)

        {:ok, result}

      name ->
        {:error, :missing_input, name}
    end
  end

  def interpolate(value, _inputs), do: {:ok, value}

  @doc """
  Interpolates input values into a step configuration map.

  Recursively walks the structure and interpolates all string values.
  Non-string values are left unchanged.
  """
  @spec interpolate_step(map(), map()) :: {:ok, map()} | {:error, :missing_input, String.t()}
  def interpolate_step(step, inputs) when is_map(step) and is_map(inputs) do
    interpolate_value(step, inputs)
  end

  defp interpolate_value(map, inputs) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case interpolate_value(v, inputs) do
        {:ok, new_v} -> {:cont, {:ok, Map.put(acc, k, new_v)}}
        error -> {:halt, error}
      end
    end)
  end

  defp interpolate_value(list, inputs) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn v, {:ok, acc} ->
      case interpolate_value(v, inputs) do
        {:ok, new_v} -> {:cont, {:ok, acc ++ [new_v]}}
        error -> {:halt, error}
      end
    end)
  end

  defp interpolate_value(string, inputs) when is_binary(string) do
    interpolate(string, inputs)
  end

  defp interpolate_value(value, _inputs), do: {:ok, value}

  @doc """
  Checks if a string contains any input references.
  """
  @spec has_references?(String.t()) :: boolean()
  def has_references?(string) when is_binary(string) do
    Regex.match?(@input_pattern, string)
  end

  def has_references?(_), do: false
end

defmodule Cadence.Catalog.MissionModel.ArgumentCriteria do
  @moduledoc """
  Lowers `value_from_argument` on verifier criteria: the argument name becomes the argument's id,
  and its type must match what the comparison reads from the subject parameter.

  Types are compared by class (numeric, boolean, string, binary). A calibrated comparison
  (`use_calibrated`, the default) reads the parameter's engineering value, which is a label when
  the parameter has enumerations (a state table): compare the raw value for those. An enumerated
  argument is numeric: the encoder sends its integer code (a request may carry "3" or 3, never a
  label), and the runtime resolves it to that integer.
  """

  alias Cadence.Catalog.MissionModel.Reference

  @type reason ::
          {:verifier_argument_not_found, binary(), binary()}
          | {:verifier_argument_type_mismatch, binary(), binary(), atom(), atom()}
          | {:verifier_argument_subject_not_parameter, binary(), term()}

  @doc "Binds `value_from_argument` in `criteria` (and nested conditions) to `argument_specs`."
  @spec bind(map() | nil, [map()], map(), binary()) :: {:ok, map() | nil} | {:error, reason()}
  def bind(nil, _argument_specs, _index, _verifier_id), do: {:ok, nil}

  def bind(criteria, argument_specs, index, verifier_id) when is_map(criteria) do
    with {:ok, criteria} <- own(criteria, argument_specs, index, verifier_id),
         {:ok, conditions} <- conditions(criteria, argument_specs, index, verifier_id) do
      {:ok, put(criteria, :conditions, conditions)}
    end
  end

  defp conditions(criteria, argument_specs, index, verifier_id) do
    criteria
    |> get(:conditions)
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn condition, {:ok, acc} ->
      case bind(condition, argument_specs, index, verifier_id) do
        {:ok, bound} -> {:cont, {:ok, acc ++ [bound]}}
        error -> {:halt, error}
      end
    end)
  end

  defp own(criteria, argument_specs, index, verifier_id) do
    case get(criteria, :value_from_argument) do
      name when is_binary(name) ->
        with {:ok, spec} <- argument(argument_specs, name, verifier_id),
             :ok <- same_type(criteria, spec, index, verifier_id) do
          {:ok, put(criteria, :value_from_argument, spec.argument_id)}
        end

      _none ->
        {:ok, criteria}
    end
  end

  # By name (the YAML importer) or by id (already lowered sources).
  defp argument(argument_specs, name, verifier_id) do
    case Enum.find(argument_specs, &(&1.name == name or &1.argument_id == name)) do
      nil -> {:error, {:verifier_argument_not_found, verifier_id, name}}
      spec -> {:ok, spec}
    end
  end

  defp same_type(criteria, spec, index, verifier_id) do
    with {:ok, type} <- subject_type(get(criteria, :subject_ref), index, verifier_id) do
      read = read_class(type, get(criteria, :use_calibrated) != false)
      sent = argument_class(spec.base_type)

      if sent == read and sent != :unsupported,
        do: :ok,
        else: {:error, {:verifier_argument_type_mismatch, verifier_id, spec.name, sent, read}}
    end
  end

  defp subject_type(subject_ref, index, verifier_id) do
    with {:ok, %{kind: :parameter} = parameter} <- Map.fetch(index, subject_ref),
         %Reference{resolved_id: type_id} when is_binary(type_id) <-
           Enum.find(parameter.references, &(&1.role == :type)),
         {:ok, type} <- Map.fetch(index, type_id) do
      {:ok, type}
    else
      _not_a_parameter ->
        {:error, {:verifier_argument_subject_not_parameter, verifier_id, subject_ref}}
    end
  end

  defp read_class(type, calibrated?) do
    enumerated? = List.wrap(get(type.definition, :enumerations)) != []

    if calibrated? and enumerated?,
      do: :string,
      else: base_class(get(type.definition, :base_type))
  end

  defp argument_class(base_type), do: base_class(base_type)

  defp base_class(kind)
       when kind in [:integer, :float, :enumerated, "integer", "float", "enumerated"],
       do: :numeric

  defp base_class(kind) when kind in [:boolean, "boolean"], do: :boolean
  defp base_class(kind) when kind in [:string, "string"], do: :string
  defp base_class(kind) when kind in [:binary, "binary"], do: :binary
  defp base_class(_kind), do: :unsupported

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp put(map, key, value) do
    if Map.has_key?(map, Atom.to_string(key)),
      do: Map.put(map, Atom.to_string(key), value),
      else: Map.put(map, key, value)
  end
end

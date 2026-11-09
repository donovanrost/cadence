defmodule Cadence.Reads.CatalogDeclarations do
  @moduledoc """
  Display facts resolved from the active Mission Model revision's catalog
  declarations: the engineering unit of a telemetry parameter, and the valid
  range and unit of a command argument.

  Lowered runtime plans don't always carry these. XTCE import attaches a
  parameter's unit to its *parameter type*, which lowering doesn't follow, so
  this read follows `parameter -> type -> unit` itself.
  """

  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis

  @type declarations :: %{binary() => map()}

  @doc "Declarations of the mission's active revision, keyed by semantic id (`%{}` when none is active)."
  @spec active(binary(), binary()) :: declarations()
  def active(organization_id, mission_id) do
    with revision_id when is_binary(revision_id) <-
           ActiveBasis.active_revision_id(organization_id, mission_id),
         {:ok, revision} <- MissionModels.fetch_revision(organization_id, mission_id, revision_id) do
      revision.declarations || %{}
    else
      _none -> %{}
    end
  end

  @doc "The unit symbol of a parameter, from its own unit reference or its type's."
  @spec parameter_unit(declarations(), binary() | nil) :: binary() | nil
  def parameter_unit(declarations, parameter_id) do
    with %{} = parameter <- Map.get(declarations, parameter_id || "") do
      unit_symbol(declarations, parameter) ||
        declarations |> referenced(parameter, :type) |> then(&unit_symbol(declarations, &1))
    end
  end

  @doc "Valid range (`%{minimum, maximum}` or `nil`) and unit of a command argument, from its type."
  @spec argument_facts(declarations(), binary()) :: %{
          valid_range: map() | nil,
          unit: binary() | nil
        }
  def argument_facts(declarations, argument_id) do
    argument = Map.get(declarations, argument_id)
    type = argument && referenced(declarations, argument, :type)
    definition = (type && field(type, :definition)) || %{}

    %{
      valid_range: valid_range(field(definition, :valid_range)),
      unit:
        blank_to_nil(field(definition, :display_unit)) ||
          (argument && unit_symbol(declarations, argument)) ||
          (type && unit_symbol(declarations, type))
    }
  end

  defp unit_symbol(_declarations, nil), do: nil

  defp unit_symbol(declarations, owner) do
    case referenced(declarations, owner, :unit) do
      nil -> nil
      unit -> blank_to_nil(field(field(unit, :definition) || %{}, :symbol)) || field(unit, :name)
    end
  end

  defp referenced(declarations, owner, role) do
    owner
    |> field(:references)
    |> List.wrap()
    |> Enum.find(&(to_string(field(&1, :role)) == Atom.to_string(role)))
    |> case do
      nil -> nil
      reference -> Map.get(declarations, field(reference, :resolved_id) || "")
    end
  end

  defp valid_range(%{} = range) do
    case {number_or_nil(field(range, :minimum)), number_or_nil(field(range, :maximum))} do
      {nil, nil} -> nil
      {minimum, maximum} -> %{minimum: minimum, maximum: maximum}
    end
  end

  defp valid_range(_range), do: nil

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_value), do: nil

  # Declarations decode as structs with atom keys, but nested definitions may
  # carry string keys after the JSON round trip.
  defp field(%{} = map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_other, _key), do: nil

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end

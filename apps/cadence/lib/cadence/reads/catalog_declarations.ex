defmodule Cadence.Reads.CatalogDeclarations do
  @moduledoc """
  Display facts resolved from the active Mission Model revision's catalog
  declarations: the engineering unit of a telemetry parameter, and the valid
  range and unit of a command argument.

  Lowered runtime plans don't always carry these. XTCE import attaches a
  parameter's unit to its *parameter type*, which lowering doesn't follow, so
  this read follows `parameter -> type -> unit` itself. Declarations are read
  through a bounded projection (`closure/4`), never the whole revision.
  """

  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis

  @type declarations :: %{binary() => map()}

  @hops 2
  @followed_roles ~w(type unit)

  @doc "The active revision id (`nil` when nothing is active)."
  @spec active_revision_id(binary(), binary()) :: binary() | nil
  defdelegate active_revision_id(organization_id, mission_id), to: ActiveBasis

  @doc """
  The named declarations of a revision plus what their `type` and `unit`
  references resolve to (two hops: parameter -> type -> unit), keyed by
  semantic id. `%{}` when the revision is `nil` or unreadable.
  """
  @spec closure(binary(), binary(), binary() | nil, [binary()]) :: declarations()
  def closure(_organization_id, _mission_id, nil, _ids), do: %{}

  def closure(organization_id, mission_id, revision_id, ids) do
    load = &MissionModels.declarations(organization_id, mission_id, revision_id, &1)
    follow(load, Enum.uniq(ids), %{}, @hops)
  end

  defp follow(_load, [], acc, _hops), do: acc

  defp follow(load, ids, acc, hops) do
    case load.(ids) do
      {:ok, found} ->
        acc = Map.merge(acc, found)

        next =
          found
          |> Map.values()
          |> Enum.flat_map(&followed_ids/1)
          |> Enum.uniq()
          |> Enum.reject(&Map.has_key?(acc, &1))

        if hops == 0, do: acc, else: follow(load, next, acc, hops - 1)

      {:error, _reason} ->
        acc
    end
  end

  defp followed_ids(declaration) do
    declaration
    |> field(:references)
    |> List.wrap()
    |> Enum.filter(&(to_string(field(&1, :role)) in @followed_roles))
    |> Enum.map(&field(&1, :resolved_id))
    |> Enum.filter(&is_binary/1)
  end

  @doc "The unit symbol of a parameter, from its own unit reference or its type's."
  @spec parameter_unit(declarations(), binary() | nil) :: binary() | nil
  def parameter_unit(declarations, parameter_id) do
    with %{} = parameter <- Map.get(declarations, parameter_id || "") do
      unit_symbol(declarations, parameter) ||
        declarations |> referenced(parameter, :type) |> then(&unit_symbol(declarations, &1))
    end
  end

  @doc "The `base_type` of a parameter's type (for example `integer` or `enumerated`), or `nil`."
  @spec parameter_base_type(declarations(), binary() | nil) :: binary() | nil
  def parameter_base_type(declarations, parameter_id) do
    with %{} = parameter <- Map.get(declarations, parameter_id || ""),
         %{} = type <- referenced(declarations, parameter, :type),
         %{} = definition <- field(type, :definition) do
      blank_to_nil(to_string(field(definition, :base_type) || ""))
    else
      _none -> nil
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
    # XTCE import writes minimum/maximum; the Cadence YAML importer writes min/max.
    minimum = number_or_nil(field(range, :minimum)) || number_or_nil(field(range, :min))
    maximum = number_or_nil(field(range, :maximum)) || number_or_nil(field(range, :max))

    case {minimum, maximum} do
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

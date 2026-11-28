defmodule Cadence.MissionModels.AuthoredScope do
  @moduledoc """
  An authored declaration's composition scope (ADR-020 P3 M2, #451; mm-engineer's refinement on
  #1106): its definition's `compositions` names the compositions it applies to; absent or empty,
  every composition in use. A composition compiles at the head with only the declarations in its
  scope, so the head is still one layer id per version.
  """

  alias Cadence.Catalog.MissionModel.{Declaration, Layer}

  @doc "`layer` with only the declarations that apply to `composition_id`."
  @spec for_composition(Layer.t(), binary()) :: Layer.t()
  def for_composition(%Layer{} = layer, composition_id) do
    %{layer | declarations: Enum.filter(layer.declarations, &applies?(&1, composition_id))}
  end

  @doc "Whether `declaration` applies to `composition_id`."
  @spec applies?(Declaration.t(), binary()) :: boolean()
  def applies?(%Declaration{definition: definition}, composition_id) do
    case scope(definition) do
      [] -> true
      ids -> composition_id in ids
    end
  end

  defp scope(%{} = definition) do
    case Map.get(definition, "compositions", Map.get(definition, :compositions)) do
      ids when is_list(ids) -> ids
      _all -> []
    end
  end

  defp scope(_definition), do: []
end

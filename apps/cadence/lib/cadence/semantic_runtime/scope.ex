defmodule Cadence.SemanticRuntime.Scope do
  @moduledoc "Stable mission and spacecraft key for partition-local semantic state."

  alias Cadence.SemanticRuntime.Update

  @mission_scope_id "__mission__"

  @type t :: {binary(), binary()}

  @spec from_update(Update.t()) :: t()
  def from_update(%Update{metadata: metadata}) do
    new(value(metadata, :mission_id), value(metadata, :spacecraft_id))
  end

  @spec new(binary() | nil, binary() | nil) :: t()
  def new(mission_id, spacecraft_id) do
    {scope_value(mission_id), scope_value(spacecraft_id)}
  end

  @spec mission() :: t()
  def mission, do: {@mission_scope_id, @mission_scope_id}

  @spec state_key(t(), binary()) :: {t(), binary()}
  def state_key(scope, semantic_id), do: {scope, semantic_id}

  @spec all(map()) :: [t()]
  def all(latest) when is_map(latest) do
    scopes =
      latest
      |> Map.keys()
      |> Enum.flat_map(fn
        {scope, _parameter_id} when is_tuple(scope) -> [scope]
        _other -> []
      end)
      |> Enum.uniq()
      |> Enum.sort()

    if scopes == [], do: [mission()], else: scopes
  end

  defp scope_value(value) when is_binary(value) and value != "", do: value
  defp scope_value(_value), do: @mission_scope_id

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

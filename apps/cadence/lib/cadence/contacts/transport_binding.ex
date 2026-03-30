defmodule Cadence.Contacts.TransportBinding do
  @moduledoc """
  Runtime configuration for one transport-local capability bound under a path.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type target_scope :: :path | :transport

  @type t :: %__MODULE__{
          transport_binding_id: binary(),
          family_key: atom(),
          target_scope: target_scope(),
          configuration: term(),
          metadata: map()
        }

  defstruct [
    :transport_binding_id,
    :family_key,
    :target_scope,
    :configuration,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    family_key = Map.get(attrs, :family_key, Map.get(attrs, "family_key"))

    %__MODULE__{
      transport_binding_id:
        Map.get(
          attrs,
          :transport_binding_id,
          Map.get(attrs, "transport_binding_id", Ids.new("transport_binding"))
        ),
      family_key: normalize_family_key(family_key),
      target_scope:
        Map.get(attrs, :target_scope, Map.get(attrs, "target_scope", :path))
        |> normalize_target_scope(),
      configuration: Map.get(attrs, :configuration, Map.get(attrs, "configuration", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_family_key(family_key), do: KnownAtom.transport_family_key!(family_key)
  defp normalize_target_scope(target_scope), do: KnownAtom.target_scope!(target_scope)
end

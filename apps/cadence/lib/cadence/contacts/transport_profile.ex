defmodule Cadence.Contacts.TransportProfile do
  @moduledoc """
  Mission-owned reusable transport-extension configuration.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type target_scope :: :path | :transport
  @type lifecycle_state :: :active | :deleted

  @type t :: %__MODULE__{
          transport_profile_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          family_key: atom(),
          target_scope: target_scope(),
          configuration: map(),
          metadata: map()
        }

  defstruct [
    :transport_profile_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :family_key,
    :target_scope,
    configuration: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    family_key = Map.get(attrs, :family_key, Map.get(attrs, "family_key"))

    %__MODULE__{
      transport_profile_id:
        Map.get(
          attrs,
          :transport_profile_id,
          Map.get(attrs, "transport_profile_id", Ids.new("transport_profile"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, Map.get(attrs, "version", 1)),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
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

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.versioned_resource_lifecycle_state!(lifecycle_state)
end

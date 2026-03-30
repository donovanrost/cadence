defmodule Cadence.Contacts.ProviderProfile do
  @moduledoc """
  Mission-owned reusable provider adapter configuration.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type adapter_key :: atom()
  @type lifecycle_state :: :active | :deleted

  @type t :: %__MODULE__{
          provider_profile_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          adapter_key: adapter_key(),
          configuration: map(),
          metadata: map()
        }

  defstruct [
    :provider_profile_id,
    :organization_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :adapter_key,
    configuration: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    adapter_key = Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key"))

    %__MODULE__{
      provider_profile_id:
        Map.get(
          attrs,
          :provider_profile_id,
          Map.get(attrs, "provider_profile_id", Ids.new("provider_profile"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      version: Map.get(attrs, :version, Map.get(attrs, "version", 1)),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      adapter_key: normalize_adapter_key(adapter_key),
      configuration: Map.get(attrs, :configuration, Map.get(attrs, "configuration", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_adapter_key(adapter_key), do: KnownAtom.provider_adapter_key!(adapter_key)

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.versioned_resource_lifecycle_state!(lifecycle_state)
end

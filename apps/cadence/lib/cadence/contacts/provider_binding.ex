defmodule Cadence.Contacts.ProviderBinding do
  @moduledoc """
  Runtime configuration for one provider adapter bound under a path.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type adapter_key :: atom()

  @type t :: %__MODULE__{
          provider_binding_id: binary(),
          adapter_key: adapter_key(),
          configuration: term(),
          metadata: map()
        }

  defstruct [
    :provider_binding_id,
    :adapter_key,
    :configuration,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    adapter_key = Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key"))

    %__MODULE__{
      provider_binding_id:
        Map.get(
          attrs,
          :provider_binding_id,
          Map.get(attrs, "provider_binding_id", Ids.new("provider_binding"))
        ),
      adapter_key: normalize_adapter_key(adapter_key),
      configuration: Map.get(attrs, :configuration, Map.get(attrs, "configuration", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_adapter_key(adapter_key), do: KnownAtom.provider_adapter_key!(adapter_key)
end

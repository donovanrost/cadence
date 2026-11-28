defmodule Cadence.Contacts.ProfileStore.Versions do
  @moduledoc """
  The next version of a provider or transport profile: the current one with `attrs`' changes, made
  active again and one version on. `ProfileStore` stores it through its usual checks.
  """

  alias Cadence.Contacts.{ProviderProfile, TransportProfile}

  @doc "The provider profile's next version with `attrs` applied."
  def next_provider_profile(%ProviderProfile{} = provider_profile, attrs) do
    {:ok,
     %ProviderProfile{
       provider_profile
       | version: provider_profile.version + 1,
         lifecycle_state: :active,
         adapter_key: Map.get(attrs, :adapter_key, provider_profile.adapter_key),
         configuration: Map.get(attrs, :configuration, provider_profile.configuration),
         metadata: Map.merge(provider_profile.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  @doc "The transport profile's next version with `attrs` applied."
  def next_transport_profile(%TransportProfile{} = transport_profile, attrs) do
    {:ok,
     %TransportProfile{
       transport_profile
       | version: transport_profile.version + 1,
         lifecycle_state: :active,
         family_key: Map.get(attrs, :family_key, transport_profile.family_key),
         target_scope: Map.get(attrs, :target_scope, transport_profile.target_scope),
         configuration: Map.get(attrs, :configuration, transport_profile.configuration),
         metadata: Map.merge(transport_profile.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end
end

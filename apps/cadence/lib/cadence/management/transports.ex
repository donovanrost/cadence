defmodule Cadence.Management.Transports do
  @moduledoc """
  Management-plane orchestration for Transport configuration.

  Provider-managed Transports cross the Ground Networks and Comms contexts, so
  this service resolves provider state and passes an immutable, narrowly scoped
  basis into the Comms persistence boundary.
  """

  alias Cadence.Comms.{ProviderTransportBasis, Transport, TransportStore}
  alias Cadence.Management.Providers

  @spec persist_transport(binary(), Transport.t()) ::
          {:ok, Transport.t()} | {:error, term()}
  def persist_transport(organization_id, %Transport{origin: :direct} = transport)
      when is_binary(organization_id) do
    TransportStore.persist_transport(organization_id, transport)
  end

  def persist_transport(
        organization_id,
        %Transport{origin: :provider_managed, mission_provider_id: provider_id} = transport
      )
      when is_binary(organization_id) and is_binary(provider_id) and provider_id != "" do
    with {:ok, configuration} <-
           Providers.operational_configuration(
             organization_id,
             transport.mission_id,
             provider_id
           ) do
      TransportStore.persist_transport(organization_id, transport,
        provider_transport_basis: provider_transport_basis(configuration)
      )
    end
  end

  def persist_transport(organization_id, %Transport{} = transport)
      when is_binary(organization_id) do
    TransportStore.persist_transport(organization_id, transport)
  end

  defp provider_transport_basis(configuration) do
    provider = configuration.provider

    %ProviderTransportBasis{
      organization_id: configuration.organization_id,
      mission_id: configuration.mission_id,
      provider_id: configuration.provider_id,
      provider_version: configuration.provider_version,
      display_name: provider.display_name,
      provider_type: provider.provider_type,
      environment_ref: provider.environment_ref,
      lifecycle_state: provider.lifecycle_state,
      last_validated_at: provider.last_validated_at,
      last_synced_at: provider.last_synced_at,
      control_status: get_in(provider.metadata, ["control_plane", "status"]),
      inventory_sync_document: provider.inventory_sync_document
    }
  end
end

defmodule Cadence.Management.Providers do
  @moduledoc "Management-plane boundary for provider accounts and mission configuration."

  alias Cadence.GroundNetworks
  alias Cadence.Management.Providers.ProviderConfiguration

  defdelegate persist_provider(scope_or_organization_id, provider), to: GroundNetworks
  defdelegate fetch_provider(organization_id, mission_id, provider_id), to: GroundNetworks

  defdelegate fetch_provider_version(organization_id, mission_id, provider_id, version),
    to: GroundNetworks

  defdelegate list_providers(organization_id, mission_id), to: GroundNetworks
  defdelegate list_provider_versions(organization_id, mission_id, provider_id), to: GroundNetworks

  defdelegate version_provider(organization_id, mission_id, provider_id, attrs),
    to: GroundNetworks

  defdelegate archive_provider(scope_or_organization_id, mission_id, provider_id),
    to: GroundNetworks

  @spec operational_configuration(binary(), binary(), binary()) ::
          {:ok, ProviderConfiguration.t()} | {:error, term()}
  def operational_configuration(organization_id, mission_id, provider_id) do
    with {:ok, provider} <-
           GroundNetworks.fetch_provider(organization_id, mission_id, provider_id) do
      {:ok, ProviderConfiguration.new(provider)}
    end
  end
end

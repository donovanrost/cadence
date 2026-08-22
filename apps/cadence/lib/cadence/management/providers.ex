defmodule Cadence.Management.Providers do
  @moduledoc "Management-plane boundary for provider accounts and mission configuration."

  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.Management.Providers.ProviderConfiguration

  @spec persist_provider(Scope.t() | binary(), MissionProvider.t()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  defdelegate persist_provider(scope_or_organization_id, provider), to: MissionProviders

  @spec fetch_provider(binary(), binary(), binary()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  defdelegate fetch_provider(organization_id, mission_id, provider_id), to: MissionProviders

  @spec fetch_provider_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  defdelegate fetch_provider_version(organization_id, mission_id, provider_id, version),
    to: MissionProviders

  @spec list_providers(binary(), binary()) :: [MissionProvider.t()]
  defdelegate list_providers(organization_id, mission_id), to: MissionProviders

  @spec list_provider_versions(binary(), binary(), binary()) :: [MissionProvider.t()]
  defdelegate list_provider_versions(organization_id, mission_id, provider_id),
    to: MissionProviders

  @spec version_provider(binary(), binary(), binary(), map()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  defdelegate version_provider(organization_id, mission_id, provider_id, attrs),
    to: MissionProviders

  @spec archive_provider(Scope.t() | binary(), binary(), binary()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  defdelegate archive_provider(scope_or_organization_id, mission_id, provider_id),
    to: MissionProviders

  @spec operational_configuration(binary(), binary(), binary()) ::
          {:ok, ProviderConfiguration.t()} | {:error, term()}
  def operational_configuration(organization_id, mission_id, provider_id) do
    with {:ok, provider} <-
           MissionProviders.fetch_provider(organization_id, mission_id, provider_id) do
      {:ok, ProviderConfiguration.new(provider)}
    end
  end
end

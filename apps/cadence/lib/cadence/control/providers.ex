defmodule Cadence.Control.Providers do
  @moduledoc "Control-plane boundary for external provider validation and inventory operations."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.ProviderClients.Registry
  alias Cadence.Control.Contacts.ProviderGrants
  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    CredentialResolver,
    MissionProvider,
    ProviderAccountGrants
  }

  alias Cadence.Management.Providers
  alias Cadence.Management.Providers.ProviderConfiguration

  @spec validate_current(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def validate_current(%Scope{} = scope, mission_id, provider_id, opts \\ []) do
    with :ok <- authorize(scope, mission_id),
         {:ok, configuration} <-
           Providers.operational_configuration(scope.organization_id, mission_id, provider_id) do
      validate(configuration, opts)
    end
  end

  @spec validate(ProviderConfiguration.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def validate(%ProviderConfiguration{} = configuration, opts \\ []) do
    GroundNetworks.validate_provider_configuration(configuration.provider, opts)
  end

  @spec sync_current(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def sync_current(%Scope{} = scope, mission_id, provider_id, opts \\ []) do
    with :ok <- authorize(scope, mission_id),
         {:ok, configuration} <-
           Providers.operational_configuration(scope.organization_id, mission_id, provider_id) do
      sync(configuration, opts)
    end
  end

  @spec sync(ProviderConfiguration.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def sync(%ProviderConfiguration{} = configuration, opts \\ []) do
    GroundNetworks.sync_provider_configuration(configuration.provider, opts)
  end

  @spec search_opportunities(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def search_opportunities(organization_id, mission_id, provider_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_id) and is_map(params) and is_list(opts) do
    with {:ok, provider} <-
           fetch_provider_version(
             organization_id,
             mission_id,
             provider_id,
             Keyword.get(opts, :provider_version)
           ),
         {:ok, context, call_opts} <- provider_context(provider, opts),
         {:ok, client} <- resolve_client(context, opts) do
      client.search_opportunities(context, params, call_opts)
    end
  end

  @spec revoke_account_grant(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def revoke_account_grant(%Scope{} = scope, grant_id, reason, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with {:ok, revoked} <- ProviderAccountGrants.revoke(scope, grant_id, reason, opts),
         {:ok, _affected_count} <-
           ProviderGrants.mark_reservations_for_review(revoked, now) do
      {:ok, revoked}
    end
  end

  defp fetch_provider_version(organization_id, mission_id, provider_id, version)
       when is_integer(version) and version > 0 do
    GroundNetworks.fetch_provider_version(organization_id, mission_id, provider_id, version)
  end

  defp fetch_provider_version(_organization_id, _mission_id, _provider_id, version),
    do: {:error, {:invalid_provider_version, version}}

  defp provider_context(%MissionProvider{} = provider, opts) do
    with {:ok, context} <- GroundNetworks.context_from_provider(provider) do
      call_opts =
        opts
        |> Keyword.drop([:client, :provider_version])
        |> Keyword.put_new(:credential_resolver, CredentialResolver.resolver(opts))

      {:ok, context, call_opts}
    end
  end

  defp resolve_client(context, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(context)
    end
  end

  defp authorize(scope, mission_id) do
    Policy.authorize(scope, :manage_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end
end

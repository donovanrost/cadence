defmodule Cadence.GroundNetworks do
  @moduledoc "Mission-scoped provider control-plane context."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.ProviderClients.Registry
  alias Cadence.Ids

  alias Cadence.GroundNetworks.{
    CredentialResolver,
    DeliveryProfile,
    MissionProvider,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCapabilities,
    ProviderContext,
    ProviderError,
    ServiceProfile,
    Validation
  }

  @inventory_limit 500
  @profile_limit 100

  @spec persist_provider(Scope.t() | binary(), MissionProvider.t()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def persist_provider(scope_or_organization_id, provider),
    do: MissionProviders.persist_provider(scope_or_organization_id, provider)

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
  def archive_provider(scope_or_organization_id, mission_id, provider_id),
    do: MissionProviders.archive_provider(scope_or_organization_id, mission_id, provider_id)

  @spec provider_context(binary(), binary(), binary()) ::
          {:ok, ProviderContext.t()} | {:error, term()}
  def provider_context(organization_id, mission_id, provider_id) do
    with {:ok, provider} <- fetch_provider(organization_id, mission_id, provider_id) do
      context_from_provider(provider, require_active_grant?: true)
    end
  end

  @doc false
  @spec context_from_provider(MissionProvider.t(), keyword()) ::
          {:ok, ProviderContext.t()} | {:error, term()}
  def context_from_provider(%MissionProvider{} = provider, opts \\ []) do
    case provider.provider_account_id do
      nil -> ProviderContext.from_mission_provider(provider)
      _account_id -> context_from_account_binding(provider, opts)
    end
  end

  @spec validate_provider(Scope.t() | binary(), binary(), binary(), keyword()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def validate_provider(scope_or_organization_id, mission_id, provider_id, opts \\ [])

  def validate_provider(%Scope{} = current_scope, mission_id, provider_id, opts) do
    with :ok <- authorize_mission_write(current_scope, mission_id) do
      validate_provider(current_scope.organization_id, mission_id, provider_id, opts)
    end
  end

  def validate_provider(organization_id, mission_id, provider_id, opts) do
    with {:ok, provider} <- fetch_provider(organization_id, mission_id, provider_id) do
      do_validate_provider(provider, opts)
    end
  end

  @spec sync_provider(Scope.t() | binary(), binary(), binary(), keyword()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def sync_provider(scope_or_organization_id, mission_id, provider_id, opts \\ [])

  def sync_provider(%Scope{} = current_scope, mission_id, provider_id, opts) do
    with :ok <- authorize_mission_write(current_scope, mission_id) do
      sync_provider(current_scope.organization_id, mission_id, provider_id, opts)
    end
  end

  def sync_provider(organization_id, mission_id, provider_id, opts) do
    with {:ok, provider} <- fetch_provider(organization_id, mission_id, provider_id) do
      do_sync_provider(provider, opts)
    end
  end

  defp do_validate_provider(provider, opts) do
    checked_at = now(opts)

    with {:ok, context} <- context_from_provider(provider),
         {:ok, client} <- resolve_client(context, opts),
         call_opts = provider_call_opts(opts),
         {:ok, account} <- client.validate_connection(context, call_opts),
         {:ok, capabilities} <- client.capabilities(context, call_opts) do
      metadata =
        provider.metadata
        |> Map.put("control_plane", %{
          "status" => "healthy",
          "checked_at" => DateTime.to_iso8601(checked_at),
          "account" => Validation.sanitize(account)
        })

      MissionProviders.update_operational_state(provider, %{
        capabilities_document: capabilities.evidence,
        last_validated_at: checked_at,
        metadata: metadata
      })
    else
      {:error, reason} -> record_failure(provider, "control_plane", reason, checked_at)
    end
  end

  defp do_sync_provider(provider, opts) do
    synced_at = now(opts)

    with {:ok, context} <- context_from_provider(provider),
         {:ok, client} <- resolve_client(context, opts),
         call_opts = provider_call_opts(opts),
         {:ok, capabilities} <- client.capabilities(context, call_opts),
         :ok <- require_inventory_discovery(capabilities),
         {:ok, spacecraft} <- client.list_spacecraft(context, %{}, call_opts),
         {:ok, ground_stations} <- client.list_ground_stations(context, %{}, call_opts),
         {:ok, service_profiles} <- client.list_service_profiles(context, %{}, call_opts),
         {:ok, delivery_profiles} <- client.list_delivery_profiles(context, %{}, call_opts) do
      sync_document =
        build_sync_document(
          spacecraft,
          ground_stations,
          service_profiles,
          delivery_profiles,
          synced_at
        )

      metadata =
        provider.metadata
        |> Map.put("sync", %{
          "status" => "healthy",
          "checked_at" => DateTime.to_iso8601(synced_at)
        })

      MissionProviders.update_operational_state(provider, %{
        capabilities_document: capabilities.evidence,
        inventory_sync_document: sync_document,
        last_synced_at: synced_at,
        metadata: metadata
      })
    else
      {:error, reason} -> record_failure(provider, "sync", reason, synced_at)
    end
  end

  defp authorize_mission_write(current_scope, mission_id) do
    Policy.authorize(current_scope, :manage_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
  end

  defp context_from_account_binding(provider, opts) do
    with {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             provider.organization_id,
             provider.provider_account_id,
             provider.provider_account_version
           ),
         {:ok, _grant} <- validate_context_grant(provider, opts) do
      ProviderContext.from_account_binding(provider, account_version)
    end
  end

  defp validate_context_grant(provider, opts) do
    if Keyword.get(opts, :require_active_grant?, true) do
      ProviderAccountGrants.validate_binding(
        provider.organization_id,
        provider.mission_id,
        provider.provider_account_id,
        provider.provider_account_version,
        provider.provider_account_grant_id,
        provider.provider_account_grant_version
      )
    else
      ProviderAccountGrants.fetch_version(
        provider.organization_id,
        provider.provider_account_grant_id,
        provider.mission_id,
        provider.provider_account_grant_version
      )
    end
  end

  defp resolve_client(context, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(context)
    end
  end

  defp provider_call_opts(opts) do
    opts
    |> Keyword.drop([:client, :now])
    |> Keyword.put_new(:request_id, Ids.new("provider_request"))
    |> Keyword.put_new(:credential_resolver, CredentialResolver.resolver(opts))
  end

  defp require_inventory_discovery(%ProviderCapabilities{} = capabilities) do
    if ProviderCapabilities.supports?(capabilities, :inventory_discovery) do
      :ok
    else
      {:error,
       ProviderError.from_response(422, %{
         "error" => %{
           "code" => "unsupported_capability",
           "detail" => "provider does not support inventory discovery"
         }
       })}
    end
  end

  defp build_sync_document(
         spacecraft,
         ground_stations,
         service_profiles,
         delivery_profiles,
         synced_at
       ) do
    %{
      "synced_at" => DateTime.to_iso8601(synced_at),
      "spacecraft" => bounded_page(spacecraft, @inventory_limit, &inventory_summary/1),
      "ground_stations" => bounded_page(ground_stations, @inventory_limit, &inventory_summary/1),
      "service_profiles" =>
        bounded_page(service_profiles, @profile_limit, &service_profile_summary/1),
      "delivery_profiles" =>
        bounded_page(delivery_profiles, @profile_limit, &delivery_profile_summary/1)
    }
  end

  defp bounded_page(items, limit, mapper) do
    %{
      "total_count" => length(items),
      "cached_count" => min(length(items), limit),
      "truncated" => length(items) > limit,
      "items" => items |> Enum.take(limit) |> Enum.map(mapper)
    }
  end

  defp inventory_summary(item) when is_map(item) do
    item
    |> Validation.sanitize()
    |> Map.take(~w(id name display_name region antenna_count synthetic state))
  end

  defp service_profile_summary(%ServiceProfile{} = profile) do
    %{
      "id" => profile.id,
      "version" => profile.version,
      "display_name" => profile.display_name,
      "service_kind" => profile.service_kind,
      "direction" => Atom.to_string(profile.direction),
      "supported_delivery_kinds" => profile.supported_delivery_kinds,
      "data_families" => profile.data_families,
      "minimum_duration_seconds" => profile.minimum_duration_seconds,
      "state" => Atom.to_string(profile.state)
    }
  end

  defp delivery_profile_summary(%DeliveryProfile{} = profile) do
    %{
      "id" => profile.id,
      "version" => profile.version,
      "display_name" => profile.display_name,
      "direction" => Atom.to_string(profile.direction),
      "delivery_kind" => profile.delivery_kind,
      "supported_service_profile_refs" => profile.supported_service_profile_refs,
      "state" => Atom.to_string(profile.state),
      "operator_summary" => profile.operator_summary,
      "diagnostics" => profile.diagnostics
    }
  end

  defp record_failure(provider, observation, reason, at) do
    metadata =
      Map.put(provider.metadata, observation, %{
        "status" => "failed",
        "checked_at" => DateTime.to_iso8601(at),
        "error" => encode_error(reason)
      })

    _result = MissionProviders.update_operational_state(provider, %{metadata: metadata})
    {:error, reason}
  end

  defp encode_error(%ProviderError{} = error), do: ProviderError.to_map(error)
  defp encode_error(reason), do: Validation.sanitize(reason)

  defp now(opts),
    do: Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end

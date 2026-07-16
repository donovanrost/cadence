defmodule Cadence.GroundNetworks.MissionProviders do
  @moduledoc "Persistence boundary for versioned mission Provider setup."

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.GroundNetworks.{MissionProvider, ProviderAccountGrants, ProviderAccounts}
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.Schemas.MissionProviderRow
  alias Cadence.Repo

  @spec persist_provider(binary(), MissionProvider.t()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def persist_provider(organization_id, %MissionProvider{} = provider)
      when is_binary(organization_id) do
    with {:ok, scoped_provider} <- put_organization_scope(provider, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_provider.organization_id, scoped_provider.mission_id),
         :ok <- validate_provider(scoped_provider),
         {:ok, _row} <-
           Repo.insert(MissionProviderRow.changeset(scoped_provider),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :provider_id, :version]
           ) do
      fetch_provider_version(
        scoped_provider.organization_id,
        scoped_provider.mission_id,
        scoped_provider.provider_id,
        scoped_provider.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_provider(binary(), binary(), binary()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def fetch_provider(organization_id, mission_id, provider_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(provider_id) do
    case latest_versioned_row(organization_id, mission_id, provider_id) do
      nil -> {:error, :mission_provider_not_found}
      %MissionProviderRow{lifecycle_state: "archived"} -> {:error, :mission_provider_not_found}
      %MissionProviderRow{} = row -> {:ok, MissionProviderRow.to_domain(row)}
    end
  end

  @spec fetch_provider_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def fetch_provider_version(organization_id, mission_id, provider_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(provider_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(MissionProviderRow,
           organization_id: organization_id,
           mission_id: mission_id,
           provider_id: provider_id,
           version: version
         ) do
      nil -> {:error, :mission_provider_not_found}
      %MissionProviderRow{} = row -> {:ok, MissionProviderRow.to_domain(row)}
    end
  end

  @spec list_providers(binary(), binary()) :: [MissionProvider.t()]
  def list_providers(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    MissionProviderRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.provider_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.provider_id, row) end)
    |> Map.values()
    |> Enum.reject(&(&1.lifecycle_state == "archived"))
    |> Enum.map(&MissionProviderRow.to_domain/1)
    |> Enum.sort_by(&String.downcase(&1.display_name))
  end

  @spec list_provider_versions(binary(), binary(), binary()) :: [MissionProvider.t()]
  def list_provider_versions(organization_id, mission_id, provider_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(provider_id) do
    MissionProviderRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.provider_id == ^provider_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&MissionProviderRow.to_domain/1)
  end

  @spec version_provider(binary(), binary(), binary(), map()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def version_provider(organization_id, mission_id, provider_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(provider_id) and
             is_map(attrs) do
    with {:ok, provider} <- fetch_provider(organization_id, mission_id, provider_id),
         {:ok, next_provider} <- build_next_version(provider, attrs) do
      persist_provider(organization_id, next_provider)
    end
  end

  @spec archive_provider(binary(), binary(), binary()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def archive_provider(organization_id, mission_id, provider_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(provider_id) do
    with {:ok, %MissionProvider{} = provider} <-
           fetch_provider(organization_id, mission_id, provider_id) do
      archived = %MissionProvider{
        provider
        | version: provider.version + 1,
          lifecycle_state: :archived,
          metadata:
            Map.put(provider.metadata, "archived_at", DateTime.utc_now() |> DateTime.to_iso8601())
      }

      persist_provider(organization_id, archived)
    end
  end

  @doc false
  @spec update_operational_state(MissionProvider.t(), map()) ::
          {:ok, MissionProvider.t()} | {:error, term()}
  def update_operational_state(%MissionProvider{} = provider, attrs) when is_map(attrs) do
    updates =
      attrs
      |> Map.take([
        :capabilities_document,
        :inventory_sync_document,
        :last_validated_at,
        :last_synced_at,
        :metadata
      ])
      |> encode_document_updates()
      |> Map.to_list()
      |> Keyword.put(:updated_at, DateTime.utc_now())

    case exact_row_query(provider) |> Repo.update_all(set: updates) do
      {1, _rows} ->
        fetch_provider_version(
          provider.organization_id,
          provider.mission_id,
          provider.provider_id,
          provider.version
        )

      {0, _rows} ->
        {:error, :mission_provider_not_found}
    end
  end

  defp latest_versioned_row(organization_id, mission_id, provider_id) do
    MissionProviderRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.provider_id == ^provider_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp exact_row_query(provider) do
    MissionProviderRow
    |> where(
      [row],
      row.organization_id == ^provider.organization_id and row.mission_id == ^provider.mission_id and
        row.provider_id == ^provider.provider_id and row.version == ^provider.version
    )
  end

  defp build_next_version(%MissionProvider{} = provider, attrs) do
    provider_type = value(attrs, :provider_type, provider.provider_type)
    normalized_provider_type = normalize_type(provider_type)

    {:ok,
     MissionProvider.new(%{
       provider_id: provider.provider_id,
       organization_id: provider.organization_id,
       mission_id: provider.mission_id,
       version: provider.version + 1,
       lifecycle_state: :active,
       display_name: value(attrs, :display_name, provider.display_name),
       provider_type: normalized_provider_type,
       client_key:
         value(attrs, :client_key, MissionProvider.client_for(normalized_provider_type)),
       base_url: value(attrs, :base_url, provider.base_url),
       credential_ref: value(attrs, :credential_ref, provider.credential_ref),
       environment_ref: value(attrs, :environment_ref, provider.environment_ref),
       capabilities_document: %{},
       inventory_sync_document: %{},
       provider_account_id: provider.provider_account_id,
       provider_account_version: provider.provider_account_version,
       provider_account_grant_id: provider.provider_account_grant_id,
       provider_account_grant_version: provider.provider_account_grant_version,
       delivery_policy_document:
         value(attrs, :delivery_policy_document, provider.delivery_policy_document),
       spacecraft_mappings_document:
         value(attrs, :spacecraft_mappings_document, provider.spacecraft_mappings_document),
       enabled_service_profile_refs:
         value(attrs, :enabled_service_profile_refs, provider.enabled_service_profile_refs),
       enabled_delivery_profile_refs:
         value(attrs, :enabled_delivery_profile_refs, provider.enabled_delivery_profile_refs),
       permitted_resource_refs:
         value(attrs, :permitted_resource_refs, provider.permitted_resource_refs),
       preferred_transport_refs:
         value(attrs, :preferred_transport_refs, provider.preferred_transport_refs),
       scheduling_policy_document:
         value(attrs, :scheduling_policy_document, provider.scheduling_policy_document),
       fallback_policy_document:
         value(attrs, :fallback_policy_document, provider.fallback_policy_document),
       metadata: Map.merge(provider.metadata, value(attrs, :metadata, %{}))
     })}
  rescue
    error in ArgumentError -> {:error, {:invalid_mission_provider, error.message}}
  end

  defp validate_provider(%MissionProvider{} = provider) do
    with :ok <- validate_base_url(provider.base_url),
         true <- provider.client_key == MissionProvider.client_for(provider.provider_type),
         true <- is_map(provider.capabilities_document),
         true <- is_map(provider.inventory_sync_document),
         true <- is_map(provider.metadata),
         :ok <- validate_account_binding(provider) do
      :ok
    else
      false -> {:error, :invalid_mission_provider}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_account_binding(%MissionProvider{provider_account_id: nil}), do: :ok

  defp validate_account_binding(%MissionProvider{} = provider) do
    with {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             provider.organization_id,
             provider.provider_account_id,
             provider.provider_account_version
           ),
         {:ok, _grant} <-
           ProviderAccountGrants.validate_binding(
             provider.organization_id,
             provider.mission_id,
             provider.provider_account_id,
             provider.provider_account_version,
             provider.provider_account_grant_id,
             provider.provider_account_grant_version
           ),
         true <- account_version.provider_type == provider.provider_type,
         true <- account_version.client_key == provider.client_key,
         true <- account_version.base_url == provider.base_url,
         true <- account_version.environment_ref == provider.environment_ref,
         true <- account_version.credential_ref == provider.credential_ref do
      :ok
    else
      false -> {:error, :mission_provider_account_configuration_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_base_url(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _other ->
        {:error, :invalid_provider_base_url}
    end
  end

  defp put_organization_scope(%MissionProvider{organization_id: nil} = provider, organization_id),
    do: {:ok, %MissionProvider{provider | organization_id: organization_id}}

  defp put_organization_scope(
         %MissionProvider{organization_id: organization_id} = provider,
         organization_id
       ),
       do: {:ok, provider}

  defp put_organization_scope(%MissionProvider{} = provider, organization_id) do
    {:error,
     {:organization_mission_mismatch, provider.organization_id, organization_id,
      provider.mission_id}}
  end

  defp encode_document_updates(attrs) do
    attrs
    |> maybe_encode(:capabilities_document)
    |> maybe_encode(:inventory_sync_document)
    |> maybe_encode(:metadata)
  end

  defp maybe_encode(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, JsonDocument.wrap_value(value))
      :error -> attrs
    end
  end

  defp normalize_type(type) when type in [:simulator], do: type

  defp normalize_type(type) when is_binary(type) do
    Enum.find(MissionProvider.provider_types(), &(Atom.to_string(&1) == type)) ||
      raise ArgumentError, "unsupported provider_type: #{inspect(type)}"
  end

  defp normalize_type(type),
    do: raise(ArgumentError, "unsupported provider_type: #{inspect(type)}")

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end

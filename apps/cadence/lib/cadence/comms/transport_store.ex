defmodule Cadence.Comms.TransportStore do
  @moduledoc """
  Persistence boundary for mission-owned Transports.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.{Transport, TransportKind, TransportRow}
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Contacts, as: ContactsService
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProvider, Validation}
  alias Cadence.Missions
  alias Cadence.Repo

  @spec persist_transport(binary(), Transport.t()) :: {:ok, Transport.t()} | {:error, term()}
  def persist_transport(organization_id, %Transport{} = transport)
      when is_binary(organization_id) do
    with {:ok, scoped_transport} <- put_organization_scope(transport, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_transport.organization_id, scoped_transport.mission_id),
         {:ok, normalized_transport} <- normalize_transport(scoped_transport),
         {:ok, transport_with_provider} <- materialize_provider_profile(normalized_transport),
         {:ok, _row} <-
           Repo.insert(TransportRow.changeset(transport_with_provider),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :transport_id, :version]
           ) do
      fetch_transport_version(
        transport_with_provider.organization_id,
        transport_with_provider.mission_id,
        transport_with_provider.transport_id,
        transport_with_provider.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_transport(binary(), binary(), binary()) :: {:ok, Transport.t()} | {:error, term()}
  def fetch_transport(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    case latest_versioned_row(organization_id, mission_id, transport_id) do
      nil ->
        {:error, :transport_not_found}

      %TransportRow{lifecycle_state: "archived"} ->
        {:error, :transport_not_found}

      %TransportRow{} = row ->
        {:ok, TransportRow.to_domain(row)}
    end
  end

  @spec fetch_transport_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Transport.t()} | {:error, term()}
  def fetch_transport_version(organization_id, mission_id, transport_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(TransportRow,
           organization_id: organization_id,
           mission_id: mission_id,
           transport_id: transport_id,
           version: version
         ) do
      nil -> {:error, :transport_not_found}
      %TransportRow{} = row -> {:ok, TransportRow.to_domain(row)}
    end
  end

  @spec list_transports(binary(), binary()) :: [Transport.t()]
  def list_transports(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.transport_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.transport_id, row) end)
    |> Map.values()
    |> Enum.reject(&(&1.lifecycle_state == "archived"))
    |> Enum.sort_by(& &1.display_name)
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @spec list_transport_versions(binary(), binary(), binary()) :: [Transport.t()]
  def list_transport_versions(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_id == ^transport_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&TransportRow.to_domain/1)
  end

  @spec version_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def version_transport(organization_id, mission_id, transport_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(attrs) do
    with {:ok, %Transport{} = current_transport} <-
           fetch_transport(organization_id, mission_id, transport_id),
         {:ok, %Transport{} = next_transport} <-
           build_next_transport_version(current_transport, attrs) do
      persist_transport(organization_id, next_transport)
    end
  end

  @spec archive_transport(binary(), binary(), binary(), map()) ::
          {:ok, Transport.t()} | {:error, term()}
  def archive_transport(organization_id, mission_id, transport_id, metadata_patch \\ %{})
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_map(metadata_patch) do
    with {:ok, %Transport{} = current_transport} <-
           fetch_transport(organization_id, mission_id, transport_id) do
      archived =
        %Transport{
          current_transport
          | version: current_transport.version + 1,
            lifecycle_state: :archived,
            metadata:
              current_transport.metadata
              |> Map.merge(metadata_patch)
              |> Map.put("archived_at", DateTime.utc_now())
        }

      persist_transport(organization_id, archived)
    end
  end

  defp normalize_transport(%Transport{lifecycle_state: :archived} = transport),
    do: {:ok, transport}

  defp normalize_transport(%Transport{origin: :direct} = transport) do
    with {:ok, entry} <- TransportKind.fetch(transport.transport_kind),
         {:ok, configuration} <- entry.module.normalize_config(transport.configuration) do
      {:ok,
       %Transport{
         transport
         | configuration: configuration,
           adapter_key: entry.adapter_key,
           direction_capability:
             configuration
             |> Map.fetch!("direction_capability")
             |> direction_capability(),
           mission_provider_id: nil,
           mission_provider_version: nil,
           service_profile_ref: nil,
           delivery_profile_ref: nil,
           provider_configuration_snapshot: %{}
       }}
    end
  end

  defp normalize_transport(%Transport{origin: :provider_managed} = transport) do
    with {:ok, provider_id, provider_version} <- provider_reference(transport),
         {:ok, %MissionProvider{} = provider} <-
           GroundNetworks.fetch_provider(
             transport.organization_id,
             transport.mission_id,
             provider_id
           ),
         true <- provider.version == provider_version,
         :ok <- require_validated_provider(provider),
         {:ok, service_profile} <-
           find_profile(provider, "service_profiles", transport.service_profile_ref),
         {:ok, delivery_profile} <-
           find_profile(provider, "delivery_profiles", transport.delivery_profile_ref),
         :ok <- require_profile_compatibility(service_profile, delivery_profile),
         {:ok, configuration} <- TCPSocket.from_delivery_profile(delivery_profile) do
      {:ok,
       %Transport{
         transport
         | transport_kind: :tcp_socket,
           adapter_key: :tcp_socket,
           direction_capability: :inbound,
           configuration: configuration,
           mission_provider_id: provider.provider_id,
           mission_provider_version: provider.version,
           service_profile_ref: exact_profile_ref(service_profile),
           delivery_profile_ref: exact_profile_ref(delivery_profile),
           provider_configuration_snapshot:
             provider_snapshot(provider, service_profile, delivery_profile, configuration)
       }}
    else
      false -> {:error, :mission_provider_version_not_current}
      {:error, reason} -> {:error, reason}
    end
  end

  defp materialize_provider_profile(%Transport{materialized_provider_profile_id: id} = transport)
       when is_binary(id) and id != "" do
    {:ok, transport}
  end

  defp materialize_provider_profile(%Transport{} = transport) do
    with {:ok, entry} <- TransportKind.fetch(transport.transport_kind),
         {:ok, provider_profile} <- entry.module.materialize_provider_profile(transport),
         {:ok, provider_profile} <-
           ContactsService.persist_provider_profile(transport.organization_id, provider_profile) do
      {:ok,
       %Transport{
         transport
         | materialized_provider_profile_id: provider_profile.provider_profile_id
       }}
    end
  end

  defp latest_versioned_row(organization_id, mission_id, transport_id) do
    TransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_id == ^transport_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp build_next_transport_version(%Transport{} = transport, attrs) when is_map(attrs) do
    {:ok,
     %Transport{
       transport
       | version: transport.version + 1,
         lifecycle_state: :active,
         display_name: Map.get(attrs, :display_name, transport.display_name),
         origin: Map.get(attrs, :origin, transport.origin),
         transport_kind: Map.get(attrs, :transport_kind, transport.transport_kind),
         direction_capability:
           Map.get(attrs, :direction_capability, transport.direction_capability),
         adapter_key: Map.get(attrs, :adapter_key, transport.adapter_key),
         configuration: Map.get(attrs, :configuration, transport.configuration),
         mission_provider_id: Map.get(attrs, :mission_provider_id, transport.mission_provider_id),
         mission_provider_version:
           Map.get(attrs, :mission_provider_version, transport.mission_provider_version),
         service_profile_ref: Map.get(attrs, :service_profile_ref, transport.service_profile_ref),
         delivery_profile_ref:
           Map.get(attrs, :delivery_profile_ref, transport.delivery_profile_ref),
         provider_configuration_snapshot: %{},
         materialized_provider_profile_id: nil,
         metadata: Map.merge(transport.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

  defp provider_reference(%Transport{
         mission_provider_id: provider_id,
         mission_provider_version: provider_version
       })
       when is_binary(provider_id) and provider_id != "" and is_integer(provider_version) and
              provider_version > 0,
       do: {:ok, provider_id, provider_version}

  defp provider_reference(_transport), do: {:error, :mission_provider_reference_required}

  defp require_validated_provider(%MissionProvider{} = provider) do
    cond do
      provider.lifecycle_state != :active ->
        {:error, :mission_provider_not_active}

      not match?(%DateTime{}, provider.last_validated_at) ->
        {:error, :mission_provider_not_validated}

      get_in(provider.metadata, ["control_plane", "status"]) != "healthy" ->
        {:error, :mission_provider_not_validated}

      not match?(%DateTime{}, provider.last_synced_at) ->
        {:error, :mission_provider_profiles_not_synced}

      true ->
        :ok
    end
  end

  defp find_profile(provider, document_key, reference) do
    with {:ok, id, version} <- profile_reference(reference),
         items when is_list(items) <-
           get_in(provider.inventory_sync_document, [document_key, "items"]),
         profile when is_map(profile) <-
           Enum.find(items, &(&1["id"] == id and &1["version"] == version)) do
      {:ok, profile}
    else
      _other -> {:error, {:provider_profile_not_found, document_key}}
    end
  end

  defp profile_reference(reference) when is_map(reference) do
    id = Map.get(reference, "id", Map.get(reference, :id))
    version = Map.get(reference, "version", Map.get(reference, :version))

    if is_binary(id) and id != "" and is_integer(version) and version > 0,
      do: {:ok, id, version},
      else: {:error, :invalid_provider_profile_reference}
  end

  defp profile_reference(_reference), do: {:error, :invalid_provider_profile_reference}

  defp require_profile_compatibility(service_profile, delivery_profile) do
    service_id = service_profile["id"]
    supported_services = delivery_profile["supported_service_profile_refs"] || []

    cond do
      service_profile["state"] != "active" ->
        {:error, :provider_service_profile_not_active}

      delivery_profile["state"] != "ready" ->
        {:error, :provider_delivery_profile_not_ready}

      service_profile["direction"] != "downlink" or
          delivery_profile["direction"] != "downlink" ->
        {:error, :provider_profile_direction_not_supported}

      service_id not in supported_services ->
        {:error, :provider_profiles_not_compatible}

      true ->
        :ok
    end
  end

  defp provider_snapshot(provider, service_profile, delivery_profile, configuration) do
    Validation.sanitize(%{
      "provider" => %{
        "id" => provider.provider_id,
        "version" => provider.version,
        "display_name" => provider.display_name,
        "provider_type" => Atom.to_string(provider.provider_type),
        "environment_ref" => provider.environment_ref
      },
      "service_profile" => service_profile,
      "delivery_profile" => delivery_profile,
      "derived_configuration" => configuration
    })
  end

  defp exact_profile_ref(profile),
    do: %{"id" => profile["id"], "version" => profile["version"]}

  defp direction_capability("inbound"), do: :inbound
  defp direction_capability("outbound"), do: :outbound
  defp direction_capability("bidirectional"), do: :bidirectional

  defp put_organization_scope(%Transport{} = transport, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case transport.organization_id do
      nil ->
        {:ok, %Transport{transport | organization_id: organization_id}}

      ^organization_id ->
        {:ok, transport}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          transport.mission_id}}
    end
  end
end

defmodule Cadence.Comms.TransportStore do
  @moduledoc """
  Persistence boundary for mission-owned Transports.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Contacts, as: ContactsService
  alias Cadence.Missions
  alias Cadence.Persistence.Schemas.CommsTransportRow
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
           Repo.insert(CommsTransportRow.changeset(transport_with_provider),
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

      %CommsTransportRow{lifecycle_state: "archived"} ->
        {:error, :transport_not_found}

      %CommsTransportRow{} = row ->
        {:ok, CommsTransportRow.to_domain(row)}
    end
  end

  @spec fetch_transport_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Transport.t()} | {:error, term()}
  def fetch_transport_version(organization_id, mission_id, transport_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(CommsTransportRow,
           organization_id: organization_id,
           mission_id: mission_id,
           transport_id: transport_id,
           version: version
         ) do
      nil -> {:error, :transport_not_found}
      %CommsTransportRow{} = row -> {:ok, CommsTransportRow.to_domain(row)}
    end
  end

  @spec list_transports(binary(), binary()) :: [Transport.t()]
  def list_transports(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    CommsTransportRow
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
    |> Enum.map(&CommsTransportRow.to_domain/1)
  end

  @spec list_transport_versions(binary(), binary(), binary()) :: [Transport.t()]
  def list_transport_versions(organization_id, mission_id, transport_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transport_id) do
    CommsTransportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.transport_id == ^transport_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&CommsTransportRow.to_domain/1)
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

  defp normalize_transport(%Transport{transport_kind: :tcp_socket} = transport) do
    with {:ok, configuration} <- TCPSocket.normalize_config(transport.configuration) do
      {:ok,
       %Transport{
         transport
         | configuration: configuration,
           direction_capability:
             configuration
             |> Map.fetch!("direction_capability")
             |> String.to_existing_atom()
       }}
    end
  end

  defp materialize_provider_profile(%Transport{materialized_provider_profile_id: id} = transport)
       when is_binary(id) and id != "" do
    {:ok, transport}
  end

  defp materialize_provider_profile(%Transport{transport_kind: :tcp_socket} = transport) do
    with {:ok, provider_profile} <- TCPSocket.materialize_provider_profile(transport),
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
    CommsTransportRow
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
         transport_kind: Map.get(attrs, :transport_kind, transport.transport_kind),
         direction_capability:
           Map.get(attrs, :direction_capability, transport.direction_capability),
         adapter_key: Map.get(attrs, :adapter_key, transport.adapter_key),
         configuration: Map.get(attrs, :configuration, transport.configuration),
         materialized_provider_profile_id: nil,
         metadata: Map.merge(transport.metadata, Map.get(attrs, :metadata, %{}))
     }}
  end

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

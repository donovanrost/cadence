defmodule Cadence.Comms.ConfigKinds.Transport do
  @moduledoc """
  Change-set kind for mission Transports.

  Transports are versioned: an update writes version v+1 and delete writes an archived version,
  so the transport's own version history stays intact. The document leaves out what the store
  derives (version, adapter key, provider snapshot, materialized provider profile).

  Contact scheduling reads transports when it books, so applying a change notifies the
  mission's contact scheduler. Booked and running contacts keep the transport they were booked
  with.
  """

  @behaviour Cadence.Platform.ConfigKind

  import Ecto.Query

  alias Cadence.Comms.{
    GroundStationStore,
    ListenClaims,
    Transport,
    TransportKind,
    TransportRow,
    TransportStore
  }

  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Repo

  @fields ~w(display_name origin transport_kind direction_capability configuration ground_station_id
             mission_provider_id mission_provider_version service_profile_ref
             delivery_profile_ref metadata)
  @field_atoms Map.new(@fields, &{&1, String.to_atom(&1)})

  @impl true
  def kind, do: "transport"

  @impl true
  def id_prefix, do: "transport"

  @impl true
  def load(organization_id, mission_id, ids) do
    latest =
      from(row in TransportRow,
        where:
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.transport_id in ^ids,
        distinct: row.transport_id,
        order_by: [asc: row.transport_id, desc: row.version]
      )

    latest
    |> Repo.all()
    |> Enum.reject(&(&1.lifecycle_state == "archived"))
    |> Map.new(fn row ->
      transport = TransportRow.to_domain(row)
      {transport.transport_id, document(transport)}
    end)
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document =
      document
      |> Map.put_new("origin", "direct")
      |> Map.put_new("transport_kind", "tcp_socket")
      |> Map.put_new("configuration", %{})
      |> Map.put_new("metadata", %{})

    errors =
      F.only(document, @fields) ++
        F.text(document, "display_name", 1..200, required: true, label: "Name") ++
        F.one_of(document, "origin", ~w(direct provider_managed), label: "Origin") ++
        F.one_of(document, "transport_kind", ~w(tcp_socket), label: "Kind") ++
        F.one_of(document, "direction_capability", ~w(inbound outbound bidirectional),
          label: "Direction"
        ) ++
        F.map(document, "configuration") ++ F.map(document, "metadata")

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the transport details")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _entity_id, _previous, nil), do: :ok

  def validate(
        org,
        mission_id,
        action,
        entity_id,
        previous,
        %{"ground_station_id" => station} = doc
      )
      when is_binary(station) do
    case GroundStationStore.fetch_ground_station(org, mission_id, station) do
      {:ok, _station} ->
        validate(
          org,
          mission_id,
          action,
          entity_id,
          previous,
          Map.delete(doc, "ground_station_id")
        )

      {:error, _missing} ->
        {:error, [F.error("ground_station_id", "That ground station doesn't exist")]}
    end
  end

  def validate(
        _organization_id,
        mission_id,
        _action,
        _entity_id,
        _previous,
        %{"origin" => "direct"} = doc
      ) do
    kind = Enum.find(Transport.transport_kinds(), &(Atom.to_string(&1) == doc["transport_kind"]))

    with {:ok, entry} <- TransportKind.fetch(kind),
         {:ok, configuration} <- entry.module.normalize_config(doc["configuration"]),
         # SAFETY: a listen host:port is one mission's; the store refuses it too, at write.
         :ok <- ListenClaims.check(mission_id, ListenClaims.endpoint(configuration)) do
      :ok
    else
      {:error, {:listen_endpoint_claimed, _endpoint}} ->
        {:error, [F.error("configuration.port", ListenClaims.message())]}

      _invalid ->
        {:error, [F.error("configuration", "Transport settings are not valid")]}
    end
  end

  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(organization_id, mission_id, :create, id, nil, proposed, _options) do
    transport =
      proposed
      |> attrs()
      |> Map.merge(%{
        transport_id: id,
        organization_id: organization_id,
        mission_id: mission_id,
        version: 1
      })
      |> Transport.new()

    stored(TransportStore.persist_transport(organization_id, transport))
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    attrs =
      proposed
      |> attrs()
      |> Map.merge(%{mission_id: mission_id})
      |> Transport.new()
      |> Map.from_struct()
      |> Map.take(Map.values(@field_atoms))

    stored(TransportStore.version_transport(organization_id, mission_id, id, attrs))
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    case TransportStore.archive_transport(organization_id, mission_id, id) do
      {:ok, _transport} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add transport #{proposed["display_name"]}"
  def summary(:delete, previous, nil), do: "Archive transport #{previous["display_name"]}"
  def summary(:update, previous, _proposed), do: "Edit transport #{previous["display_name"]}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :contacts

  # Transport.new/1 reads atom keys and treats a present nil as a value, so known fields are
  # atomized and nils dropped to let its defaults apply.
  defp attrs(document) do
    for {key, value} <- document, key in @fields, not is_nil(value), into: %{} do
      {Map.fetch!(@field_atoms, key), value}
    end
  end

  defp stored({:ok, transport}), do: {:ok, document(transport), []}
  defp stored({:error, reason}), do: {:error, reason}

  defp document(%Transport{} = transport) do
    %{
      "display_name" => transport.display_name,
      "origin" => Atom.to_string(transport.origin),
      "transport_kind" => Atom.to_string(transport.transport_kind),
      "direction_capability" => Atom.to_string(transport.direction_capability),
      "configuration" => transport.configuration || %{},
      "ground_station_id" => transport.ground_station_id,
      "mission_provider_id" => transport.mission_provider_id,
      "mission_provider_version" => transport.mission_provider_version,
      "service_profile_ref" => transport.service_profile_ref,
      "delivery_profile_ref" => transport.delivery_profile_ref,
      "metadata" => transport.metadata || %{}
    }
  end
end

defmodule Cadence.Management.ConfigKinds.Transport do
  @moduledoc """
  Change-set kind for mission Transports.

  Transports are versioned: an update writes version v+1 and delete writes an archived version,
  so the transport's own version history stays intact. The document leaves out what the store
  derives (version, adapter key, provider snapshot, materialized provider profile).

  Contact scheduling reads transports when it books, so applying a change notifies the
  mission's contact scheduler. Booked and running contacts keep the transport they were booked
  with.

  A **provider-managed** transport stages its provider (`mission_provider_id`,
  `mission_provider_version`) and exact profile refs (`service_profile_ref`,
  `delivery_profile_ref`: `{"id", "version"}`); its configuration and direction are derived
  from the delivery profile and replace anything staged there. Validation runs the same
  derivation an apply does (`Cadence.Management.Transports.derive/3`), so a preview that passes
  applies. This kind is composition, not Comms, because that crosses Ground Networks and Comms
  (comms parity 2).
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.{
    GroundStationStore,
    ListenClaims,
    Transport,
    TransportKind,
    TransportStore
  }

  alias Cadence.Control.ConfigUsers
  alias Cadence.Management.Transports
  alias Cadence.Platform.ConfigFields, as: F

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
    organization_id
    |> TransportStore.latest_transports(mission_id, ids)
    |> Map.new(&{&1.transport_id, document(&1)})
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
  # Archiving: refused while anything still uses it (director 11-16, ux U82), at stage
  # (stage_check/4) and again here, which re-runs at preview and apply.
  def validate(organization_id, mission_id, :delete, entity_id, _previous, nil),
    do: in_use(ConfigUsers.transport_uses(organization_id, mission_id, entity_id))

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
         {:ok, configuration} <- entry.module.normalize_config(doc["configuration"]) do
      listen_claim(mission_id, configuration)
    else
      _invalid -> {:error, [F.error("configuration", "Transport settings are not valid")]}
    end
  end

  # Provider-managed: the provider, its version and the two profile refs are checked, and the
  # configuration derived, exactly as an apply will (Management.Transports.derive/3).
  def validate(
        organization_id,
        mission_id,
        _action,
        _entity_id,
        _previous,
        %{"origin" => "provider_managed"} = doc
      ) do
    case Transports.derive(organization_id, mission_id, doc) do
      {:ok, derived} -> listen_claim(mission_id, derived.configuration)
      {:error, errors} -> {:error, Enum.map(errors, &F.error(&1.path, &1.message))}
    end
  end

  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  # SAFETY: a listen host:port is one mission's (listener guard); the store refuses it too, at
  # write. Both origins check here: a provider-managed transport's derived configuration listens
  # too (provider_connects), so it's refused at validate like a direct one.
  defp listen_claim(mission_id, configuration) do
    case ListenClaims.check(mission_id, ListenClaims.endpoint(configuration)) do
      :ok ->
        :ok

      {:error, {:listen_endpoint_claimed, _endpoint}} ->
        {:error, [F.error("configuration.port", ListenClaims.message())]}
    end
  end

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

    stored(Transports.persist_transport(organization_id, transport))
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    attrs =
      proposed
      |> attrs()
      |> Map.merge(%{mission_id: mission_id})
      |> Transport.new()
      |> Map.from_struct()
      |> Map.take(Map.values(@field_atoms))

    stored(Transports.version_transport(organization_id, mission_id, id, attrs))
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    case TransportStore.archive_transport(organization_id, mission_id, id) do
      {:ok, _transport} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stage_check(organization_id, mission_id, :delete, entity_id, deleting) do
    uses = ConfigUsers.transport_uses(organization_id, mission_id, entity_id, except: deleting)
    if ConfigUsers.in_use?(uses), do: {:error, {:in_use, uses}}, else: :ok
  end

  def stage_check(_organization_id, _mission_id, _action, _entity_id, _deleting), do: :ok

  defp in_use(uses) do
    if ConfigUsers.in_use?(uses),
      do:
        {:error,
         [
           ""
           |> F.error("This transport is still in use, so it can't be archived.")
           |> Map.put(:in_use, uses)
         ]},
      else: :ok
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

  # The store's own refusal (it holds the port's lock, so it can catch what validate raced past,
  # and a provider-managed transport's derived port) in the same words, on the port field.
  defp stored({:error, {:listen_endpoint_claimed, _endpoint}}),
    do: {:error, [F.error("configuration.port", ListenClaims.message())]}

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

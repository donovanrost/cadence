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
  from the delivery profile, with the listener choice owned by Cadence. Validation runs the same
  derivation an apply does (`Cadence.Management.Transports.derive/3`), so a preview that passes
  applies. This kind is composition, not Comms, because that crosses Ground Networks and Comms
  (comms parity 2).
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.{
    GroundStationStore,
    ListenClaims,
    ListenerChoice,
    Transport,
    TransportKind,
    TransportStore
  }

  alias Cadence.Configuration.Document
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

    with {:ok, document} <- F.result(document, errors),
         {:ok, _choice} <- ListenerChoice.parse(ListenerChoice.value(document["configuration"])) do
      {:ok, document}
    else
      {:error, :invalid_listener_choice} ->
        {:error, [ListenerChoice.field_error(:invalid_listener_choice)]}

      {:error, _errors} = error ->
        error
    end
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the transport details")]}

  @impl true
  # Archiving: refused while anything still uses it (director 11-16, ux U82), at stage
  # (stage_check/4) and again here, which re-runs at preview and apply.
  def validate(organization_id, mission_id, :delete, entity_id, previous, nil),
    do:
      in_use(
        entity(entity_id, previous),
        uses(organization_id, mission_id, entity_id, [])
      )

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
        entity_id,
        _previous,
        %{"origin" => "direct"} = doc
      ) do
    with {:ok, configuration} <- direct_configuration(doc) do
      listen_claim(mission_id, entity_id, configuration)
    end
  end

  # Provider-managed: the provider, its version and the two profile refs are checked, and the
  # configuration derived, exactly as an apply will (Management.Transports.derive/3).
  def validate(
        organization_id,
        mission_id,
        _action,
        entity_id,
        _previous,
        %{"origin" => "provider_managed"} = doc
      ) do
    case Transports.derive(organization_id, mission_id, doc) do
      {:ok, derived} -> listen_claim(mission_id, entity_id, derived.configuration)
      {:error, errors} -> {:error, Enum.map(errors, &validation_error/1)}
    end
  end

  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  defp validation_error(error) do
    if error.path == ListenerChoice.path(), do: error, else: F.error(error.path, error.message)
  end

  # SAFETY: a listen host:port is one mission's (listener guard); the store refuses it too, at
  # write. Both origins check here: a provider-managed transport's derived configuration listens
  # too (provider_connects), so it's refused at validate like a direct one.
  defp listen_claim(mission_id, entity_id, configuration) do
    case ListenClaims.check_configuration(mission_id, configuration, {:transport, entity_id}) do
      :ok -> :ok
      {:error, {reason, _endpoint}} -> {:error, [claim_error(reason)]}
    end
  end

  defp direct_configuration(doc) do
    kind = Enum.find(Transport.transport_kinds(), &(Atom.to_string(&1) == doc["transport_kind"]))
    input = doc["configuration"]

    with %{} <- input,
         :ok <- TransportStore.check_direct_delivery_auth(input),
         {:ok, entry} <- TransportKind.fetch(kind),
         {:ok, configuration} <- entry.module.normalize_config(input) do
      {:ok, configuration}
    else
      {:error, reason} ->
        {:error, [direct_validation_error(reason, input)]}

      _invalid ->
        {:error, [direct_validation_error(nil, input)]}
    end
  end

  defp direct_validation_error(:delivery_binding_unavailable, input) do
    if ListenerChoice.shared?(input),
      do: ListenerChoice.field_error(:shared_listener_unavailable_mtls),
      else: F.error("configuration", "Transport settings are not valid")
  end

  defp direct_validation_error(reason, _input),
    do:
      ListenerChoice.field_error(reason) ||
        F.error("configuration", "Transport settings are not valid")

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
    uses = uses(organization_id, mission_id, entity_id, except: deleting)

    if in_use?(uses),
      do:
        {:error, {:in_use, %{entity: entity(organization_id, mission_id, entity_id), uses: uses}}},
      else: :ok
  end

  def stage_check(_organization_id, _mission_id, _action, _entity_id, _deleting), do: :ok

  @impl true
  def stage_conflicts(org, mission, staged, prepared) do
    request =
      for {%{kind: "transport", entity_id: id}, index} <- Enum.with_index(prepared),
          do: {index, {:transport, id}}

    proposals =
      (staged ++ prepared)
      |> Enum.filter(&(&1.kind == "transport"))
      |> Enum.group_by(& &1.entity_id)

    current = load(org, mission, Map.keys(proposals))

    documents =
      Map.new(proposals, fn {id, ops} ->
        {{:transport, id}, Enum.reduce(ops, current[id], &apply_staged/2)}
      end)

    results = stage_configurations(org, mission, documents)

    with :ok <- check_staged_fields(request, results) do
      configs = for {owner, {:ok, config}} <- results, do: {owner, config}

      case ListenClaims.check_staged(mission, configs, request) do
        :ok ->
          :ok

        {:error, index, {reason, _endpoint}} ->
          {:error, {:invalid_op, index, [claim_error(reason)]}}
      end
    end
  end

  defp apply_staged(%{action: "create", payload: %{"document" => document}}, _document),
    do: document

  defp apply_staged(%{action: "update", payload: %{"changes" => changes}}, document),
    do: Document.patch(document, changes)

  defp apply_staged(%{action: "delete"}, _document), do: nil

  defp stage_configurations(org, mission, documents) do
    {managed, other} =
      Enum.split_with(documents, fn {_owner, doc} ->
        match?(%{"origin" => "provider_managed"}, doc)
      end)

    derived = Transports.derive_many(org, mission, Map.new(managed))

    Map.new(other ++ Map.to_list(derived), fn
      {owner, {:ok, derived}} -> {owner, {:ok, derived.configuration}}
      {owner, {:error, _errors} = error} -> {owner, error}
      {owner, nil} -> {owner, {:ok, nil}}
      {owner, doc} -> {owner, direct_configuration(doc)}
    end)
  end

  defp check_staged_fields(request, results) do
    Enum.find_value(request, :ok, fn {index, owner} ->
      with {:error, errors} <- Map.fetch!(results, owner),
           [_ | _] = listener_errors <- Enum.filter(errors, &(&1.path == ListenerChoice.path())) do
        {:error, {:invalid_op, index, listener_errors}}
      else
        _accepted -> nil
      end
    end)
  end

  # The refusal carries what was archived and what uses it, as {:in_use, %{entity, uses}} (api).
  defp in_use(entity, uses) do
    if in_use?(uses),
      do:
        {:error,
         [
           ""
           |> F.error("This transport is still in use, so it can't be archived.")
           |> Map.put(:in_use, %{entity: entity, uses: uses})
         ]},
      else: :ok
  end

  # Through the :config_users adapter (Cadence.Control.ConfigUsers), so this kind has no
  # compile-time edge to Control. Without one configured there's nothing to check.
  defp uses(organization_id, mission_id, transport_id, opts) do
    case Application.get_env(:cadence, :config_users) do
      nil -> %{}
      users -> users.transport_uses(organization_id, mission_id, transport_id, opts)
    end
  end

  defp in_use?(uses), do: Enum.any?(uses, fn {_kind, %{count: count}} -> count > 0 end)

  defp entity(id, %{} = previous),
    do: %{kind: "transport", id: id, name: previous["display_name"]}

  defp entity(organization_id, mission_id, id) do
    name =
      case TransportStore.fetch_transport(organization_id, mission_id, id) do
        {:ok, transport} -> transport.display_name
        _gone -> nil
      end

    %{kind: "transport", id: id, name: name}
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
  defp stored({:error, {reason, %{port: _port}}}), do: {:error, [claim_error(reason)]}

  defp stored({:error, reason}) do
    case ListenerChoice.field_error(reason) do
      nil -> {:error, reason}
      error -> {:error, [error]}
    end
  end

  defp claim_error(:listen_endpoint_claimed),
    do: F.error("configuration.port", ListenClaims.message())

  defp claim_error(:listen_endpoint_mode_mismatch),
    do:
      F.error(
        "configuration.port",
        "Listeners on one endpoint must use the same authentication mode."
      )

  defp claim_error(reason), do: ListenerChoice.field_error(reason)

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

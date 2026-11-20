defmodule Cadence.Applications.OpsConsole.Actions.PlatformBindings do
  @moduledoc """
  Platform-wide data-source bindings (DECISIONS #90, ux U53): a binding with no organization is
  the default every mission reads for its logical source and realm unless it has its own. A switch
  repoints all of those missions, so the server counts the blast radius, requires an audited
  reason, and refuses when the radius changed while the operator was confirming.
  """

  import Ecto.Query

  alias Cadence.Accounts
  alias Cadence.Accounts.MemberNames
  alias Cadence.Administration.PlatformEvents
  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Store.DataBindingRow
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @first_passes 3
  @max_reason 500

  @doc "A binding shared by the platform (no organization)."
  @spec shared?(DataBinding.t()) :: boolean()
  def shared?(%DataBinding{organization_id: nil}), do: true
  def shared?(%DataBinding{}), do: false

  @doc """
  Who a switch of this shared binding would move, now: the missions with no active binding of
  their own for its logical source and realm, and the passes live on them (AOS <= now < LOS).
  `{:error, :blast_radius_unavailable}` when counting fails: the sheet then refuses to switch.
  """
  @spec blast_radius(DataBinding.t(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def blast_radius(%DataBinding{} = binding, now \\ DateTime.utc_now()) do
    missions = affected_missions(binding)
    live = live_passes(missions, now)

    {:ok,
     %{
       affected_missions: length(missions),
       live_passes: %{total: length(live), first: live |> Enum.take(@first_passes) |> names()}
     }}
  rescue
    _error -> {:error, :blast_radius_unavailable}
  end

  @doc """
  The blast-radius read (U53): the binding, its current source, and who a switch would move.
  Also the 409 blast_radius_changed body.
  """
  @spec view(DataBinding.t()) :: {:ok, map()} | {:error, atom()}
  def view(%DataBinding{} = binding) do
    with {:ok, radius} <- blast_radius(binding), do: {:ok, view(binding, radius)}
  end

  @spec view(DataBinding.t(), map()) :: map()
  def view(%DataBinding{} = binding, radius) do
    Map.put(radius, :binding, %{
      id: binding.binding_id,
      logical_source: to_string(binding.logical_source),
      realm: binding.realm && to_string(binding.realm),
      from: source_ref(binding.data_source_id)
    })
  end

  @doc """
  A mission's binding list (U53): its own bindings first, then the platform ones it falls back to
  (only for a logical source and realm it has none of its own for).
  """
  @spec mission_bindings([DataBinding.t()], binary()) :: [map()]
  def mission_bindings(bindings, mission_id) do
    {own, others} = Enum.split_with(bindings, &(&1.mission_id == mission_id))
    covered = MapSet.new(own, &{to_string(&1.logical_source), to_string(&1.realm)})

    fallback =
      Enum.filter(others, fn binding ->
        shared?(binding) and
          not MapSet.member?(
            covered,
            {to_string(binding.logical_source), to_string(binding.realm)}
          )
      end)

    Enum.map(own ++ fallback, &binding_row/1)
  end

  defp binding_row(%DataBinding{} = binding) do
    %{
      id: binding.binding_id,
      logical_source: to_string(binding.logical_source),
      realm: binding.realm && to_string(binding.realm),
      data_source: source_ref(binding.data_source_id),
      status: binding.status,
      shared: shared?(binding)
    }
  end

  @doc """
  The binding's history (U53), newest first: switches carry their reason and counts. Actors are
  named by #146's rule (#471): on an organization's own binding, a person only while an active
  member of that organization; on a platform-wide one (shown in full only to platform admins in
  admin mode), by display name. Never by email.
  """
  @spec events(DataBinding.t(), pos_integer()) :: [map()]
  def events(%DataBinding{} = binding, limit \\ 50) do
    events = DataSources.list_data_binding_events(binding.binding_id, limit: limit)
    actors = actors(events, binding.organization_id)
    sources = source_refs(events)

    Enum.map(events, fn event ->
      payload = event.payload || %{}

      %{
        at: event.occurred_at,
        actor: actor(event.actor_id, actors, binding.organization_id),
        kind: event_kind(event),
        from: named(payload["from"], event.previous_data_source_id, sources),
        to: named(payload["to"], event.current_data_source_id, sources),
        reason: payload["reason"],
        affected_missions: payload["affected_missions"],
        live_passes_total: payload["live_passes_total"]
      }
    end)
  end

  # Every from/to names its source (qa, 11-15: a registered or changed event's had a null name).
  # A switch's payload already carries the names it had then; otherwise the source's current name,
  # or its id when the source is gone.
  defp named(%{"id" => id, "display_name" => name} = ref, _id, _sources)
       when is_binary(id) and is_binary(name),
       do: ref

  defp named(%{"id" => id}, _fallback, sources) when is_binary(id), do: Map.fetch!(sources, id)
  defp named(_ref, id, sources) when is_binary(id), do: Map.fetch!(sources, id)
  defp named(_ref, nil, _sources), do: nil

  defp source_refs(events) do
    events
    |> Enum.flat_map(fn event ->
      payload = event.payload || %{}

      [
        get_in(payload, ["from", "id"]),
        get_in(payload, ["to", "id"]),
        event.previous_data_source_id,
        event.current_data_source_id
      ]
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Map.new(&{&1, source_ref(&1)})
  end

  defp event_kind(event) do
    if event.previous_data_source_id && event.current_data_source_id &&
         event.previous_data_source_id != event.current_data_source_id,
       do: "switched",
       else: to_string(event.event_type)
  end

  defp actor(nil, _actors, _organization_id), do: nil

  # On an organization's binding, someone who isn't a member (a platform admin acting as support)
  # is recorded but neither named nor identified, as the model approval read does (#366).
  defp actor(id, actors, organization_id) when is_binary(organization_id) do
    case Map.fetch(actors, id) do
      {:ok, name} -> %{id: id, name: name}
      :error -> %{id: nil, name: nil}
    end
  end

  defp actor(id, actors, nil), do: %{id: id, name: Map.get(actors, id)}

  defp actors(events, organization_id) do
    ids = events |> Enum.map(& &1.actor_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    names(ids, organization_id)
  end

  defp names(ids, organization_id) when is_binary(organization_id),
    do: MemberNames.display_names(organization_id, ids)

  defp names(ids, nil) do
    Map.new(ids, fn id ->
      case Accounts.fetch_user(id) do
        {:ok, %{display_name: name}} when is_binary(name) and name != "" -> {id, name}
        _no_name -> {id, nil}
      end
    end)
  end

  @doc "A source as `{id, display_name}`, for the from/to of a switch."
  @spec source_ref(DataSource.t() | binary() | nil) :: map() | nil
  def source_ref(%DataSource{} = source),
    do: %{"id" => source.data_source_id, "display_name" => display_name(source)}

  def source_ref(data_source_id) when is_binary(data_source_id) do
    case DataSources.fetch_data_source(data_source_id) do
      {:ok, source} -> source_ref(source)
      _missing -> %{"id" => data_source_id, "display_name" => data_source_id}
    end
  end

  def source_ref(nil), do: nil

  defp display_name(%DataSource{metadata: metadata, data_source_id: id}) do
    (is_map(metadata) && (metadata["display_name"] || metadata[:display_name])) || id
  end

  @doc """
  Validates a shared-binding switch: the reason (required, at most #{@max_reason} characters) and
  the counts the sheet showed. Answers the reason and the counts recorded now, or
  `{:error, {:invalid, field, sentence}}` / `{:error, {:blast_radius_changed, fresh}}`.
  """
  @spec check_switch(DataBinding.t(), map()) :: {:ok, map()} | {:error, term()}
  def check_switch(%DataBinding{} = binding, params) do
    with {:ok, reason} <- reason(params["reason"]),
         {:ok, missions} <- expected(params, "expected_affected_missions"),
         {:ok, passes} <- expected(params, "expected_live_passes_total"),
         {:ok, fresh} <- blast_radius(binding) do
      if fresh.affected_missions == missions and fresh.live_passes.total == passes,
        do: {:ok, %{reason: reason, radius: fresh}},
        else: {:error, {:blast_radius_changed, view(binding, fresh)}}
    end
  end

  @doc "The binding event payload and the platform audit entry for a recorded switch."
  @spec audit(DataBinding.t(), map(), map(), map(), binary()) :: :ok
  def audit(%DataBinding{} = binding, from, to, %{reason: reason, radius: radius}, actor_id) do
    PlatformEvents.record(actor_id, "platform_binding_switched", %{
      target: {"data_source_binding", binding.binding_id, binding.binding_id},
      details: payload(from, to, reason, radius)
    })
  end

  @spec payload(map(), map(), binary(), map()) :: map()
  def payload(from, to, reason, radius) do
    %{
      "reason" => reason,
      "affected_missions" => radius.affected_missions,
      "live_passes_total" => radius.live_passes.total,
      "from" => from,
      "to" => to
    }
  end

  defp reason(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, {:invalid, "reason", "Say why you're switching it for every mission."}}
      trimmed when byte_size(trimmed) > @max_reason -> {:error, {:invalid, "reason", too_long()}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp reason(_missing),
    do: {:error, {:invalid, "reason", "Say why you're switching it for every mission."}}

  defp too_long, do: "Keep the reason under #{@max_reason} characters."

  defp expected(params, field) do
    case params[field] do
      count when is_integer(count) and count >= 0 -> {:ok, count}
      _other -> {:error, {:invalid, field, "Send the count the confirmation showed."}}
    end
  end

  # Missions on the platform minus those with an active binding of their own for the same
  # logical source and realm.
  defp affected_missions(%DataBinding{} = binding) do
    logical_source = to_string(binding.logical_source)
    realm = binding.realm && to_string(binding.realm)

    own =
      from(row in DataBindingRow,
        where:
          not is_nil(row.mission_id) and row.logical_source == ^logical_source and
            row.status == "active",
        select: row.mission_id
      )
      |> maybe_realm(realm)

    own = own |> Repo.all() |> MapSet.new()
    Enum.reject(Missions.list_all_mission_keys(), fn {_org, id} -> MapSet.member?(own, id) end)
  end

  defp maybe_realm(query, nil), do: query
  defp maybe_realm(query, realm), do: where(query, [row], row.realm == ^realm)

  defp live_passes([], _now), do: []

  defp live_passes(missions, now) do
    missions |> Enum.map(&elem(&1, 1)) |> ProviderReservations.live_on(now)
  end

  # 'EARENDIL-312 · SVA 03:10Z' (ux U53): the spacecraft's name and the station's code.
  defp names(reservations) do
    Enum.map(reservations, fn reservation ->
      org = reservation.organization_id
      mission = reservation.mission_id

      %{
        spacecraft_name: spacecraft_name(org, mission, reservation.spacecraft_id),
        station_code: station_code(org, mission, ground_station_ref(reservation)),
        aos: reservation.starts_at
      }
    end)
  end

  defp spacecraft_name(_org, _mission, nil), do: nil

  defp spacecraft_name(org, mission, spacecraft_id) do
    case SpacecraftStore.fetch_spacecrafts_in_batches(org, mission, [spacecraft_id]) do
      {:ok, %{^spacecraft_id => craft}} -> craft.display_name
      _missing -> spacecraft_id
    end
  end

  defp station_code(_org, _mission, nil), do: nil

  defp station_code(org, mission, ref) do
    StationRefs.resolve(ref, StationRefs.index(org, mission)).code || ref
  end

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end
end

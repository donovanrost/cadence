defmodule Cadence.Reads.ActionQueue.AttentionItems do
  @moduledoc """
  Attention items of the action queue (DECISIONS #54, ux U31): the mission's
  "needs acknowledgment" items from `Cadence.Reads.Attention` (pass-resolution
  conflicts for now), one queue row each, never grouped.

    * **P1** (`critical`) when the affected pass starts within 2 h or is in
      progress; **P2** (`caution`) otherwise. Computed on every read, so a row
      moves up at AOS−2h on the next refetch.
    * Acknowledged items sort last within their priority (U21), like fully
      acknowledged alarms.
    * `due_at` is the pass start (the consequence time), `since` is when the
      conflict was raised.

  Names are resolved here: spacecraft (from the fleet read, falling back to the
  spacecraft store for one that left the fleet), station identity and provider.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Comms.StationRefs
  alias Cadence.GroundNetworks.MissionProviders
  alias Cadence.Reads.ActionQueue.Item
  alias Cadence.Reads.Attention
  alias Cadence.SpacecraftStore

  @p1_horizon_s 2 * 3600

  @doc "Loads the attention read and builds its items, names resolved; none when unavailable."
  @spec load(Scope.t(), binary(), map(), DateTime.t()) :: %{items: [map()], resolved: [map()]}
  def load(%Scope{} = scope, mission_id, fleet, now) do
    case Attention.load(scope, mission_id, now: now) do
      {:ok, %{items: [], resolved: []}} ->
        %{items: [], resolved: []}

      {:ok, loaded} ->
        build(
          loaded,
          attention_names(scope.organization_id, mission_id, fleet, loaded),
          now
        )

      {:error, _reason} ->
        %{items: [], resolved: []}
    end
  end

  defp attention_names(org, mission_id, fleet, loaded) do
    wanted =
      loaded.items |> Enum.map(& &1.spacecraft_id) |> Enum.reject(&is_nil/1) |> MapSet.new()

    in_fleet =
      fleet.spacecraft
      |> Enum.filter(&MapSet.member?(wanted, &1.id))
      |> Map.new(&{&1.id, Item.member(&1)})

    org
    |> lookups(mission_id)
    |> Map.put(:spacecraft, Map.merge(outside_fleet(org, mission_id, wanted, in_fleet), in_fleet))
  end

  @doc "Station and provider name lookups for `object/2` (pass rows, the attention endpoints)."
  @spec lookups(binary(), binary()) :: map()
  def lookups(org, mission_id) do
    stations = StationRefs.index(org, mission_id)

    %{
      spacecraft: %{},
      station: &StationRefs.resolve(&1, stations),
      providers:
        org
        |> MissionProviders.list_providers(mission_id)
        |> Map.new(&{&1.provider_id, %{id: &1.provider_id, name: &1.display_name}})
    }
  end

  # A spacecraft that left the fleet (archived) still has a name.
  defp outside_fleet(org, mission_id, wanted, in_fleet) do
    missing = wanted |> Enum.reject(&Map.has_key?(in_fleet, &1))

    case missing != [] && SpacecraftStore.fetch_spacecrafts(org, mission_id, missing) do
      {:ok, found} ->
        Map.new(found, fn {id, craft} ->
          {id,
           Item.member(%{
             id: id,
             name: craft.display_name,
             scid: craft.scid,
             plane: nil,
             stale: nil,
             last_received_at: nil,
             violating_points: nil
           })}
        end)

      _none ->
        %{}
    end
  end

  @doc """
  Queue items and the `resolved` list (ids match the rows they replace) from
  an attention load. `names` = `%{spacecraft, stations, providers}` lookups.
  """
  @spec build(map(), map(), DateTime.t()) :: %{items: [map()], resolved: [map()]}
  def build(%{items: items, resolved: resolved}, names, now) do
    %{
      items: Enum.map(items, &item(&1, names, now)),
      resolved: Enum.map(resolved, &resolved(&1, names))
    }
  end

  @doc "The queue id of an attention item: `attention:<source>:<id>`."
  @spec item_id(map()) :: binary()
  def item_id(%{source: source, id: id}), do: "attention:#{source}:#{id}"

  defp item(attention, names, now) do
    p1? = p1?(attention, now)

    Item.new(%{
      id: item_id(attention),
      priority: if(p1?, do: 1, else: 2),
      kind: :attention,
      state: if(p1?, do: :critical, else: :caution),
      source: attention.source,
      since: attention.raised_at,
      due_at: attention.starts_at,
      count: 1,
      spacecraft: spacecraft(attention.spacecraft_id, names),
      attention: object(attention, names)
    })
  end

  @doc """
  The wire `attention` object of one item from the attention read (the queue row's
  `attention`, pass rows, the acknowledge/resolve responses), names resolved with `lookups/2`.
  """
  @spec object(map(), map()) :: map()
  def object(attention, names) do
    %{
      id: attention.id,
      source: attention.source,
      conflict: attention.conflict,
      state: attention.state,
      acknowledged_by: attention.acknowledged_by,
      contact_id: attention.contact_id,
      reservation_id: Map.get(attention, :provider_reservation_id),
      station: station(attention.ground_station_ref, names),
      provider: provider(attention.provider_id, names),
      starts_at: attention.starts_at,
      raised_at: attention.raised_at,
      provider_message: attention.provider_message,
      resolution: attention.resolution
    }
  end

  # Within 2 h of the pass start, or the pass is under way (started, not ended).
  defp p1?(%{starts_at: %DateTime{} = starts_at} = attention, now) do
    horizon = DateTime.add(now, @p1_horizon_s, :second)

    DateTime.compare(starts_at, horizon) != :gt and
      not ended?(Map.get(attention, :ends_at), now)
  end

  defp p1?(_attention, _now), do: false

  defp ended?(%DateTime{} = ends_at, now), do: DateTime.compare(ends_at, now) != :gt
  defp ended?(_ends_at, _now), do: false

  # A provider closure names the provider; a user names themself; a system closure has no actor
  # name (ux: "Resolved: cancel confirmed").
  defp resolved(entry, names) do
    by = entry.resolved_by || %{}

    %{
      id: item_id(entry),
      resolved_by: %{
        kind: by["kind"],
        id: by["id"],
        name: resolved_name(by, names)
      },
      action: entry.action,
      resolved_at: entry.resolved_at
    }
  end

  defp resolved_name(%{"kind" => "provider", "id" => id} = by, names),
    do: provider(id, names).name || by["name"]

  defp resolved_name(by, _names), do: by["name"]

  defp spacecraft(nil, _names), do: []

  defp spacecraft(id, names) do
    case Map.fetch(names.spacecraft, id) do
      {:ok, member} -> [member]
      :error -> []
    end
  end

  defp station(ref, names), do: names.station.(ref)

  defp provider(nil, _names), do: %{id: nil, name: nil}

  defp provider(id, names),
    do: Map.get(names.providers, id, %{id: id, name: nil})
end

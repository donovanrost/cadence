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
  alias Cadence.Reads.{Attention, PassUplink}
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
      loaded.items
      |> Enum.flat_map(&(Map.get(&1, :spacecraft_ids) || [Map.get(&1, :spacecraft_id)]))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

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

    case missing != [] && SpacecraftStore.fetch_spacecrafts_in_batches(org, mission_id, missing) do
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
      priority: priority(p1?, attention, now),
      kind: :attention,
      state: if(p1?, do: :critical, else: :caution),
      source: attention.source,
      since: attention.raised_at,
      due_at: due_at(attention),
      count: 1,
      spacecraft: members(attention, names),
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
      conflict: Map.get(attention, :conflict),
      state: attention.state,
      acknowledged_by: Map.get(attention, :acknowledged_by),
      contact_id: Map.get(attention, :contact_id),
      reservation_id: Map.get(attention, :provider_reservation_id),
      station: station(Map.get(attention, :ground_station_ref), names),
      provider: provider(Map.get(attention, :provider_id), names),
      starts_at: Map.get(attention, :starts_at),
      raised_at: attention.raised_at,
      provider_message: Map.get(attention, :provider_message),
      resolution: Map.get(attention, :resolution),
      uplink: uplink(attention),
      release: release(attention)
    }
    |> Map.merge(settlement(attention))
  end

  # DECISIONS #71 / ux U37: telemetry still on disk, not stored. The pass has ended, so the row
  # is always P2; nothing expires it (the journal keeps it) and Cadence retries by itself.
  @settlement_keys [
    :reason,
    :failure_kind,
    :failure_message,
    :realized_contact_id,
    :spacecraft_id,
    :ends_at,
    :deadline_at,
    :journal,
    :backlog,
    :expires_at,
    :retry,
    :attempts,
    :next_attempt_at,
    :last_attempt_at,
    :first_failure_kind
  ]

  # 2026-11-12 / ux U38: the mission's runtime hasn't applied its active generation.
  @mission_runtime_keys [
    :reason,
    :failure_message,
    :desired_generation,
    :applied_generation,
    :since,
    :activated_at,
    :change_set_id
  ]

  # Director C / ux U41: an approved activation whose apply failed or stalled (Retry apply).
  @activation_apply_keys [
    :error_code,
    :error,
    :retryable,
    :activation_request_id,
    :summary,
    :kind,
    :app,
    :spacecraft_ids,
    :spacecraft_count,
    :runtime_not_applied,
    :since,
    :approved_by,
    :approved_at
  ]

  defp settlement(%{source: "contact_settlement"} = attention),
    do: Map.take(attention, @settlement_keys)

  defp settlement(%{source: "mission_runtime"} = attention),
    do: Map.take(attention, @mission_runtime_keys)

  defp settlement(%{source: "activation_apply"} = attention),
    do: Map.take(attention, @activation_apply_keys)

  # §11 L14: what the provider changed, for the decision block.
  defp settlement(%{source: "provider_change"} = attention) do
    attention
    |> Map.take([:provider_change, :deadline_at])
    |> Map.update(:provider_change, nil, &provider_change/1)
  end

  defp settlement(_attention), do: %{}

  @doc """
  A provider change as the console reads it (ux U44): one `state`, which is `expired` for a
  pending change whose pass has ended (domain's derived `expired`, kept alongside).
  """
  @spec provider_change(map() | nil) :: map() | nil
  def provider_change(%{expired: true} = change), do: %{change | state: "expired"}
  def provider_change(change), do: change

  # D2 Release whose cancel the provider didn't confirm (domain 548b8dd9).
  defp release(%{source: "pass_release"} = attention),
    do: %{outcome: Map.get(attention, :outcome), reason: Map.get(attention, :provider_reason)}

  defp release(_attention), do: nil

  # U33 / DECISIONS #58: a blocked pass holding queued command groups back.
  defp uplink(%{source: "uplink_blocked"} = attention) do
    %{
      state: "blocked",
      reason: PassUplink.reason_key(attention.reason),
      since: attention.raised_at,
      command_group_ids: Map.get(attention, :command_group_ids, [])
    }
  end

  defp uplink(_attention), do: nil

  # The queue sorts within a priority by due_at. A settlement Cadence is still retrying is due at
  # its next attempt (future); one handed to an operator at its last attempt (past), so those
  # rank first (fe-ops, ux U37). Other sources: the pass start.
  defp due_at(%{source: "contact_settlement", retry: "manual"} = attention),
    do: Map.get(attention, :last_attempt_at) || attention.raised_at

  defp due_at(%{source: "contact_settlement"} = attention),
    do: Map.get(attention, :next_attempt_at) || attention.starts_at

  # An approval is due at its deadline (the provider applies or drops it then).
  defp due_at(%{source: "provider_change", deadline_at: %DateTime{} = deadline}), do: deadline
  defp due_at(attention), do: Map.get(attention, :starts_at)

  # fe-ops (L14): a provider change to acknowledge, or one that failed, is P3; an approval P2
  # until its deadline passes (ux U44: the provider decides then), then P3.
  defp priority(true, _attention, _now), do: 1

  defp priority(false, %{source: "provider_change", conflict: "approval_required"} = item, now) do
    case Map.get(item, :deadline_at) do
      %DateTime{} = deadline -> if DateTime.compare(deadline, now) == :gt, do: 2, else: 3
      _none -> 2
    end
  end

  defp priority(false, %{source: "provider_change"}, _now), do: 3
  defp priority(false, _attention, _now), do: 2

  # Within 2 h of the pass start, or the pass is under way (started, not ended).
  defp p1?(%{source: "contact_settlement"}, _now), do: false
  defp p1?(%{source: "provider_change"}, _now), do: false
  # No spacecraft's telemetry is processed while it's open.
  defp p1?(%{source: "mission_runtime"}, _now), do: true
  # The same while an apply that would bring the runtime up is stuck (ux U41).
  defp p1?(%{source: "activation_apply"} = attention, _now),
    do: Map.get(attention, :runtime_not_applied) == true

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
      resolved_at: entry.resolved_at,
      note: Map.get(entry, :note)
    }
  end

  defp resolved_name(%{"kind" => "provider", "id" => id} = by, names),
    do: provider(id, names).name || by["name"]

  defp resolved_name(by, _names), do: by["name"]

  # An activation names several spacecraft; other sources one.
  defp members(%{spacecraft_ids: [_ | _] = ids}, names),
    do: Enum.flat_map(ids, &spacecraft(&1, names))

  defp members(attention, names), do: spacecraft(Map.get(attention, :spacecraft_id), names)

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

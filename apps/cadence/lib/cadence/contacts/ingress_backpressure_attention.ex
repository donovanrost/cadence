defmodule Cadence.Contacts.IngressBackpressureAttention do
  @moduledoc """
  The `ingress_backpressure` source of the mission attention read (DECISIONS #83, ux U47), one
  item per downlink transport of a running contact, from `Cadence.Runtime.IngressBackpressureMonitor`
  (read through `Cadence.Runtime.Ingress`):

  - `journal_near_full`: the contact's ingest buffer (its journal) is at least 80% full. P1 at
    95% or while it is still rising during the pass; otherwise P2. It clears itself (resolved
    `system` / `drained`) below 70% or when the contact ends and drains; not acknowledgeable.
  - `frames_dropped`: a transport that can't push back dropped frames because its buffer was
    full (data loss; none today, see `ReceiveBackpressure`). P1 while the pass is live and a drop
    happened in the last 5 minutes; otherwise P2. Any mission operator acknowledges it; it
    resolves (`user` / `acknowledged`) once acknowledged and the contact has ended.

  - `journal_disk` (ux U66): the disk every journal shares is filling (one item, id
    `journal_disk`). Caution from 70 %, P1 and critical from 90 % or while appends are refused
    for lack of space; it clears itself below 60 % (`system` / `drained`). Holders are this
    mission's contacts only, each `storing` (not yet all archived) or `kept` (archived, kept for
    review until `kept_until`); other missions' bytes are summed, never named.

  The id is `<conflict>:<realized_contact_id>:<provider_binding_id>` (`journal_disk` for the
  disk). State lives in the monitor, so it lasts the node's lifetime. Contract:
  docs/apogee/api/ops.md.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.{AttentionPasses, JournalReclaim, RealizedContact}
  alias Cadence.Runtime.Ingress, as: RuntimeIngress

  @source "ingress_backpressure"
  @disk_id "journal_disk"
  @p1_ratio 0.95
  @recent_drop_s 300

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    snapshot = RuntimeIngress.backpressure(mission)
    keys = Enum.map(snapshot.near_full, & &1.key) ++ Enum.map(snapshot.drops, & &1.key)
    context = context(org, mission, keys)
    now = DateTime.utc_now()

    Enum.map(snapshot.near_full, &near_full(&1, context, now)) ++
      Enum.map(snapshot.drops, &dropped(&1, context, now)) ++
      disk_items(org, mission, snapshot.disk)
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(_org, mission, %DateTime{} = since) do
    for %{key: {_mission, contact, binding}} = entry <-
          RuntimeIngress.backpressure(mission).resolved,
        DateTime.compare(entry.resolved_at, since) != :lt do
      %{
        id: id(entry.conflict, contact, binding),
        source: @source,
        resolved_by: entry.resolved_by,
        action: entry.action,
        resolved_at: entry.resolved_at
      }
    end ++
      for entry <- RuntimeIngress.backpressure(mission).disk_resolved,
          DateTime.compare(entry.resolved_at, since) != :lt do
        %{
          id: @disk_id,
          source: @source,
          resolved_by: %{"kind" => "system"},
          action: "drained",
          resolved_at: entry.resolved_at,
          refused_from: entry.refused_from,
          refused_to: entry.refused_to
        }
      end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: non_neg_integer()}
  def counts(_org, mission) do
    snapshot = RuntimeIngress.backpressure(mission)
    acknowledged = Enum.count(snapshot.drops, &(&1.acknowledged_by != nil))

    %{
      open:
        length(snapshot.near_full) + length(snapshot.drops) - acknowledged +
          if(snapshot.disk, do: 1, else: 0),
      acknowledged: acknowledged
    }
  end

  @doc "Acknowledges lost telemetry (`frames_dropped` only); anything else isn't found."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id) do
    with {:ok, "frames_dropped", contact, binding} <- parse(id),
         {:ok, actor} <- actor(scope, mission),
         {:ok, drop} <-
           RuntimeIngress.acknowledge_dropped_frames(mission, {mission, contact, binding}, actor) do
      context = context(scope.organization_id, mission, [drop.key])
      {:ok, dropped(drop, context, DateTime.utc_now())}
    else
      {:ok, _other_conflict, _contact, _binding} -> {:error, :attention_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Not an operator action for this source."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _action), do: {:error, :attention_item_not_found}

  # todo(authz): Cedar should decide who may acknowledge lost telemetry (any operator today).
  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  defp parse(id) do
    case String.split(id, ":", parts: 3) do
      [conflict, contact, binding] when contact != "" and binding != "" ->
        {:ok, conflict, contact, binding}

      _other ->
        {:error, :attention_item_not_found}
    end
  end

  defp id(conflict, contact, binding), do: "#{conflict}:#{contact}:#{binding}"

  defp near_full(%{key: {_mission, contact, binding}} = usage, context, now) do
    pass = pass(context, contact)

    base(context, "journal_near_full", contact, binding, usage.raised_at)
    |> Map.merge(%{
      state: "open",
      acknowledged_by: nil,
      journal_usage:
        Map.take(usage, [
          :used_bytes,
          :capacity_bytes,
          :ratio,
          :threshold,
          :backlog_bytes,
          :observed_at,
          :rising
        ]),
      drops: nil,
      diagnostics: %{stream_id: usage[:stream_id], last_error: usage[:last_error]},
      p1: usage.ratio >= @p1_ratio or (usage.rising and live?(pass, now))
    })
    |> Map.merge(pass)
  end

  defp dropped(%{key: {_mission, contact, binding}} = drop, context, now) do
    pass = pass(context, contact)

    base(context, "frames_dropped", contact, binding, drop.first_at)
    |> Map.merge(%{
      state: if(drop.acknowledged_by, do: "acknowledged", else: "open"),
      acknowledged_by: drop.acknowledged_by,
      journal_usage: nil,
      drops: Map.take(drop, [:count, :bytes, :first_at, :last_at, :buffer]),
      diagnostics: %{stream_id: nil, last_error: nil},
      p1: live?(pass, now) and DateTime.diff(now, drop.last_at) <= @recent_drop_s
    })
    |> Map.merge(pass)
  end

  @doc false
  # The disk item from the monitor's view of it (public for its test; the monitor is global).
  def disk_items(_org, _mission, nil), do: []

  def disk_items(org, mission, disk) do
    context =
      context(org, mission, Enum.map(disk.holders, &{mission, &1.realized_contact_id, nil}))

    [
      %{
        id: @disk_id,
        source: @source,
        conflict: @disk_id,
        state: "open",
        acknowledged_by: nil,
        raised_at: disk.raised_at,
        p1: disk.level == :critical or disk.refusing,
        journal_disk:
          disk
          |> Map.take([
            :percent,
            :used_bytes,
            :size_bytes,
            :rate_bytes_per_hour,
            :eta_full_s,
            :more_count,
            :other_missions_bytes,
            :refusing,
            :refused_since
          ])
          |> Map.put(:holders, Enum.map(disk.holders, &holder(&1, context))),
        provider_message: nil,
        resolution: nil
      }
    ]
  end

  # 'kept': settled and archived, on disk only for the review window (or until early removal
  # under pressure); 'storing': anything else (live, or not yet all in the archive).
  defp holder(%{realized_contact_id: contact, bytes: bytes}, context) do
    {state, kept_until} = holder_state(Map.get(context.contacts, contact))

    context
    |> pass(contact)
    |> Map.take([:spacecraft_id, :ground_station_ref, :provider_id, :starts_at, :ends_at])
    |> Map.merge(%{
      realized_contact_id: contact,
      contact_id: scheduled_contact_id(context, contact),
      bytes: bytes,
      state: state,
      kept_until: kept_until
    })
  end

  defp holder_state(%RealizedContact{metadata: metadata}) do
    settlement = Map.get(metadata || %{}, "settlement", %{})

    with "settled" <- settlement["state"],
         nil <- settlement["journal_disk"],
         {:ok, settled_at, _offset} <- DateTime.from_iso8601(settlement["settled_at"] || "") do
      kept_until = DateTime.add(settled_at, JournalReclaim.retention_ms(), :millisecond)
      {"kept", DateTime.truncate(kept_until, :second)}
    else
      _storing -> {"storing", nil}
    end
  end

  defp holder_state(nil), do: {"storing", nil}

  defp base(context, conflict, contact, binding, raised_at) do
    %{
      id: id(conflict, contact, binding),
      source: @source,
      conflict: conflict,
      realized_contact_id: contact,
      contact_id: scheduled_contact_id(context, contact),
      contact_label: nil,
      transport: %{provider_binding_id: binding, kind: transport_kind(context, contact, binding)},
      raised_at: raised_at,
      provider_message: nil,
      resolution: nil
    }
  end

  defp live?(%{starts_at: %DateTime{} = starts, ends_at: %DateTime{} = ends}, now),
    do: DateTime.compare(starts, now) != :gt and DateTime.compare(ends, now) == :gt

  defp live?(_pass, _now), do: false

  # Each contact's record and its booking, looked up once per read (shared with replay_conflict).
  defp context(org, mission, keys) do
    contacts = keys |> Enum.map(fn {_mission, contact, _binding} -> contact end) |> Enum.uniq()
    AttentionPasses.context(org, mission, contacts)
  end

  defp scheduled_contact_id(context, contact),
    do: AttentionPasses.scheduled_contact_id(context, contact)

  defp pass(context, contact), do: AttentionPasses.pass(context, contact)

  defp transport_kind(context, contact, binding) do
    with %RealizedContact{paths: paths} <- Map.get(context.contacts, contact),
         %{adapter_key: key} <-
           paths
           |> Enum.flat_map(&(&1.provider_bindings || []))
           |> Enum.find(&(&1.provider_binding_id == binding)) do
      if key == :tcp_socket, do: "tcp", else: to_string(key)
    else
      _unknown -> nil
    end
  end
end

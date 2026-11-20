defmodule Cadence.Contacts.ReplayConflictAttention do
  @moduledoc """
  The `replay_conflict` source of the mission attention read (#99 follow-up, director GO 11-17;
  ux U84 'Stuck processing'): a unit that #99's tripwire stopped, from its durable record
  (`Cadence.Runtime.ReplayConflicts`). One item per stalled unit; its id is the unit's oldest open
  record. It's a fault in Cadence: nothing in the console fixes it, so the only action is
  Acknowledge, with an optional note ('who you told'). An acknowledged item reads open again
  (`reraised`) once its buffer starts dropping new telemetry. It resolves when the unit commits.
  Contract: docs/apogee/api/contacts.md.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.AttentionPasses
  alias Cadence.Runtime.ReplayConflicts

  @source "replay_conflict"
  @conflict "replay_id_conflict"
  @note_max 500
  @system %{kind: "system", id: nil, name: nil}

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    rows = ReplayConflicts.open(mission)
    passes = passes(org, mission, rows)
    # #146: whoever acknowledged is named at read time, in the mission's organization.
    people = MemberNames.members(org, rows |> Enum.map(&acknowledger/1) |> Enum.reject(&is_nil/1))

    rows
    |> units()
    |> Enum.map(&item(&1, passes, people))
    |> Enum.sort_by(& &1.raised_at, DateTime)
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: non_neg_integer()}
  def counts(org, mission) do
    items = items(org, mission)

    %{
      open: Enum.count(items, &(&1.state == "open")),
      acknowledged: Enum.count(items, &(&1.state == "acknowledged"))
    }
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    rows = ReplayConflicts.resolved_since(mission, since)
    passes = passes(org, mission, rows)

    for [first | _] = unit <- units(rows) do
      %{
        id: first.id,
        source: @source,
        conflict: @conflict,
        path: first.path,
        spacecraft_ids: spacecraft_ids(first, passes),
        resolved_at: unit |> Enum.map(& &1.resolved_at) |> Enum.max(DateTime),
        resolved_by: @system,
        action: "resumed"
      }
    end
  end

  @doc "Acknowledge without a note (the generic route)."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id), do: acknowledge(scope, mission, id, nil)

  @doc "Acknowledge the item's unit, with an optional plain-text note (500 at most)."
  @spec acknowledge(Scope.t(), binary(), binary(), term()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id, note) do
    # Permission first: a non-operator gets 403, never invalid_note (fe-ops).
    with {:ok, actor} <- actor(scope, mission),
         {:ok, note} <- note(note),
         [_ | _] = unit <- unit_of(ReplayConflicts.open(mission), id) do
      :ok = ReplayConflicts.acknowledge(mission, Enum.map(unit, & &1.id), actor, note)
      item = scope.organization_id |> items(mission) |> Enum.find(&(&1.id == id))
      if item, do: {:ok, item}, else: {:error, :attention_item_not_found}
    else
      [] -> {:error, :attention_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Not an operator action for this source: the fix is in Cadence (ux U84)."
  @spec resolve(Scope.t(), binary(), binary(), String.t() | nil) ::
          {:error, :attention_item_not_found}
  def resolve(_scope, _mission, _id, _action), do: {:error, :attention_item_not_found}

  defp note(nil), do: {:ok, nil}

  defp note(note) when is_binary(note) do
    case String.trim(note) do
      "" -> {:ok, nil}
      text -> if String.length(text) <= @note_max, do: {:ok, text}, else: {:error, :invalid_note}
    end
  end

  defp note(_note), do: {:error, :invalid_note}

  # todo(authz): Cedar should decide who may acknowledge stuck processing (any operator today).
  # Stored as kind and id only: the name comes from the live membership on read (#146).
  defp actor(%Scope{user: %{user_id: id}} = scope, mission) when is_binary(id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id}}
  end

  defp actor(%Scope{}, _mission), do: {:error, :forbidden}

  # Only a person acknowledges (`actor/2`): stored as kind and id, named from the live membership.
  defp acknowledger(%{acknowledged_by: %{"kind" => "user", "id" => id}}) when is_binary(id),
    do: id

  defp acknowledger(_row), do: nil

  defp acknowledged_by(row, people) do
    with id when is_binary(id) <- acknowledger(row),
         {:ok, name} <- Map.fetch(people, id) do
      %{kind: "user", id: id, name: name}
    else
      _outsider -> %{kind: "user", id: nil, name: nil}
    end
  end

  # One unit per (path, unit key), its rows oldest first.
  defp units(rows) do
    rows
    |> Enum.group_by(&{&1.path, &1.unit_key})
    |> Map.values()
    |> Enum.map(&oldest_first/1)
  end

  defp oldest_first(rows),
    do: Enum.sort_by(rows, &{DateTime.to_unix(&1.first_seen_at, :microsecond), &1.id})

  defp unit_of(rows, id) do
    case Enum.find(rows, &(&1.id == id)) do
      %{path: path, unit_key: key} ->
        Enum.filter(rows, &(&1.path == path and &1.unit_key == key))

      nil ->
        []
    end
  end

  defp passes(org, mission, rows) do
    contacts = rows |> Enum.map(& &1.realized_contact_id) |> Enum.reject(&is_nil/1)
    AttentionPasses.context(org, mission, contacts)
  end

  defp item([first | _] = unit, passes, people) do
    pass = pass(first, passes)

    acked =
      unit
      |> Enum.filter(& &1.acknowledged_at)
      |> Enum.max_by(& &1.acknowledged_at, DateTime, fn -> nil end)

    dropping_since = unit |> Enum.map(& &1.dropping_since) |> Enum.reject(&is_nil/1) |> min_time()
    reraised = reraised?(acked, dropping_since)
    ids = spacecraft_ids(first, passes)

    %{
      id: first.id,
      source: @source,
      conflict: @conflict,
      state: if(acked && not reraised, do: "acknowledged", else: "open"),
      raised_at: first.first_seen_at,
      acknowledged_by: acked && acknowledged_by(acked, people),
      acknowledged_at: acked && acked.acknowledged_at,
      acknowledged_note: acked && acked.acknowledged_note,
      reraised: reraised,
      resolution: nil,
      path: first.path,
      effect_kind: effect_kind(first.effect_kind),
      effect_id: first.effect_id,
      effect_count: length(unit),
      partition_id: first.partition_id,
      partition_stopped: Enum.any?(unit, & &1.partition_stopped),
      stopped_while:
        unit |> Enum.max_by(& &1.last_conflict_at, DateTime) |> Map.get(:stopped_while),
      realized_contact_id: first.realized_contact_id,
      path_id: first.path_id,
      provider_binding_id: first.provider_binding_id,
      stream_key: first.stream_key,
      contact_id: pass[:contact_id],
      ground_station_ref: pass[:ground_station_ref],
      starts_at: pass[:starts_at],
      spacecraft_ids: ids,
      spacecraft_count: length(ids),
      first_seen_at: first.first_seen_at,
      last_seen_at: unit |> Enum.map(& &1.last_conflict_at) |> Enum.max(DateTime),
      occurrences: unit |> Enum.map(& &1.conflict_count) |> Enum.sum(),
      buffer: buffer(unit),
      dropping: not is_nil(dropping_since),
      dropping_since: dropping_since
    }
  end

  defp reraised?(nil, _dropping_since), do: false
  defp reraised?(_acked, nil), do: false

  defp reraised?(%{acknowledged_at: at}, dropping_since),
    do: DateTime.compare(dropping_since, at) == :gt

  defp min_time([]), do: nil
  defp min_time(times), do: Enum.min(times, DateTime)

  defp buffer(unit) do
    case Enum.find(
           unit,
           &(is_integer(&1.buffer_max_bytes) and is_integer(&1.buffer_retained_bytes))
         ) do
      %{} = row -> %{used_bytes: row.buffer_retained_bytes, max_bytes: row.buffer_max_bytes}
      nil -> nil
    end
  end

  defp effect_kind(kind) when kind in ["alarm_episode", "alarm_event"], do: "alarm_effect"
  defp effect_kind(kind), do: kind

  defp pass(%{realized_contact_id: nil}, _passes), do: %{}

  defp pass(%{realized_contact_id: contact}, passes) do
    passes
    |> AttentionPasses.pass(contact)
    |> Map.put(:contact_id, AttentionPasses.scheduled_contact_id(passes, contact))
  end

  # At least these: the pass's craft. A partition is keyed by source endpoint, so a timer unit
  # names none ('not known yet'); the words say 'and may affect others' (ux U84).
  defp spacecraft_ids(row, passes) do
    case pass(row, passes) do
      %{spacecraft_id: id} when is_binary(id) -> [id]
      _none -> []
    end
  end
end

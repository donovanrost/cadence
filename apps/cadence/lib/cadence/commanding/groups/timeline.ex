defmodule Cadence.Commanding.Groups.Timeline do
  @moduledoc """
  The outcome half of a group's timeline (DECISIONS #51), the operators' audit
  record next to submitted / decision / note / abort events:

    * `member_failed`: once per member whose release failed or whose
      verification failed or timed out. Under stop on failure (#31) the later
      members of that target won't release; the payload counts them.
    * `completed`: once, when every member of a queued or aborted group is
      final (released with verification settled, release failed, canceled or
      rejected). An uncertain release isn't final: an operator must resolve it.

  Outcomes are read from the stored rows, so this works the same whichever path
  finished a member. Event ids derive from the member or group and are inserted
  with `on_conflict: :nothing`, so the post-release and verifier hooks and the
  reconcile sweep can all call `settle/3` without writing an event twice.
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandReleaseAttemptRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.{CommandGroupEventRow, CommandGroupRow, GroupStore}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  require Logger

  @open_states ~w(queued aborted)
  @sweep_limit 200
  @actor %{"actor_kind" => "system"}

  @doc "Settles the groups of the given member requests. Never raises; returns `:ok`."
  @spec settle_requests(binary(), binary(), [binary()]) :: :ok
  def settle_requests(_org, _mission, []), do: :ok

  def settle_requests(org, mission, request_ids) do
    if Repo.in_transaction?() do
      # The sweep picks it up; events are only written after the outcome commits.
      :ok
    else
      CommandRequestRow
      |> where(
        [r],
        r.organization_id == ^org and r.mission_id == ^mission and
          r.command_request_id in ^request_ids and not is_nil(r.command_group_id)
      )
      |> select([r], r.command_group_id)
      |> distinct(true)
      |> Repo.all()
      |> Enum.each(&safe_settle(org, mission, &1))
    end
  end

  @doc "Settles one group after a commit. Never raises; returns `:ok`."
  @spec settle_group(binary(), binary(), binary()) :: :ok
  def settle_group(org, mission, group_id) do
    if !Repo.in_transaction?(), do: safe_settle(org, mission, group_id)
    :ok
  end

  @doc """
  The reconcile sweep: settles queued and aborted groups that have no
  `completed` event yet (oldest first, bounded per run). Returns how many
  events it wrote.
  """
  @spec settle_open() :: non_neg_integer()
  def settle_open do
    completed =
      from(e in CommandGroupEventRow,
        where: e.kind == "completed",
        select: e.command_group_id
      )

    CommandGroupRow
    |> where([g], g.state in @open_states and g.command_group_id not in subquery(completed))
    |> order_by([g], asc: g.requested_at)
    |> limit(@sweep_limit)
    |> select([g], {g.organization_id, g.mission_id, g.command_group_id})
    |> Repo.all()
    |> Enum.reduce(0, fn {org, mission, id}, total -> total + safe_settle(org, mission, id) end)
  end

  @doc "Writes any missing `member_failed` / `completed` events for one group. Returns how many."
  @spec settle(binary(), binary(), binary()) :: non_neg_integer()
  def settle(org, mission, group_id) do
    with {:ok, group} <- GroupStore.fetch(org, mission, group_id),
         true <- Atom.to_string(group.state) in @open_states do
      members = members(org, mission, group_id)
      outcomes = outcomes(org, mission, members)
      # `completed` sorts after the failures it closes over.
      now = DateTime.utc_now()

      events =
        failure_events(group, members, outcomes, now) ++
          completion(group, outcomes, DateTime.add(now, 1, :microsecond))

      inserted = insert(events)
      if inserted > 0, do: ScopedReadUpdates.publish(:commanding_changed, org, mission)
      inserted
    else
      _closed_or_missing -> 0
    end
  end

  defp safe_settle(org, mission, group_id) do
    settle(org, mission, group_id)
  rescue
    error ->
      Logger.error(
        "command group timeline settle failed for #{group_id}: #{Exception.message(error)}"
      )

      0
  end

  defp members(org, mission, group_id) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and r.command_group_id == ^group_id
    )
    |> order_by([r], asc: r.group_target_index, asc: r.group_position)
    |> Repo.all()
  end

  # `%{request_id => :open | :ok | :canceled | :rejected | {:failed, reason}}`
  defp outcomes(org, mission, members) do
    release_failed = release_failed(org, mission, Enum.map(members, & &1.command_request_id))

    Map.new(members, fn member ->
      {member.command_request_id,
       outcome(member, MapSet.member?(release_failed, member.command_request_id))}
    end)
  end

  # A member that radiated is judged by its verification; otherwise a failed release attempt
  # (including one the uplink refused, #33, which also cancels the request) is a failure.
  defp outcome(%{lifecycle_state: "released", verification_state: state}, _release_failed?) do
    case state do
      "failed" -> {:failed, "verify_failed"}
      "timed_out" -> {:failed, "verify_timed_out"}
      "satisfied" -> :verified
      "not_required" -> :no_verifier
      _pending -> :open
    end
  end

  defp outcome(_member, true), do: {:failed, "release_failed"}

  defp outcome(%{lifecycle_state: "canceled"} = member, false) do
    # DECISIONS #65: canceled by a catalog change set reads as its own outcome.
    case JsonDocument.unwrap_value(member.metadata_document) do
      %{"cancellation" => %{"reason" => "catalog_changed" <> _}} -> :catalog_changed
      _other -> :canceled
    end
  end

  defp outcome(%{lifecycle_state: "rejected"}, false), do: :rejected
  defp outcome(_member, false), do: :open

  defp release_failed(_org, _mission, []), do: MapSet.new()

  defp release_failed(org, mission, ids) do
    ids
    |> Enum.chunk_every(1000)
    |> Enum.flat_map(fn chunk ->
      CommandReleaseAttemptRow
      |> where(
        [a],
        a.organization_id == ^org and a.mission_id == ^mission and
          a.command_request_id in ^chunk and a.lifecycle_state == "release_failed"
      )
      |> select([a], a.command_request_id)
      |> Repo.all()
    end)
    |> MapSet.new()
  end

  defp failure_events(group, members, outcomes, at) do
    by_target = Enum.group_by(members, & &1.group_target_index)

    for member <- members,
        {:failed, reason} <- [Map.fetch!(outcomes, member.command_request_id)] do
      later =
        by_target
        |> Map.get(member.group_target_index, [])
        |> Enum.count(fn other ->
          other.group_position > member.group_position and
            (Map.fetch!(outcomes, other.command_request_id) == :open or
               halted_by?(other, member.command_request_id))
        end)

      event(group, "member_failed", member.command_request_id, at, %{
        "command_request_id" => member.command_request_id,
        "command_id" => member.command_id,
        "spacecraft_id" => spacecraft_id(group, member.group_target_index),
        "target_index" => member.group_target_index,
        "position" => member.group_position,
        "reason" => reason,
        "later_members_stopped" => later
      })
    end
  end

  # Halt cancels later members lazily, at their release time, naming the failed member.
  defp halted_by?(%{lifecycle_state: "canceled", metadata_document: document}, failed_id) do
    case JsonDocument.unwrap_value(document) do
      %{"cancellation" => %{"reason" => "earlier_command_failed: " <> ^failed_id}} -> true
      _other -> false
    end
  end

  defp halted_by?(_member, _failed_id), do: false

  defp completion(group, outcomes, at) do
    values = Map.values(outcomes)

    if values != [] and :open not in values do
      counts =
        Enum.frequencies_by(values, fn
          {:failed, reason} -> reason
          outcome -> Atom.to_string(outcome)
        end)

      [event(group, "completed", group.command_group_id, at, %{"members" => counts})]
    else
      []
    end
  end

  defp spacecraft_id(group, index) do
    Enum.find_value(group.targets, fn target ->
      if target["index"] == index, do: target["spacecraft_id"]
    end)
  end

  defp event(group, kind, key, at, payload) do
    %{
      at: at,
      event_id: "command_group_event_#{kind}_#{key}",
      command_group_id: group.command_group_id,
      mission_id: group.mission_id,
      kind: kind,
      actor: @actor,
      payload: payload
    }
  end

  defp insert([]), do: 0

  defp insert(events) do
    rows =
      Enum.map(events, fn event ->
        event
        |> CommandGroupEventRow.changeset()
        |> Ecto.Changeset.apply_action!(:insert)
        |> Map.take(CommandGroupEventRow.__schema__(:fields))
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, total ->
      {count, _} = Repo.insert_all(CommandGroupEventRow, chunk, on_conflict: :nothing)
      total + count
    end)
  end
end

defmodule Cadence.Commanding.Groups.Admission do
  @moduledoc """
  Builds and admits group members in bulk inside the caller's locked
  transaction: member requests from validated payloads, and queue entries in
  stack order per target lane (a target's K members share its lane, so they
  release in order at its contact).
  """

  alias Cadence.Commanding.{CommandQueueEntry, CommandRequest}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Ids

  @doc "Member requests for a group from `Validation` members, in `state`."
  @spec members(binary(), [map()], atom()) :: [CommandRequest.t()]
  def members(group_id, validated, state) do
    :ok = uniform_expiry!(validated)

    Enum.map(validated, fn member ->
      %{
        member.request
        | command_request_id: Ids.new("command_request"),
          lifecycle_state: state,
          command_group_id: group_id,
          group_target_index: member.target_index,
          group_position: member.position
      }
    end)
  end

  @doc """
  Tripwire for DECISIONS #97 (an expired member halts its group): every member of a group shares
  the group's one `expires_at`. So when one expires, every later member of its target expires at
  the same instant and ends `expired` itself, and no later member is ever left to release
  without it. Per-member expiry would break that: it needs #97's HELD = BLOCKED hold (later
  members excluded from release on every path until an operator acts) built FIRST. Raises
  rather than admit a group with mixed expiry.
  """
  @spec uniform_expiry!([map()]) :: :ok
  def uniform_expiry!(validated) do
    case validated |> Enum.map(& &1.request.expires_at) |> Enum.uniq() do
      distinct when length(distinct) <= 1 ->
        :ok

      distinct ->
        raise ArgumentError,
              "DECISIONS #97: a group's members must share one expires_at (got " <>
                "#{length(distinct)} distinct); per-member expiry needs HELD = BLOCKED first"
    end
  end

  @doc """
  Queue entries for already-persisted `requests` (all `:queued`), allocating
  each lane's next sequences under its lane lock. `metadata_for` adds per-entry
  metadata (the approved content hash on the decision path).
  """
  @spec enqueue([CommandRequest.t()], map(), (CommandRequest.t() -> map())) :: [
          CommandQueueEntry.t()
        ]
  def enqueue(requests, enqueued_by, metadata_for \\ fn _request -> %{} end)

  def enqueue([], _enqueued_by, _metadata_for), do: []

  def enqueue([first | _] = requests, enqueued_by, metadata_for) do
    org = first.organization_id
    mission = first.mission_id
    next = GroupStore.reserve_lanes(org, mission, Enum.map(requests, & &1.source_endpoint_ref))
    now = DateTime.utc_now()

    {entries, _next} =
      requests
      |> Enum.sort_by(&{&1.group_target_index, &1.group_position})
      |> Enum.map_reduce(next, fn request, next ->
        lane = request.source_endpoint_ref
        sequence = Map.fetch!(next, lane)

        {entry(request, sequence, enqueued_by, now, metadata_for.(request)),
         Map.put(next, lane, sequence + 1)}
      end)

    :ok = GroupStore.insert_queue_entries(entries)
    entries
  end

  defp entry(request, sequence, enqueued_by, now, metadata) do
    CommandQueueEntry.new(%{
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      command_request_id: request.command_request_id,
      source_endpoint_ref: request.source_endpoint_ref,
      queue_lane_key: request.source_endpoint_ref,
      priority: request.priority,
      queue_sequence: sequence,
      not_before: request.not_before,
      expires_at: request.expires_at,
      lifecycle_state: :pending,
      enqueued_by: enqueued_by,
      enqueued_at: now,
      metadata: Map.merge(%{"command_group_id" => request.command_group_id}, metadata)
    })
  end
end

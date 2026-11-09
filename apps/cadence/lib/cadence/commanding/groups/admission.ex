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
    Enum.map(validated, fn member ->
      group = %{
        "id" => group_id,
        "target_index" => member.target_index,
        "position" => member.position
      }

      %{
        member.request
        | command_request_id: Ids.new("command_request"),
          lifecycle_state: state,
          metadata: Map.put(member.request.metadata, "group", group)
      }
    end)
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
      |> Enum.sort_by(&{&1.metadata["group"]["target_index"], &1.metadata["group"]["position"]})
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
      metadata: Map.merge(%{"command_group_id" => request.metadata["group"]["id"]}, metadata)
    })
  end
end

defmodule Cadence.Commanding.RequestActivity do
  @moduledoc """
  Command requests by source endpoint: which endpoints ever had requests (spacecraft traffic,
  #49/#50), and which still wait to release or are in flight (catalog changes, #36/#65).
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Repo

  @not_yet_queued ~w(validated approval_pending approved)

  @spec endpoints_with_requests(binary(), binary(), [binary()]) :: MapSet.t()
  def endpoints_with_requests(_organization_id, _mission_id, []), do: MapSet.new()

  def endpoints_with_requests(organization_id, mission_id, endpoint_refs) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.source_endpoint_ref in ^endpoint_refs
    )
    |> distinct(true)
    |> select([r], r.source_endpoint_ref)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Requests on these endpoints that haven't started to release (the ones `Cancellation.cancel/5`
  can cancel): `[%{command_request_id, command_group_id, command_name, lifecycle_state}]`.
  """
  @spec waiting(binary(), binary(), [binary()]) :: [map()]
  def waiting(_organization_id, _mission_id, []), do: []

  def waiting(organization_id, mission_id, endpoint_refs) do
    from(r in CommandRequestRow,
      left_join: q in CommandQueueEntryRow,
      on: q.command_request_id == r.command_request_id and q.mission_id == r.mission_id,
      where:
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.source_endpoint_ref in ^endpoint_refs and
          (r.lifecycle_state in ^@not_yet_queued or
             (r.lifecycle_state == "queued" and q.lifecycle_state == "pending")),
      order_by: [asc: r.command_request_id],
      select: %{
        command_request_id: r.command_request_id,
        command_group_id: r.command_group_id,
        command_name: r.command_name,
        lifecycle_state: r.lifecycle_state
      }
    )
    |> Repo.all()
  end

  @doc "How many requests wait on each endpoint (`waiting/3`'s rule): `%{endpoint_ref => count}`."
  @spec waiting_counts(binary(), binary(), [binary()]) :: %{binary() => pos_integer()}
  def waiting_counts(_organization_id, _mission_id, []), do: %{}

  def waiting_counts(organization_id, mission_id, endpoint_refs) do
    from(r in CommandRequestRow,
      left_join: q in CommandQueueEntryRow,
      on: q.command_request_id == r.command_request_id and q.mission_id == r.mission_id,
      where:
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.source_endpoint_ref in ^endpoint_refs and
          (r.lifecycle_state in ^@not_yet_queued or
             (r.lifecycle_state == "queued" and q.lifecycle_state == "pending")),
      group_by: r.source_endpoint_ref,
      select: {r.source_endpoint_ref, count(r.command_request_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Requests on these endpoints releasing or radiating right now: a queue entry mid-release, or a
  released request still waiting on its verification.
  """
  @spec in_flight(binary(), binary(), [binary()]) :: [map()]
  def in_flight(_organization_id, _mission_id, []), do: []

  def in_flight(organization_id, mission_id, endpoint_refs) do
    from(r in CommandRequestRow,
      left_join: q in CommandQueueEntryRow,
      on: q.command_request_id == r.command_request_id and q.mission_id == r.mission_id,
      where:
        r.organization_id == ^organization_id and r.mission_id == ^mission_id and
          r.source_endpoint_ref in ^endpoint_refs and
          (q.lifecycle_state == "release_pending" or
             (r.lifecycle_state == "released" and r.verification_state == "pending")),
      order_by: [asc: r.command_request_id],
      select: %{
        command_request_id: r.command_request_id,
        command_group_id: r.command_group_id,
        command_name: r.command_name
      }
    )
    |> Repo.all()
  end
end

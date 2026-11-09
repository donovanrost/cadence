defmodule Cadence.Reads.CommandCounts do
  @moduledoc """
  Mission command-pipeline counts for status tiles.

  `queued` covers requests waiting to release (queued or release pending),
  `in_flight` covers released requests awaiting verification, and
  `approval_pending` counts requests waiting on a second operator.
  `awaiting_viewer` counts approval-pending requests the viewer did not request
  themselves (an operator cannot approve their own request).
  """

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Reads.Commands

  @spec load(binary(), binary(), binary() | nil) :: map()
  def load(organization_id, mission_id, viewer_user_id) do
    summary = Commands.summary(organization_id, mission_id)
    requests = Cadence.Commanding.list_command_requests(organization_id, mission_id)

    build(summary, requests, viewer_user_id)
  end

  @spec build(map(), [CommandRequest.t()], binary() | nil) :: map()
  def build(summary, requests, viewer_user_id) do
    pending = Enum.filter(requests, &(&1.lifecycle_state == :approval_pending))

    %{
      queued: summary.queued_count + summary.release_pending_count,
      in_flight: summary.in_flight_count,
      failed: summary.failed_count + summary.indeterminate_count,
      approval_pending: length(pending),
      awaiting_viewer: Enum.count(pending, &(requester_id(&1) != viewer_user_id))
    }
  end

  @doc "The requesting user's id, or `nil` when the request does not record one."
  @spec requester_id(CommandRequest.t()) :: binary() | nil
  def requester_id(%CommandRequest{requested_by: requested_by}) when is_map(requested_by) do
    Map.get(requested_by, "id") || Map.get(requested_by, :id) ||
      Map.get(requested_by, "user_id") || Map.get(requested_by, :user_id)
  end

  def requester_id(%CommandRequest{}), do: nil
end

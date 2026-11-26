defmodule Cadence.Reads.CommandCounts do
  @moduledoc """
  Mission command-pipeline counts for status tiles.

  `queued` covers requests waiting to release (queued or release pending),
  `in_flight` covers released requests awaiting verification, and
  `approval_pending` counts command groups waiting on a second operator.
  `awaiting_viewer` counts those the viewer may decide (an operator cannot approve their own group).
  """

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Reads.{CommandGroups, Commands}

  @spec load(binary(), binary(), binary() | nil) :: map()
  def load(organization_id, mission_id, viewer_user_id) do
    summary = Commands.summary(organization_id, mission_id)
    groups = GroupStore.list(organization_id, mission_id, states: [:approval_pending])

    build(summary, viewer_user_id, groups)
  end

  @doc """
  Approvals count **decisions**: a command group waiting for its second GO is one however many
  members it has.
  """
  @spec build(map(), binary() | nil, [map()]) :: map()
  def build(summary, viewer_user_id, groups \\ []) do
    groups = Enum.filter(groups, &(&1.state == :approval_pending))

    %{
      queued: summary.queued_count + summary.release_pending_count,
      in_flight: summary.in_flight_count,
      failed: summary.failed_count + summary.indeterminate_count,
      approval_pending: length(groups),
      awaiting_viewer: Enum.count(groups, &CommandGroups.awaiting?(&1, viewer_user_id))
    }
  end
end

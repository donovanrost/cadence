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
    organization_id
    |> load_for_viewers(mission_id, [viewer_user_id])
    |> Map.fetch!(viewer_user_id)
  end

  @doc """
  The counts for each of `viewer_user_ids`, keyed by viewer, from one read of the mission's
  commands: only `awaiting_viewer` differs by viewer, and it is built in memory. For a push that
  serves many viewers of one mission at once (the live fleet push, #798).
  """
  @spec load_for_viewers(binary(), binary(), [binary() | nil]) :: %{(binary() | nil) => map()}
  def load_for_viewers(organization_id, mission_id, viewer_user_ids) do
    summary = Commands.summary(organization_id, mission_id)
    groups = GroupStore.list(organization_id, mission_id, states: [:approval_pending])

    Map.new(Enum.uniq(viewer_user_ids), &{&1, build(summary, &1, groups)})
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

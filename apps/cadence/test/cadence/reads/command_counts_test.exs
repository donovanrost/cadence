defmodule Cadence.Reads.CommandCountsTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.Groups.CommandGroup
  alias Cadence.Reads.CommandCounts

  @summary %{
    queued_count: 0,
    release_pending_count: 0,
    in_flight_count: 0,
    failed_count: 0,
    indeterminate_count: 0
  }

  defp group(id, requester),
    do: %CommandGroup{
      command_group_id: id,
      state: :approval_pending,
      requested_by: %{"user_id" => requester}
    }

  test "a pending group counts once; the requester's own group isn't awaiting them" do
    assert %{approval_pending: 1, awaiting_viewer: 1} =
             CommandCounts.build(@summary, "viewer", [group("g1", "other")])

    assert %{approval_pending: 1, awaiting_viewer: 0} =
             CommandCounts.build(@summary, "other-2", [group("g1", "other-2")])
  end
end

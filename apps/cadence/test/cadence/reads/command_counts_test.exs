defmodule Cadence.Reads.CommandCountsTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Commanding.Groups.CommandGroup
  alias Cadence.Reads.CommandCounts

  @summary %{
    queued_count: 0,
    release_pending_count: 0,
    in_flight_count: 0,
    failed_count: 0,
    indeterminate_count: 0
  }

  defp request(id, requester, group \\ nil) do
    %CommandRequest{
      command_request_id: id,
      mission_id: "m",
      lifecycle_state: :approval_pending,
      requested_by: %{"user_id" => requester},
      metadata: if(group, do: %{"group" => %{"id" => group}}, else: %{})
    }
  end

  defp group(id, requester),
    do: %CommandGroup{
      command_group_id: id,
      state: :approval_pending,
      requested_by: %{"user_id" => requester}
    }

  test "a pending group counts once and its members don't; the requester's own group isn't awaiting them" do
    requests = [
      request("a", "other", "g1"),
      request("b", "other", "g1"),
      request("solo", "other")
    ]

    assert %{approval_pending: 2, awaiting_viewer: 2} =
             CommandCounts.build(@summary, requests, "viewer", [group("g1", "other")])

    assert %{approval_pending: 2, awaiting_viewer: 1} =
             CommandCounts.build(@summary, requests, "other-2", [group("g1", "other-2")])
  end
end

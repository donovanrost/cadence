defmodule Cadence.Commanding.ListFiltersTest do
  @moduledoc """
  #1051: what a command group's preflight and read need of the queue, they ask SQL for: the open
  work on their own lanes, their own members' rows, never the mission's whole history.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.MissionModels
  alias Cadence.Reads.CommandPreflight

  setup do
    c = setup!(3)
    [first, second, third] = c.spacecraft

    submit = fn craft ->
      draft = draft([craft], [command(c, "SET_SIGNED", %{"counter" => 1})])

      {:ok, group} =
        GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

      group
    end

    Map.merge(c, %{first: first, second: second, third: third, submit: submit})
  end

  defp lane(craft), do: Cadence.SourceEndpoints.managed_source_endpoint_id(craft)

  test "queue entries by lane, by state and by request", c do
    one = c.submit.(c.first)
    c.submit.(c.second)

    assert [%{queue_lane_key: lane}] =
             Commanding.list_command_queue_entries(c.org, c.mission,
               queue_lane_keys: [lane(c.first), lane(c.third)]
             )

    assert lane == lane(c.first)
    assert Commanding.list_command_queue_entries(c.org, c.mission, queue_lane_keys: []) == []

    assert Commanding.list_command_queue_entries(c.org, c.mission,
             queue_lane_keys: [lane(c.first)],
             lifecycle_states: [:released, :cancelled]
           ) == []

    assert [_] =
             Commanding.list_command_queue_entries(c.org, c.mission,
               queue_lane_keys: [lane(c.first)],
               lifecycle_states: [:pending, :release_pending]
             )

    [member] =
      GroupStore.members(c.org, c.mission, one.command_group_id)

    assert [%{command_request_id: id}] =
             Commanding.list_command_queue_entries(c.org, c.mission,
               command_request_ids: [member.command_request_id]
             )

    assert id == member.command_request_id

    assert Commanding.list_command_release_attempts(c.org, c.mission, command_request_ids: [id]) ==
             []

    assert Commanding.list_command_verifier_instances(c.org, c.mission, command_request_ids: [id]) ==
             []
  end

  test "requests by lane", c do
    c.submit.(c.first)
    c.submit.(c.second)

    assert [%{source_endpoint_ref: ref}] =
             Commanding.list_command_requests(c.org, c.mission,
               source_endpoint_refs: [lane(c.second)]
             )

    assert ref == lane(c.second)
  end

  test "conflicts are the open work on the group's own lanes", c do
    queued = c.submit.(c.first)
    c.submit.(c.second)

    {:ok, %{checks: checks}} =
      CommandPreflight.run(
        c.org,
        c.mission,
        actor(c),
        draft([c.first], [command(c, "SET_SIGNED", %{"counter" => 2})])
      )

    assert %{result: :hold, evidence: %{count: 1}} = Enum.find(checks, &(&1.key == :conflicts))

    {:ok, %{checks: other}} =
      CommandPreflight.run(
        c.org,
        c.mission,
        actor(c),
        draft([c.third], [command(c, "SET_SIGNED", %{"counter" => 2})])
      )

    assert %{result: :go} = Enum.find(other, &(&1.key == :conflicts))
    assert queued.command_group_id
  end

  test "the runtime plans of a revision, in one read; the first missing target is the error", c do
    assert {:ok, plans} = MissionModels.fetch_runtime_plans(c.org, c.mission, c.revision_id)
    assert Map.keys(plans) |> Enum.sort() == [:algorithm, :command, :monitoring, :telemetry]

    assert {:error, {:telemetry, :mission_model_runtime_plan_not_found}} =
             MissionModels.fetch_runtime_plans(c.org, c.mission, "no-such-revision")
  end
end

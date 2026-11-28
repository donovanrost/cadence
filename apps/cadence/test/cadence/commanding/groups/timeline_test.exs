defmodule Cadence.Commanding.Groups.TimelineTest do
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{
    Cancellation,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Commanding.Groups.{GroupStore, Timeline}
  alias Cadence.Control.Commanding.{GroupAbort, GroupSubmission}

  setup do
    c = setup!(2)
    Map.put(c, :approver, operator!(c))
  end

  defp submit(c, commands, extra \\ %{}) do
    draft = draft(c.spacecraft, commands, extra)

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {group, GroupStore.members(c.org, c.mission, group.command_group_id)}
  end

  defp signed(c, counter), do: command(c, "SET_SIGNED", %{"counter" => counter})

  defp kinds(c, group) do
    c.mission
    |> GroupStore.events(group.command_group_id)
    |> Enum.map(& &1.kind)
  end

  defp event(c, group, kind),
    do: c.mission |> GroupStore.events(group.command_group_id) |> Enum.find(&(&1.kind == kind))

  # What the release path stores when a member radiates (verification settled as given).
  defp released!(member, verification) do
    CommandRequestRow
    |> where([r], r.command_request_id == ^member.command_request_id)
    |> Repo.update_all(set: [lifecycle_state: "released", verification_state: verification])
  end

  defp release_failed!(c, member) do
    %CommandQueueEntryRow{command_queue_entry_id: entry_id} =
      Repo.get_by!(CommandQueueEntryRow, command_request_id: member.command_request_id)

    CommandReleaseAttempt.new(%{
      organization_id: c.org,
      mission_id: c.mission,
      command_queue_entry_id: entry_id,
      command_request_id: member.command_request_id,
      source_endpoint_ref: member.source_endpoint_ref,
      realized_contact_id: "contact-1",
      mission_model_revision_id: member.mission_model_revision_id,
      command_id: member.command_id,
      lifecycle_state: :release_failed,
      released_by: %{},
      attempted_at: DateTime.utc_now()
    })
    |> CommandReleaseAttemptRow.changeset()
    |> Repo.insert!()
  end

  test "completed is written once, when every member is final", c do
    {group, [first, second]} = submit(c, [signed(c, 1)])

    released!(first, "not_required")
    assert Timeline.settle(c.org, c.mission, group.command_group_id) == 0
    assert kinds(c, group) == [:submitted]

    released!(second, "satisfied")
    assert Timeline.settle(c.org, c.mission, group.command_group_id) == 1
    assert Timeline.settle(c.org, c.mission, group.command_group_id) == 0

    assert kinds(c, group) == [:submitted, :completed]

    assert %{actor: actor, payload: %{"members" => %{"no_verifier" => 1, "verified" => 1}}} =
             event(c, group, :completed)

    # Explicit system actor, no invented user (director, qa #29).
    assert actor == %{"actor_kind" => "system"}
  end

  # #795: the member row says why it failed, from the same fact the member_failed event does, so
  # a card needn't find that event in a paged log.
  test "a failed member's row carries the reason its member_failed event states", c do
    for {state, reason} <- [{"failed", "verify_failed"}, {"timed_out", "verify_timed_out"}] do
      {group, [member | _]} = submit(c, [signed(c, 1)])
      released!(member, state)
      Timeline.settle_requests(c.org, c.mission, [member.command_request_id])

      assert %{payload: %{"reason" => ^reason}} = event(c, group, :member_failed)

      {:ok, view} =
        Cadence.Reads.CommandGroups.get(c.org, c.mission, group.command_group_id, nil)

      assert [%{stage: :verify_failed, members: [%{failure_reason: failure}]} | _] = view.targets
      assert Atom.to_string(failure) == reason
    end
  end

  test "a failed verification writes member_failed, counting the later members it stops", c do
    {group, [first, second | _]} = submit(c, [signed(c, 1), signed(c, 2)])
    assert first.group_slot.target_index == second.group_slot.target_index

    released!(first, "failed")
    Timeline.settle_requests(c.org, c.mission, [first.command_request_id])

    assert %{
             payload: %{
               "command_request_id" => id,
               "reason" => "verify_failed",
               "spacecraft_id" => "sc-1",
               "position" => 0,
               "later_members_stopped" => 1
             }
           } = event(c, group, :member_failed)

    assert id == first.command_request_id
    refute event(c, group, :completed)

    # Halt cancels the later member at its release time; the count still names it.
    {:ok, :ok} =
      Repo.transaction(fn ->
        Cancellation.fail_closed(
          c.org,
          c.mission,
          second.command_request_id,
          "earlier_command_failed: " <> first.command_request_id
        )
      end)

    Timeline.settle(c.org, c.mission, group.command_group_id)

    assert [%{payload: %{"later_members_stopped" => 1}}] =
             c.mission
             |> GroupStore.events(group.command_group_id)
             |> Enum.filter(&(&1.kind == :member_failed))
  end

  test "a release the uplink refused (#33: attempt failed, request canceled) is a failure", c do
    {group, [first, second]} = submit(c, [signed(c, 1)])
    release_failed!(c, first)

    CommandRequestRow
    |> where([r], r.command_request_id == ^first.command_request_id)
    |> Repo.update_all(set: [lifecycle_state: "canceled"])

    released!(second, "not_required")
    assert Timeline.settle(c.org, c.mission, group.command_group_id) == 2

    assert %{payload: %{"reason" => "release_failed"}} = event(c, group, :member_failed)

    assert %{payload: %{"members" => %{"release_failed" => 1, "no_verifier" => 1}}} =
             event(c, group, :completed)
  end

  test "a catalog change set's cancellation counts as catalog_changed when the group closes (#65)",
       c do
    {group, [first, second]} = submit(c, [signed(c, 1)])

    {:ok, _} =
      Repo.transaction(fn ->
        Cancellation.cancel(
          c.org,
          c.mission,
          [first.command_request_id],
          "catalog_changed: cs-1",
          %{
            "actor_kind" => "system",
            "id" => "change_set:cs-1"
          }
        )
      end)

    released!(second, "not_required")
    Timeline.settle(c.org, c.mission, group.command_group_id)

    assert %{payload: %{"members" => %{"catalog_changed" => 1, "no_verifier" => 1}}} =
             event(c, group, :completed)
  end

  test "a failed release is a member failure", c do
    {group, [first | _]} = submit(c, [signed(c, 1)])
    release_failed!(c, first)

    assert Timeline.settle(c.org, c.mission, group.command_group_id) == 1
    assert %{payload: %{"reason" => "release_failed"}} = event(c, group, :member_failed)
  end

  test "an aborted group completes once its members are canceled", c do
    {group, _members} = submit(c, [signed(c, 1)])
    {:ok, _} = GroupAbort.abort(c.approver, c.mission, group.command_group_id, "Stand down")

    # The abort hook settled it already.
    assert [:submitted, :aborted, :completed] = kinds(c, group)
    assert %{payload: %{"members" => %{"canceled" => 2}}} = event(c, group, :completed)
  end

  test "the sweep settles open groups and skips groups awaiting a decision", c do
    {group, members} = submit(c, [signed(c, 1)])
    {pending, _} = submit(c, [command(c, "SET_COUNTER", %{"amount" => 1})], %{log_entry: "x"})

    Enum.each(members, &released!(&1, "not_required"))

    assert Timeline.settle_open() == 1
    assert Timeline.settle_open() == 0
    assert :completed in kinds(c, group)
    assert kinds(c, pending) == [:submitted]
  end
end

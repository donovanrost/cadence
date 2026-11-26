defmodule Cadence.Control.Commanding.GroupMemberStandaloneApprovalTest do
  @moduledoc """
  Four-eyes audit 11-17, cross-cutting item 6 (P0, director): a command-group member is decided,
  queued and released only through its group. The standalone decide (the REST approve/reject core
  and the ops review page) and the standalone enqueue refuse it; the release refuses a member
  whose group isn't armed; and membership comes from the server's group relation, never from
  caller metadata.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding

  alias Cadence.Commanding.{
    CommandApprovalRow,
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandRequestRow
  }

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupAbort, GroupDecision, GroupSubmission}
  alias Cadence.Ids
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(2)
    approver = operator!(c)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{
        log_entry: "Reset counters",
        requested_approver_user_id: approver.user.user_id
      })

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    assert group.state == :approval_pending
    [member | _rest] = GroupStore.members(c.org, c.mission, group.command_group_id)
    assert member.lifecycle_state == :approval_pending

    # A third operator: neither the requester nor the group's named approver.
    other = operator!(c, "Third Operator")

    Map.merge(c, %{group: group, member: member, approver: approver, other: other})
  end

  describe "the standalone decide refuses a group member" do
    test "approve through the REST core, by an operator who isn't the named approver", c do
      assert {:error, :command_request_in_group} = approve(c, user(c.other))
      assert_member_untouched(c)
    end

    test "approve through the REST core, even by the group's named approver", c do
      assert {:error, :command_request_in_group} = approve(c, user(c.approver))
      assert_member_untouched(c)
    end

    test "reject through the REST core (only the group's NO-GO rejects a member)", c do
      assert {:error, :command_request_in_group} =
               ManagementCommanding.reject_command_request(
                 c.org,
                 c.mission,
                 c.member.command_request_id,
                 user(c.other),
                 reason: "rejecting one member alone",
                 admin_mode: false
               )

      assert_member_untouched(c)
    end
  end

  describe "the standalone enqueue refuses a group member" do
    test "while it waits for the group's GO", c do
      assert {:error, :command_request_in_group} = enqueue(c, c.member.command_request_id)
      assert_member_untouched(c)
    end

    test "even in a state the standalone enqueue would otherwise queue", c do
      :ok =
        GroupStore.set_member_state(c.org, c.mission, [c.member.command_request_id], :approved)

      assert {:error, :command_request_in_group} = enqueue(c, c.member.command_request_id)
      refute queued?(c, c.member.command_request_id)
    end
  end

  describe "membership comes from the server's group relation, never from caller metadata" do
    test "a member stays refused whatever marker the caller's metadata carries", c do
      for metadata <- [
            %{},
            %{"command_group_id" => nil},
            %{"command_group_id" => "command_group_other"}
          ] do
        assert {:error, :command_request_in_group} =
                 ManagementCommanding.approve_command_request(
                   c.org,
                   c.mission,
                   c.member.command_request_id,
                   user(c.other),
                   metadata: metadata,
                   admin_mode: false
                 )

        assert {:error, :command_request_in_group} =
                 enqueue(c, c.member.command_request_id, metadata: metadata)
      end

      assert_member_untouched(c)
    end

    test "a standalone request carrying a forged group marker is still standalone", c do
      standalone = standalone_request!(c)
      forged = %{"command_group_id" => c.group.command_group_id}

      assert {:ok, %{approval: approval}} =
               ManagementCommanding.approve_command_request(
                 c.org,
                 c.mission,
                 standalone.command_request_id,
                 user(c.other),
                 metadata: forged,
                 admin_mode: false
               )

      assert approval.decision == :approved
      assert {:ok, _queued} = enqueue(c, standalone.command_request_id, metadata: forged)

      # The forged marker didn't make it a member: the group's members are what they were.
      refute standalone.command_request_id in member_ids(c)
    end

    test "a new request can't make itself a member by naming a group in its metadata", c do
      marker = %{
        "group" => %{"id" => c.group.command_group_id, "target_index" => 0, "position" => 9}
      }

      before = member_ids(c)

      assert {:error, :command_request_group_reserved} =
               ManagementCommanding.persist_command_request(
                 c.org,
                 %{base_request(c) | metadata: marker}
               )

      assert member_ids(c) == before
    end

    test "the group's GO review lists exactly the members its submission made", c do
      submitted = member_ids(c)
      assert length(submitted) == c.group.member_count

      # Both ways a caller could try to add one are refused...
      marker = %{
        "group" => %{"id" => c.group.command_group_id, "target_index" => 1, "position" => 1}
      }

      assert {:error, :command_request_group_reserved} =
               ManagementCommanding.persist_command_request(
                 c.org,
                 %{base_request(c) | metadata: marker}
               )

      assert {:ok, _standalone} =
               ManagementCommanding.persist_command_request(c.org, base_request(c))

      # ...so the review the second operator reads, and the members a GO acts on, are the
      # submission's own.
      {:ok, view} =
        CommandGroups.get(
          c.org,
          c.mission,
          c.group.command_group_id,
          c.approver.user.user_id
        )

      assert view.targets |> Enum.flat_map(& &1.members) |> length() == c.group.member_count
      assert member_ids(c) == submitted
    end
  end

  describe "the GO refuses a group whose member rows changed after submission" do
    test "a member row added behind the submission's back", c do
      standalone = standalone_request!(c)
      join!(standalone.command_request_id, c.group.command_group_id, 1, 1)

      assert {:error, {:command_group_members_changed, 2, 3}} = go(c)
      assert {:ok, %{state: :approval_pending}} = fetch_group(c)
      refute queued?(c, standalone.command_request_id)

      # NO-GO stays the way out: it releases nothing.
      assert {:ok, %{state: :rejected}} =
               GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
                 kind: :no_go,
                 note: "changed after submission"
               })

      refute queued?(c, standalone.command_request_id)
    end

    test "a member row taken out of the group", c do
      join!(c.member.command_request_id, nil, nil, nil)

      assert {:error, {:command_group_members_changed, 2, 1}} = go(c)
      assert {:ok, %{state: :approval_pending}} = fetch_group(c)

      assert {:ok, %{state: :sent_back}} =
               GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
                 kind: :send_back,
                 note: "changed after submission"
               })
    end

    test "abort stays allowed on a changed group", c do
      standalone = standalone_request!(c)
      join!(standalone.command_request_id, c.group.command_group_id, 1, 1)

      assert {:error, {:command_group_members_changed, 2, 3}} = go(c)

      assert {:ok, %{state: :aborted}} =
               GroupAbort.abort(c.approver, c.mission, c.group.command_group_id, "changed")

      refute queued?(c, standalone.command_request_id)
    end

    test "an untouched group is GO'd as before", c do
      assert {:ok, %{state: :queued}} = go(c)
    end
  end

  describe "the release refuses a group member its group didn't send" do
    test "a member that reached the queue without its group's GO doesn't release", c do
      entry = queue_behind_the_groups_back!(c)

      assert {:error, :command_group_not_armed} =
               Commanding.release_command_queue_entry(
                 c.org,
                 c.mission,
                 entry.command_queue_entry_id,
                 "realized_contact_none",
                 user(c.other)
               )

      [member] =
        Enum.filter(members(c), &(&1.command_request_id == c.member.command_request_id))

      assert member.lifecycle_state == :queued
    end

    test "a queued member whose group row is missing doesn't release, and it's logged", c do
      entry = queue_behind_the_groups_back!(c)
      join!(c.member.command_request_id, "command_group_missing", 0, 0)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, :command_group_not_armed} =
                   Commanding.release_command_queue_entry(
                     c.org,
                     c.mission,
                     entry.command_queue_entry_id,
                     "realized_contact_none",
                     user(c.other)
                   )
        end)

      assert log =~ "[error]"
      assert log =~ "command_group_missing"
    end

    test "after the group's GO its members get past the group check", c do
      assert {:ok, %{state: :queued}} =
               GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
                 kind: :go,
                 expected_review: GroupDecision.review_token(c.group)
               })

      [entry | _] =
        Repo.all(
          from(q in CommandQueueEntryRow,
            where: q.mission_id == ^c.mission,
            order_by: [asc: q.queue_sequence]
          )
        )

      # It stops later (no such contact), never on the group check.
      assert {:error, reason} =
               Commanding.release_command_queue_entry(
                 c.org,
                 c.mission,
                 entry.command_queue_entry_id,
                 "realized_contact_none",
                 user(c.approver)
               )

      refute reason == :command_group_not_armed
    end
  end

  defp go(c) do
    GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
      kind: :go,
      expected_review: GroupDecision.review_token(c.group)
    })
  end

  defp fetch_group(c), do: GroupStore.fetch(c.org, c.mission, c.group.command_group_id)

  # Alters a request's group columns straight in the table (what no product path may do).
  defp join!(request_id, group_id, target_index, position) do
    {1, _} =
      Repo.update_all(
        from(r in CommandRequestRow,
          where: r.command_request_id == ^request_id
        ),
        set: [
          command_group_id: group_id,
          group_target_index: target_index,
          group_position: position
        ]
      )

    :ok
  end

  defp approve(c, actor) do
    ManagementCommanding.approve_command_request(
      c.org,
      c.mission,
      c.member.command_request_id,
      actor,
      admin_mode: false
    )
  end

  defp enqueue(c, request_id, opts \\ []) do
    Commanding.enqueue_command_request(
      c.org,
      c.mission,
      request_id,
      user(c.other),
      Keyword.put_new(opts, :admin_mode, false)
    )
  end

  defp user(scope), do: %{"actor_kind" => "user", "user_id" => scope.user.user_id}

  defp members(c), do: GroupStore.members(c.org, c.mission, c.group.command_group_id)
  defp member_ids(c), do: c |> members() |> Enum.map(& &1.command_request_id) |> Enum.sort()

  defp queued?(c, request_id) do
    Repo.exists?(
      from(q in CommandQueueEntryRow,
        where: q.mission_id == ^c.mission and q.command_request_id == ^request_id
      )
    )
  end

  # The member's own command as a plain request: same target, command and arguments, no group.
  defp base_request(c) do
    %{
      c.member
      | command_request_id: Ids.new("command_request"),
        lifecycle_state: nil,
        metadata: %{},
        requested_by: user(c.scope)
    }
  end

  defp standalone_request!(c) do
    {:ok, request} = ManagementCommanding.persist_command_request(c.org, base_request(c))
    assert request.lifecycle_state == :approval_pending
    request
  end

  # What a path that skipped every check would leave behind: the member queued while its group
  # still waits for its GO (written straight to the tables; no product path can do this now).
  defp queue_behind_the_groups_back!(c) do
    :ok = GroupStore.set_member_state(c.org, c.mission, [c.member.command_request_id], :queued)

    entry =
      CommandQueueEntry.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        command_request_id: c.member.command_request_id,
        source_endpoint_ref: c.member.source_endpoint_ref,
        queue_lane_key: c.member.source_endpoint_ref,
        priority: c.member.priority,
        queue_sequence: 1,
        lifecycle_state: :pending,
        enqueued_by: user(c.other),
        enqueued_at: DateTime.utc_now(),
        metadata: %{}
      })

    :ok = GroupStore.insert_queue_entries([entry])
    entry
  end

  defp assert_member_untouched(c) do
    [member] =
      Enum.filter(members(c), &(&1.command_request_id == c.member.command_request_id))

    assert member.lifecycle_state == :approval_pending

    refute Repo.exists?(
             from(a in CommandApprovalRow,
               where:
                 a.mission_id == ^c.mission and
                   a.command_request_id == ^c.member.command_request_id
             )
           )

    refute queued?(c, c.member.command_request_id)
  end
end

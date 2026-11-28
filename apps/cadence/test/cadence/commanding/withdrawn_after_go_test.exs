defmodule Cadence.Commanding.WithdrawnAfterGoTest do
  @moduledoc """
  E2 (#546, the CTO's ruling): a withdrawal after a GO. A group is armed by a GO (or by its submit
  when no second GO is needed); that arming records, in each member's own approval row, which
  withdrawn model approval its craft ran on, if any. A release nobody is watching (a lane
  draining itself, `unattended: true`) refuses a withdrawal the GO didn't know of and fails the
  member closed, so the group needs a new GO. A person naming the contact is the decision.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding
  alias Cadence.Commanding.{CommandApprovalRow, CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.CommandGroupRow
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.{CommandGroups, CommandPreflight}
  alias Cadence.TestSupport.DecisionRecordPurge

  @key "model_approval_withdrawn"

  setup do
    c = setup!(2)
    pin_fleet!(c)
    Map.put(c, :approver, operator!(c))
  end

  defp routine(c), do: draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

  defp hazardous(c),
    do: draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "Reset"})

  # The acknowledgement a person gives the withdrawal HOLD of `draft`'s preflight.
  defp ack(c, draft) do
    {:ok, preflight} = CommandPreflight.run(c.org, c.mission, actor(c), draft)
    check = Enum.find(preflight.checks, &(&1.key == :model_approval_withdrawn))

    [
      %{
        key: @key,
        hold_basis: check.hold_basis,
        note: "Seen.",
        preflight_digest: preflight.digest
      }
    ]
  end

  defp submit(c, draft, acks \\ []) do
    GroupSubmission.submit(c.scope, c.mission, draft,
      preflight_digest: digest(c, draft),
      hold_acks: acks
    )
  end

  defp members(c, group), do: GroupStore.members(c.org, c.mission, group.command_group_id)

  defp entry_id(member),
    do:
      Repo.get_by!(CommandQueueEntryRow, command_request_id: member.command_request_id).command_queue_entry_id

  defp release(c, member, opts),
    do:
      Commanding.release_command_queue_entry(
        c.org,
        c.mission,
        entry_id(member),
        "no-such-contact",
        %{},
        opts
      )

  defp seen(member),
    do:
      GroupStore.withdrawn_seen(
        member.organization_id,
        member.mission_id,
        member.command_request_id
      )

  describe "the GO's record" do
    test "a group armed by its submit records that its craft ran an approved model", c do
      {:ok, group} = submit(c, routine(c))
      assert Enum.all?(members(c, group), &(seen(&1) == nil))
    end

    test "a withdrawal acknowledged at submit is recorded, per craft", c do
      withdraw_approval!(c)
      draft = routine(c)
      {:ok, group} = submit(c, draft, ack(c, draft))

      for member <- members(c, group) do
        assert seen(member) =~ ":withdrawn:"
        assert String.starts_with?(seen(member), c.revision_id)
      end
    end

    test "a withdrawal nobody acknowledged is a stale preflight, and nothing is armed", c do
      withdraw_approval!(c)
      assert {:error, :preflight_stale} = submit(c, routine(c))
      assert Repo.aggregate(from(g in CommandGroupRow), :count) == 0
    end

    test "a GO records it too, and refuses a withdrawal that came in since the review", c do
      {:ok, group} = submit(c, hazardous(c))
      withdraw_approval!(c)

      # The approver's review preflight shows the withdrawal; a GO without its acknowledgement
      # is a stale review, with it the GO records what it knew.
      assert {:error, :command_group_review_stale} =
               go(c, group, [])

      {:ok, review} = CommandPreflight.review(c.org, c.mission, group)
      check = Enum.find(review.checks, &(&1.key == :model_approval_withdrawn))
      acks = [%{key: @key, hold_basis: check.hold_basis, note: "Seen."}]

      assert {:ok, %{state: :queued}} = go(c, group, acks)
      assert Enum.all?(members(c, group), &(seen(&1) =~ ":withdrawn:"))
    end
  end

  describe "an unattended release" do
    test "refuses a withdrawal after the GO, and fails the member closed", c do
      {:ok, group} = submit(c, routine(c))
      [member | _] = members(c, group)
      withdraw_approval!(c)

      assert {:error, :model_approval_withdrawn_after_go} =
               release(c, member, unattended: true)

      assert %{lifecycle_state: :canceled, metadata: %{"cancellation" => cancellation}} =
               Repo.get_by!(CommandRequestRow,
                 command_request_id: member.command_request_id
               )
               |> CommandRequestRow.to_domain()

      assert cancellation["reason"] == "model_approval_withdrawn_after_go"

      {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)
      stopped = Enum.flat_map(view.targets, & &1.members)
      assert Enum.any?(stopped, &(&1.end_reason == :model_approval_withdrawn_after_go))
    end

    test "passes a withdrawal the GO acknowledged", c do
      withdraw_approval!(c)
      draft = routine(c)
      {:ok, group} = submit(c, draft, ack(c, draft))
      [member | _] = members(c, group)

      refute {:error, :model_approval_withdrawn_after_go} == release(c, member, unattended: true)

      assert Repo.get_by!(CommandRequestRow,
               command_request_id: member.command_request_id
             ).lifecycle_state == "queued"
    end

    test "refuses when the GO predates the record (fail closed)", c do
      withdraw_approval!(c)
      draft = routine(c)
      {:ok, group} = submit(c, draft, ack(c, draft))
      [member | _] = members(c, group)

      # An approval row written before the record has no key. (Append-only, so the test database's
      # designed purge opens it.)
      DecisionRecordPurge.run(fn ->
        Repo.update_all(
          from(a in CommandApprovalRow,
            where: a.command_request_id == ^member.command_request_id
          ),
          set: [
            metadata_document:
              JsonDocument.wrap_value(%{"command_group_id" => group.command_group_id})
          ]
        )
      end)

      assert seen(member) == :unrecorded

      assert {:error, :model_approval_withdrawn_after_go} =
               release(c, member, unattended: true)
    end

    test "is unchanged when no craft is withdrawn", c do
      {:ok, group} = submit(c, routine(c))
      [member | _] = members(c, group)
      refute {:error, :model_approval_withdrawn_after_go} == release(c, member, unattended: true)
    end
  end

  test "a person's release is the decision: a withdrawal after the GO doesn't refuse it", c do
    {:ok, group} = submit(c, routine(c))
    [member | _] = members(c, group)
    withdraw_approval!(c)

    refute {:error, :model_approval_withdrawn_after_go} == release(c, member, [])
    refute {:error, :model_approval_withdrawn_after_go} == release(c, member, unattended: false)
  end

  defp go(c, group, acks) do
    GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{
      kind: :go,
      expected_review: GroupDecision.review_token(group),
      hold_acks: acks
    })
  end
end

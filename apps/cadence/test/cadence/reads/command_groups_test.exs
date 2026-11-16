defmodule Cadence.Reads.CommandGroupsTest do
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{
    Cancellation,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow
  }

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupAbort, GroupDecision, GroupSubmission}
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(2)
    Map.put(c, :approver, operator!(c))
  end

  defp submit(c, name, args, extra \\ %{}, opts \\ []) do
    draft = draft(c.spacecraft, [command(c, name, args)], extra)

    {:ok, group} =
      GroupSubmission.submit(
        c.scope,
        c.mission,
        draft,
        Keyword.put(opts, :preflight_digest, digest(c, draft))
      )

    group
  end

  defp viewer(scope), do: scope.user.user_id

  test "a queued group shows each target waiting for its contact", c do
    group = submit(c, "SET_SIGNED", %{"counter" => 1})
    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, viewer(c.scope))

    assert view.state == :queued

    assert [%{name: "SC-1", scid: 7, stage: :queued_for_contact, members: [member]}, _] =
             view.targets

    assert %{position: 0, stage: :queued_for_contact, end_reason: nil} = member
    assert view.progress == %{queued_for_contact: 2}
    assert [%{kind: :submitted}] = view.events
  end

  test "list rows carry progress, and a delivered group reads finished while staying queued",
       c do
    group = submit(c, "SET_SIGNED", %{"counter" => 1})
    id = group.command_group_id

    assert [%{state: :queued, progress: %{queued_for_contact: 2}, finished: false}] =
             CommandGroups.list(c.org, c.mission, viewer(c.scope))

    [first, second] = GroupStore.members(c.org, c.mission, id)
    release!(c, first, :released)

    assert [%{progress: %{no_verifier: 1, queued_for_contact: 1}, finished: false}] =
             CommandGroups.list(c.org, c.mission, viewer(c.scope))

    release!(c, second, :released)

    # Group state is the approval lifecycle; delivery lives in progress (qa #28).
    assert [%{state: :queued, progress: %{no_verifier: 2}, finished: true}] =
             CommandGroups.list(c.org, c.mission, viewer(c.scope))

    assert {:ok, %{state: :queued, progress: %{no_verifier: 2}, finished: true}} =
             CommandGroups.get(c.org, c.mission, id, viewer(c.scope))
  end

  test "list rows of groups that are not queued carry no progress", c do
    group = submit(c, "SET_COUNTER", %{"amount" => 1}, %{log_entry: "x"})

    assert [%{state: :approval_pending, progress: nil, finished: nil}] =
             CommandGroups.list(c.org, c.mission, viewer(c.scope))

    assert {:ok, %{finished: false}} =
             CommandGroups.get(c.org, c.mission, group.command_group_id, viewer(c.scope))
  end

  test "awaiting_me is true only for an eligible approver", c do
    group = submit(c, "SET_COUNTER", %{"amount" => 1}, %{log_entry: "x"})

    assert {:ok, %{awaiting_me: false}} =
             CommandGroups.get(c.org, c.mission, group.command_group_id, viewer(c.scope))

    assert {:ok, %{awaiting_me: true, progress: %{awaiting_go: 2}}} =
             CommandGroups.get(c.org, c.mission, group.command_group_id, viewer(c.approver))

    assert [%{id: id}] =
             CommandGroups.list(c.org, c.mission, viewer(c.approver), awaiting_me: true)

    assert id == group.command_group_id
    assert [] = CommandGroups.list(c.org, c.mission, viewer(c.scope), awaiting_me: true)
  end

  test "excluded and aborted members say why they ended", c do
    group = submit(c, "SET_COUNTER", %{"amount" => 1}, %{log_entry: "x"})

    {:ok, _} =
      GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{
        kind: :go_excluding,
        excluded: ["sc-2"],
        note: "safe mode"
      })

    {:ok, _} = GroupAbort.abort(c.approver, c.mission, group.command_group_id, "Stand down")

    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, viewer(c.scope))

    assert [
             %{stage: :canceled, members: [%{end_reason: :aborted}]},
             %{stage: :excluded, members: [%{end_reason: :excluded_at_review}]}
           ] =
             view.targets
  end

  test "a release the uplink refused reads release_failed, not canceled (#33)", c do
    group = submit(c, "SET_SIGNED", %{"counter" => 3})
    [first | _] = GroupStore.members(c.org, c.mission, group.command_group_id)
    release!(c, first, :release_failed)

    Cadence.Commanding.CommandRequestRow
    |> where([r], r.command_request_id == ^first.command_request_id)
    |> Repo.update_all(set: [lifecycle_state: "canceled"])

    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)
    assert [%{stage: :release_failed, members: [%{end_reason: nil}]}, _] = view.targets
  end

  test "a member canceled by a catalog change set reads end_reason catalog_changed (#65)", c do
    group = submit(c, "SET_SIGNED", %{"counter" => 4})
    [first | _] = GroupStore.members(c.org, c.mission, group.command_group_id)

    {:ok, _} =
      Repo.transaction(fn ->
        Cancellation.cancel(
          c.org,
          c.mission,
          [first.command_request_id],
          "catalog_changed: change_set_1",
          %{"actor_kind" => "system", "id" => "change_set:change_set_1"}
        )
      end)

    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)

    assert [%{members: [%{stage: :canceled, end_reason: :catalog_changed}]}, _] = view.targets
  end

  test "an operation id resolves to its group", c do
    group = submit(c, "SET_SIGNED", %{"counter" => 2}, %{}, operation_id: "op-42")
    assert {:ok, %{id: id}} = CommandGroups.fetch_by_operation(c.org, c.mission, "op-42")
    assert id == group.command_group_id
  end

  test "a target waiting behind an uncertain release on its lane is blocked", c do
    ahead = submit(c, "SET_SIGNED", %{"counter" => 1})
    behind = submit(c, "SET_SIGNED", %{"counter" => 2})

    [first | _] = GroupStore.members(c.org, c.mission, ahead.command_group_id)
    release!(c, first, :release_uncertain)

    {:ok, view} = CommandGroups.get(c.org, c.mission, behind.command_group_id, nil)
    [held, other] = view.targets

    assert %{
             stage: :queued_for_contact,
             blocked: %{reason: :lane_release_uncertain, command_request_id: id}
           } = held

    assert id == first.command_request_id
    assert other.blocked == nil

    # The uncertain member's own target shows it (an operator must resolve it), so its group
    # isn't finished.
    {:ok, ahead_view} = CommandGroups.get(c.org, c.mission, ahead.command_group_id, nil)
    assert [%{stage: :indeterminate, blocked: nil}, _] = ahead_view.targets
    assert ahead_view.finished == false
  end

  # A release attempt for `member` in `state` (what the dispatcher records on release).
  defp release!(c, member, state) do
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
      lifecycle_state: state,
      released_by: %{},
      attempted_at: DateTime.utc_now()
    })
    |> CommandReleaseAttemptRow.changeset()
    |> Repo.insert!()
  end
end

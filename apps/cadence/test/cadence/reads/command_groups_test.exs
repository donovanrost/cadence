defmodule Cadence.Reads.CommandGroupsTest do
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

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

  test "an operation id resolves to its group", c do
    group = submit(c, "SET_SIGNED", %{"counter" => 2}, %{}, operation_id: "op-42")
    assert {:ok, %{id: id}} = CommandGroups.fetch_by_operation(c.org, c.mission, "op-42")
    assert id == group.command_group_id
  end
end

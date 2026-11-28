defmodule Cadence.Reads.CommandGroups.WithdrawnAfterGoTest do
  @moduledoc """
  E2 (#546): the group read says which targets are on a withdrawn model approval their GO didn't
  know about (the release panel's caution), per target and as a summary over the whole group.
  The comparison is the unattended release's own.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures
  import Ecto.Query

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups
  alias Cadence.Reads.CommandGroups.{Page, WithdrawnAfterGo}

  setup do
    c = setup!(4)
    pin_fleet!(c)
    c
  end

  defp submit!(c, craft, acks \\ []) do
    draft = draft(craft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft,
        preflight_digest: digest(c, draft),
        hold_acks: acks
      )

    group
  end

  defp view(c, group) do
    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)
    view
  end

  test "nothing is flagged while no approval is withdrawn", c do
    view = view(c, submit!(c, c.spacecraft))

    assert view.withdrawn_after_go == nil
    assert Enum.all?(view.targets, &(&1.withdrawn_after_go == nil))
  end

  test "a withdrawal after the GO flags every waiting target, and summarizes the group", c do
    view_before = submit!(c, c.spacecraft)
    withdraw_approval!(c)
    view = view(c, view_before)

    assert Enum.all?(view.targets, fn target ->
             match?(
               %{
                 revision_id: revision,
                 decision: %{kind: "withdrawn", reason: "Limits were wrong"}
               }
               when revision == c.revision_id,
               target.withdrawn_after_go
             ) and is_map(target.withdrawn_after_go.decision.by)
           end)

    assert %{count: 4, latest: %{revision_id: revision, decision: %{at: %DateTime{}}}} =
             view.withdrawn_after_go

    assert revision == c.revision_id
  end

  test "a withdrawal the GO acknowledged is not flagged", c do
    withdraw_approval!(c)
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])
    view = view(c, submit!(c, c.spacecraft, withdrawal_ack(c, draft)))

    assert view.withdrawn_after_go == nil
    assert Enum.all?(view.targets, &(&1.withdrawn_after_go == nil))
  end

  test "a target with no member still waiting for its contact is not flagged", c do
    group = submit!(c, c.spacecraft)
    withdraw_approval!(c)

    Repo.update_all(
      from(r in CommandRequestRow, where: r.command_group_id == ^group.command_group_id),
      set: [lifecycle_state: "canceled"]
    )

    assert view(c, group).withdrawn_after_go == nil
  end

  test "the field is on the target rows of every page, and the summary counts the whole group",
       c do
    group = submit!(c, c.spacecraft)
    withdraw_approval!(c)
    view = view(c, group)

    {:ok, first} = Page.targets(view, %{"limit" => "2"})
    assert [%{withdrawn_after_go: %{}}, %{withdrawn_after_go: %{}}] = first.targets
    {:ok, second} = Page.targets(view, %{"limit" => "2", "cursor" => first.next_cursor})
    assert [%{withdrawn_after_go: %{}}, %{withdrawn_after_go: %{}}] = second.targets

    # The summary is the group's, not the page's.
    assert Page.first(view).withdrawn_after_go.count == 4
  end

  test "the same number of queries for one target and for four", c do
    one = submit!(c, [hd(c.spacecraft)])
    four = submit!(c, c.spacecraft)
    withdraw_approval!(c)

    one_targets = view(c, one).targets
    four_targets = view(c, four).targets

    {few, {[_], %{count: 1}}} =
      count_queries(fn -> WithdrawnAfterGo.put(one_targets, c.org, c.mission) end)

    {many, {[_, _, _, _], %{count: 4}}} =
      count_queries(fn -> WithdrawnAfterGo.put(four_targets, c.org, c.mission) end)

    assert few == many
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "withdrawn-after-go-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, {:query, ref}) end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, 0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, n) do
    receive do
      {:query, ^ref} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end

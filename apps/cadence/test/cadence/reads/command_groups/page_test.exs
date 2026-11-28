defmodule Cadence.Reads.CommandGroups.PageTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.CommandGroups.Page

  @stages ~w(queued_for_contact verified release_failed)a

  defp view(mission \\ "mission-1", group \\ "group-1", targets \\ 250, events \\ 120) do
    at = ~U[2026-11-26 00:00:00.000000Z]

    %{
      group: %{mission_id: mission, command_group_id: group},
      targets:
        for i <- 0..(targets - 1) do
          %{
            index: i,
            spacecraft_id: "sc-#{i}",
            name: "SAT #{i}",
            stage: Enum.at(@stages, rem(i, 3)),
            blocked: if(rem(i, 50) == 1, do: %{reason: :lane_release_uncertain}),
            members: []
          }
        end,
      events:
        for i <- 1..events do
          %{
            id: "ev-#{i}",
            kind: if(rem(i, 10) == 0, do: :hold_acknowledged, else: :member_failed),
            at: DateTime.add(at, i, :second)
          }
        end
    }
  end

  defp all_targets(view, params, acc \\ []) do
    {:ok, page} = Page.targets(view, params)
    acc = acc ++ page.targets

    case page.next_cursor do
      nil -> acc
      cursor -> all_targets(view, Map.put(params, "cursor", cursor), acc)
    end
  end

  test "the first page carries the first targets, the latest events and their totals" do
    view = Page.first(view())

    assert length(view.targets) == 100
    assert hd(view.targets).index == 0
    assert %{total: 250, next_cursor: cursor, revision: revision} = view.targets_page
    assert is_binary(cursor) and is_integer(revision)

    assert length(view.events) == 50
    assert hd(view.events).id == "ev-71" and List.last(view.events).id == "ev-120"
    assert %{total: 120, next_cursor: older} = view.events_page
    assert is_binary(older)
  end

  test "a group within one page has no cursor" do
    view = Page.first(view("mission-1", "group-1", 3, 2))
    assert %{total: 3, next_cursor: nil} = view.targets_page
    assert %{total: 2, next_cursor: nil} = view.events_page
  end

  test "following the cursor reads every target once, in order, whatever the limit" do
    for limit <- ["1", "7", "100", "500"] do
      indexes = view() |> all_targets(%{"limit" => limit}) |> Enum.map(& &1.index)
      assert indexes == Enum.to_list(0..249), "limit #{limit}"
    end
  end

  test "stage and q filter the targets, and the total is the filtered one" do
    view = view()

    assert {:ok, %{total: 83, targets: targets}} =
             Page.targets(view, %{"stage" => "verified", "limit" => "500"})

    assert Enum.all?(targets, &(&1.stage == :verified))

    assert {:ok, %{total: 11, targets: [%{index: 7}, %{index: 70}]}} =
             Page.targets(view, %{"q" => " sat 7 ", "limit" => "2"})

    assert {:ok, %{total: 11}} = Page.targets(view, %{"q" => "sc-24"})

    assert {:ok, %{total: 41}} =
             Page.targets(view, %{"stage" => "verified,release_failed", "q" => "sc-2"})
  end

  test "needs_you holds the failed and uncertain targets and the ones blocked on a held lane" do
    view = view()

    # Stages in the fixture cycle queued_for_contact, verified, release_failed by index; the
    # blocked ones are indexes 1, 51, 101, 151 and 201 (stage verified, so they'd be missed by a
    # stage filter alone).
    assert {:ok, %{total: total, targets: targets}} =
             Page.targets(view, %{"needs_you" => "true", "limit" => "500"})

    failed = Enum.count(view.targets, &(&1.stage == :release_failed))
    blocked = Enum.count(view.targets, &(&1.blocked != nil and &1.stage != :release_failed))
    assert total == failed + blocked
    assert Enum.all?(targets, &(&1.stage == :release_failed or &1.blocked != nil))
    assert Enum.any?(targets, &(&1.index == 51))

    # It combines with the other filters, and pages with a cursor like any other read.
    assert {:ok, %{total: ^failed}} =
             Page.targets(view, %{"needs_you" => "true", "stage" => "release_failed"})

    assert Enum.map(all_targets(view, %{"needs_you" => "true", "limit" => "7"}), & &1.index) ==
             Enum.map(targets, & &1.index)

    assert {:ok, %{total: 250}} = Page.targets(view, %{"needs_you" => "false"})

    assert {:error, {:invalid_params, %{"needs_you" => _}}} =
             Page.targets(view, %{"needs_you" => "1"})
  end

  test "events can be read by kind, and a cursor pages the filtered list" do
    view = view()

    assert {:ok, %{total: 12, events: events, next_cursor: nil}} =
             Page.events(view, %{"kind" => "hold_acknowledged"})

    assert Enum.all?(events, &(&1.kind == :hold_acknowledged))

    assert {:ok, %{total: 108}} = Page.events(view, %{"kind" => "member_failed,note"})

    assert {:ok, %{total: 120}} =
             Page.events(view, %{"kind" => "member_failed,hold_acknowledged"})

    {:ok, first} = Page.events(view, %{"kind" => "hold_acknowledged", "limit" => "5"})

    {:ok, second} =
      Page.events(view, %{
        "kind" => "hold_acknowledged",
        "limit" => "5",
        "cursor" => first.next_cursor
      })

    assert length(first.events ++ second.events) == 10
    assert Enum.all?(second.events, &(&1.kind == :hold_acknowledged))

    assert {:error, {:invalid_params, %{"kind" => _}}} = Page.events(view, %{"kind" => "nope"})
    assert {:error, {:invalid_params, %{"kind" => _}}} = Page.events(view, %{"kind" => ""})
  end

  test "following the events cursor reads older events until none are left" do
    view = view()
    {:ok, first} = Page.events(view, %{"limit" => "50"})
    {:ok, second} = Page.events(view, %{"limit" => "50", "cursor" => first.next_cursor})
    {:ok, third} = Page.events(view, %{"limit" => "50", "cursor" => second.next_cursor})

    ids = Enum.map(first.events ++ second.events ++ third.events, & &1.id)
    assert Enum.sort(ids) == Enum.sort(Enum.map(view.events, & &1.id))
    assert length(Enum.uniq(ids)) == 120
    assert third.next_cursor == nil
    assert Enum.map(third.events, & &1.id) |> hd() == "ev-1"
  end

  test "a cursor is bound to its group, mission and list" do
    {:ok, %{next_cursor: targets_cursor}} = Page.targets(view(), %{"limit" => "10"})
    {:ok, %{next_cursor: events_cursor}} = Page.events(view(), %{"limit" => "10"})

    assert {:error, :invalid_cursor} =
             Page.targets(view("mission-1", "group-2"), %{"cursor" => targets_cursor})

    assert {:error, :invalid_cursor} =
             Page.targets(view("mission-2", "group-1"), %{"cursor" => targets_cursor})

    assert {:error, :invalid_cursor} =
             Page.events(view("mission-1", "group-2"), %{"cursor" => events_cursor})

    assert {:error, :invalid_cursor} = Page.targets(view(), %{"cursor" => events_cursor})
    assert {:error, :invalid_cursor} = Page.events(view(), %{"cursor" => targets_cursor})
    assert {:error, :invalid_cursor} = Page.targets(view(), %{"cursor" => "not-a-cursor"})
    assert {:error, :invalid_cursor} = Page.targets(view(), %{"cursor" => 5})

    forged =
      Base.url_encode64(~s({"m":"mission-1","g":"group-1","s":"targets","k":"x"}), padding: false)

    assert {:error, :invalid_cursor} = Page.targets(view(), %{"cursor" => forged})
  end

  test "bad limit, stage or q name the field" do
    assert {:error, {:invalid_params, %{"limit" => _}}} = Page.targets(view(), %{"limit" => "0"})

    assert {:error, {:invalid_params, %{"limit" => _}}} =
             Page.targets(view(), %{"limit" => "501"})

    assert {:error, {:invalid_params, %{"limit" => _}}} = Page.events(view(), %{"limit" => "201"})
    assert {:error, {:invalid_params, %{"limit" => _}}} = Page.events(view(), %{"limit" => "x"})

    assert {:error, {:invalid_params, %{"stage" => _}}} =
             Page.targets(view(), %{"stage" => "nope"})

    assert {:error, {:invalid_params, %{"q" => _}}} =
             Page.targets(view(), %{"q" => String.duplicate("a", 101)})
  end

  test "the revision moves when anything a page of targets shows does" do
    base = %{view() | targets: view().targets}
    same = Page.first(base).targets_page.revision

    blocked = %{
      base
      | targets:
          List.update_at(base.targets, 2, &%{&1 | blocked: %{reason: :lane_release_uncertain}})
    }

    refute Page.first(blocked).targets_page.revision == same

    # A member's own facts, with the stage unchanged.
    member = %{failure_reason: :verify_failed, timed_out_at: ~U[2026-11-28 00:00:00Z]}
    with_member = %{base | targets: List.update_at(base.targets, 3, &%{&1 | members: [member]})}
    refute Page.first(with_member).targets_page.revision == same
  end

  test "the revision moves when a target's stage does, and not otherwise" do
    base = view()
    same = Page.first(base).targets_page.revision
    assert Page.first(base).targets_page.revision == same

    changed = %{base | targets: List.update_at(base.targets, 4, &%{&1 | stage: :canceled})}
    refute Page.first(changed).targets_page.revision == same
  end
end

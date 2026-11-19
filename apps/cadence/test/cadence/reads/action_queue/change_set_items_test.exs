defmodule Cadence.Reads.ActionQueue.ChangeSetItemsTest do
  @moduledoc "BACKLOG 8d: a change set staged for more than 24 h is one P3 Now item."
  use ExUnit.Case, async: true

  alias Cadence.Reads.ActionQueue.ChangeSetItems

  @now ~U[2026-11-13 12:00:00.000000Z]
  @author %{kind: "user", id: "user-1", name: "Mira K."}

  defp set(staged_ats) do
    %{
      id: "change_set-1",
      state: :open,
      staged_count: length(staged_ats),
      base_revision: 5,
      opened_at: hd(staged_ats ++ [@now]),
      submitted_at: nil,
      authors: [@author],
      changes: Enum.map(staged_ats, &%{staged_at: &1})
    }
  end

  defp hours_ago(h), do: DateTime.add(@now, -h * 3_600)

  test "the oldest staged change past 24 h raises one P3 item" do
    oldest = DateTime.add(hours_ago(24), -1)

    assert [item] = ChangeSetItems.items(set([hours_ago(2), oldest]), @now)

    assert %{
             id: "change_set_stale:change_set-1",
             priority: 3,
             kind: :change_set_stale,
             state: :off,
             since: ^oldest,
             count: 2,
             spacecraft: [],
             change_set: %{
               id: "change_set-1",
               state: :open,
               staged_count: 2,
               base_revision: 5,
               oldest_staged_at: ^oldest,
               authors: [@author]
             }
           } = item
  end

  test "nothing at exactly 24 h, with nothing staged, or with no active set" do
    assert [] = ChangeSetItems.items(set([hours_ago(24)]), @now)
    assert [] = ChangeSetItems.items(set([]), @now)
    assert [] = ChangeSetItems.items(nil, @now)
  end
end

defmodule Cadence.Alarms.EpisodeCursorTest do
  @moduledoc "U69 A6d: alarm-episode pages in the list's own order, by an opaque cursor."
  use Cadence.DataCase, async: false

  alias Cadence.Alarms.{EpisodeCursor, EpisodeRow, Queries}

  @mission "mission-episode-cursor"
  @at ~U[2026-11-14 07:00:00.000000Z]

  setup do
    persist_mission_scope("org-episode-cursor", @mission)

    # Every ordering case: severity, acknowledged or not, opened times (one tie), and cleared.
    for {id, severity, acked?, minute} <- [
          {"e1", "critical", false, 1},
          {"e2", "critical", true, 5},
          {"e3", "caution", false, 3},
          {"e4", "caution", false, 3},
          {"e5", "caution", true, 2},
          {"e6", "critical", false, 4}
        ],
        do: episode!(id, severity, acked?, minute, nil)

    for {id, minute} <- [{"c1", 10}, {"c2", 12}, {"c3", 12}],
        do: episode!(id, "caution", true, 1, minute)

    :ok
  end

  defp episode!(id, severity, acked?, minute, cleared_minute) do
    Repo.insert!(%EpisodeRow{
      episode_id: id,
      organization_id: "org-episode-cursor",
      mission_id: @mission,
      spacecraft_id: "sc-1",
      spacecraft_scope_id: "sc-1",
      source: "ground_limit",
      subject_key: id,
      parameter_ref: "HK." <> id,
      severity: severity,
      peak_severity: severity,
      source_state: "yellow",
      state: if(cleared_minute, do: "cleared", else: "active"),
      opened_at: DateTime.add(@at, minute * 60),
      last_observed_at: DateTime.add(@at, minute * 60),
      last_evaluated_at: DateTime.add(@at, minute * 60),
      opened_by_ref: "ref-" <> id,
      acknowledged_at: if(acked?, do: DateTime.add(@at, minute * 60 + 1)),
      cleared_at: cleared_minute && DateTime.add(@at, cleared_minute * 60)
    })
  end

  defp all_pages(state, limit, cursor \\ nil, acc \\ []) do
    after_key = cursor && elem(EpisodeCursor.decode(cursor), 1)
    page = Queries.page(@mission, %{state: state, limit: limit, after: after_key})
    ids = acc ++ Enum.map(page.episodes, & &1.id)

    case EpisodeCursor.encode(page.next) do
      nil -> ids
      next -> all_pages(state, limit, next, ids)
    end
  end

  test "pages of two reproduce the full active and cleared lists, in order" do
    active = Enum.map(Queries.list(@mission, %{state: "active", limit: 50}), & &1.id)
    # A tie on opened_at sorts by id.
    assert active == ~w(e6 e1 e2 e3 e4 e5)
    assert all_pages("active", 2) == active

    cleared = Enum.map(Queries.list(@mission, %{state: "cleared", limit: 50}), & &1.id)
    assert cleared == ~w(c2 c3 c1)
    assert all_pages("cleared", 2) == cleared

    assert all_pages("all", 4) ==
             Enum.map(Queries.list(@mission, %{state: "all", limit: 50}), & &1.id)
  end

  test "the boundary holds when its row moves; the moved row shows where it now sorts" do
    page = Queries.page(@mission, %{state: "active", limit: 2})
    assert Enum.map(page.episodes, & &1.id) == ~w(e6 e1)

    Repo.update_all(from(e in EpisodeRow, where: e.episode_id == "e1"),
      set: [acknowledged_at: DateTime.add(@at, 3_600)]
    )

    next = Queries.page(@mission, %{state: "active", limit: 10, after: page.next})
    # e1 is now critical-acknowledged, opened before e2: it sorts after the boundary again.
    assert Enum.map(next.episodes, & &1.id) == ~w(e2 e1 e3 e4 e5)
  end

  test "a cursor decodes back; garbage or another list's cursor is refused or matches nothing" do
    %{next: key} = Queries.page(@mission, %{state: "active", limit: 1})
    assert {:ok, ^key} = key |> EpisodeCursor.encode() |> EpisodeCursor.decode()
    assert {:error, :invalid_cursor} = EpisodeCursor.decode("nope")
    assert {:ok, nil} = EpisodeCursor.decode(nil)

    assert %{episodes: []} = Queries.page(@mission, %{state: "cleared", limit: 5, after: key})
  end
end

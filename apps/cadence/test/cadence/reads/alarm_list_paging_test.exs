defmodule Cadence.Reads.AlarmListPagingTest do
  @moduledoc """
  The alarm list in pages (#794, #176): every page enriched, a cursor that survives change between
  pages, and the per-plane / per-point filters the sister-alarm views ask the server for.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits.Event
  alias Cadence.Reads.AlarmList
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-alarm-paging"
  @mission "mission-alarm-paging"
  @points ["HK.a", "HK.b", "HK.c", "HK.d", "HK.e"]

  # 90 spacecraft x 5 points = 450 active alarms, red on every third, newest first by index.
  defp events(spacecraft \\ 1..90) do
    for craft <- spacecraft, {point, p} <- Enum.with_index(@points) do
      %Event{
        limit_event_id: "ev-#{craft}-#{point}",
        mission_id: @mission,
        spacecraft_id: "sc-#{String.pad_leading("#{craft}", 3, "0")}",
        point_id: point,
        point_name: point,
        limit_definition_id: "def-#{point}",
        limit_definition_version: 1,
        limit_set_name: "default",
        evaluated_value: craft,
        limit_state: :high,
        normalized_state: if(rem(craft + p, 3) == 0, do: :red, else: :yellow),
        violation: true,
        generation_time: ~U[2026-11-26 12:00:00Z],
        receipt_time: DateTime.add(~U[2026-11-26 12:00:00Z], craft * 5 + p, :second),
        provenance: %{}
      }
    end
  end

  defp load(filters, events \\ events()) do
    AlarmList.load(@org, @mission, filters,
      latest_states: fn _org, _mission, _opts -> events end,
      first_crossed_at: fn row -> row.receipt_time end
    )
  end

  defp walk(filters, events \\ events(), pages \\ []) do
    {:ok, page} = load(filters, events)

    case page.next_cursor do
      nil -> Enum.reverse([page | pages])
      cursor -> walk(Map.put(filters, :cursor, cursor), events, [page | pages])
    end
  end

  test "pages cover every alarm once, in the list's order, with a total and a last page" do
    pages = walk(%{limit: 200})

    assert Enum.map(pages, &length(&1.alarms)) == [200, 200, 50]
    assert Enum.all?(pages, &(&1.total == 450))
    assert List.last(pages).next_cursor == nil

    ids = pages |> Enum.flat_map(& &1.alarms) |> Enum.map(& &1.id)
    assert length(Enum.uniq(ids)) == 450

    {:ok, everything} = load(%{limit: 200})
    assert hd(pages).alarms == everything.alarms
    assert Enum.map(Enum.take(ids, 3), & &1) == Enum.map(Enum.take(everything.alarms, 3), & &1.id)

    severities = Enum.map(Enum.flat_map(pages, & &1.alarms), & &1.severity)
    assert severities == Enum.sort_by(severities, &if(&1 == :critical, do: 0, else: 1))
  end

  test "every page is enriched, not only the first 200" do
    pages = walk(%{limit: 200})
    last = List.last(pages)

    assert Enum.all?(last.alarms, &is_struct(&1.first_crossed_at, DateTime))
    assert Enum.all?(last.alarms, &Map.has_key?(&1, :unit))
    assert Enum.all?(Enum.flat_map(pages, & &1.alarms), &(&1.first_crossed_at == &1.receipt_time))
  end

  test "the default page is 100 and the limit is bounded" do
    assert {:ok, %{alarms: page}} = load(%{})
    assert length(page) == 100
    assert {:ok, %{alarms: page}} = load(%{limit: 0})
    assert length(page) == 100
    assert {:ok, %{alarms: page}} = load(%{limit: 5})
    assert length(page) == 5
  end

  test "the summary counts the whole mission, whatever the page or filters" do
    {:ok, page} = load(%{limit: 5, point_id: "HK.a"})
    assert page.summary.active == 450
    assert page.total == 90
  end

  test "a cursor survives alarms that clear or appear between pages" do
    {:ok, first} = load(%{limit: 200})
    seen = Enum.map(first.alarms, & &1.id)
    last = List.last(first.alarms)

    # Between the pages: the alarms of the first page's last spacecraft clear, and a spacecraft's
    # alarms appear, older than the cursor (newer ones sort into pages already read).
    changed =
      events()
      |> Enum.reject(&(&1.spacecraft_id == last.spacecraft_id))
      |> Kernel.++(events(0..0))

    rest = walk(%{limit: 200, cursor: first.next_cursor}, changed) |> Enum.flat_map(& &1.alarms)
    ids = Enum.map(rest, & &1.id)

    # Nothing already read repeats; nothing cleared is listed; the new alarms are reached.
    assert Enum.all?(ids, &(&1 not in seen))
    assert length(Enum.uniq(ids)) == length(ids)
    refute Enum.any?(rest, &(&1.spacecraft_id == last.spacecraft_id))
    # sc-000's two red alarms sort among the critical ones, behind the cursor: only its three
    # caution alarms are ahead of it.
    assert Enum.count(rest, &(&1.spacecraft_id == "sc-000")) == 3

    still_ahead =
      for e <- events(),
          e.limit_event_id not in seen,
          e.spacecraft_id != last.spacecraft_id,
          do: e

    assert length(rest) == length(still_ahead) + 3
  end

  test "a cursor that isn't one is refused" do
    for bad <- ["nonsense", "!!", Base.url_encode64("not a term", padding: false)] do
      assert {:error, :invalid_cursor} = load(%{cursor: bad})
    end
  end

  describe "sister alarms: same point, same plane, not me" do
    setup do
      persist_mission_scope(@org, @mission)

      for {craft, plane} <- [{3, 7}, {4, 7}, {5, 7}, {6, 8}] do
        id = "sc-00#{craft}"

        {:ok, _} =
          SpacecraftStore.persist_spacecraft(
            @org,
            Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: @org,
              mission_id: @mission,
              display_name: id,
              metadata: %{"plane" => plane}
            })
          )
      end

      :ok
    end

    test "the plane's alarms on the point, excluding the spacecraft itself" do
      assert {:ok, page} = load(%{point_id: "HK.b", plane: 7, exclude_spacecraft_id: "sc-004"})
      assert Enum.map(page.alarms, & &1.spacecraft_id) |> Enum.sort() == ["sc-003", "sc-005"]
      assert page.total == 2
      assert Enum.all?(page.alarms, &(&1.point_id == "HK.b"))
    end

    test "a count is one row's page and the total" do
      assert {:ok, %{total: 3, alarms: [_one]}} = load(%{point_id: "HK.b", plane: 7, limit: 1})
    end

    test "a plane with no spacecraft matches nothing" do
      assert {:ok, %{total: 0, alarms: [], next_cursor: nil}} =
               load(%{point_id: "HK.b", plane: 99})
    end
  end
end

defmodule Cadence.Reads.MissionTimelinePagingTest do
  use Cadence.DataCase, async: false
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.{Event, EventRow}
  alias Cadence.Projections.MissionEvents, as: Projection
  alias Cadence.Reads.MissionTimeline
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.{Spacecraft, SpacecraftStore}
  @org "org-timeline-pages"
  @mission "mission-timeline-pages"
  @at ~U[2026-09-01 00:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "effective time controls canonical ordering and half-open filter bounds" do
    early = event("recorded-late", DateTime.add(@at, 1000)) |> Map.put(:effective_at, @at)
    late = event("effective-late", @at) |> Map.put(:effective_at, DateTime.add(@at, 1000))
    persist(early)
    persist(late)
    assert [newest, oldest] = MissionTimeline.list_for_mission(@org, @mission)
    assert newest.mission_event_id == "mission_event:effective-late"
    assert oldest.mission_event_id == "mission_event:recorded-late"

    page =
      MissionTimeline.page_for_mission(@org, @mission,
        from_occurred_at: @at,
        to_occurred_at: DateTime.add(@at, 1)
      )

    assert Enum.map(page.entries, & &1.mission_event_id) == [oldest.mission_event_id]
    assert page.next_cursor == nil
    # Other operational consumers still use recorded event occurrence unless they opt in.
    assert [recorded] =
             OperationalEvents.list_events(@org, @mission,
               from_occurred_at: @at,
               to_occurred_at: DateTime.add(@at, 1)
             )

    assert recorded.event_id == "effective-late"
  end

  test "equal-time pages merge sources without duplicates and projected evidence wins" do
    ids = ~w(A Z a z alpha beta)
    for id <- ids, do: persist(event(id, @at))
    {:ok, original} = MissionTimeline.fetch_for_mission(@org, @mission, "mission_event:alpha")

    assert {:ok, 1} =
             Projection.persist_entries(Repo, [
               %{original | title: "Corrected canonical evidence"}
             ])

    projected =
      for id <- ~w(A B a b),
          do:
            Entry.new(%{
              mission_event_id: "projection:#{id}",
              mission_id: @mission,
              occurred_at: @at,
              category: :health,
              kind: :limit_violation,
              severity: :warning,
              title: "Limit evidence",
              source_record_kind: :limit_event,
              source_record_id: id
            })

    assert {:ok, 4} = Projection.persist_entries(Repo, projected)
    rows = collect_pages([], nil, 10)

    expected =
      Enum.sort(
        Enum.map(ids, &"mission_event:#{&1}") ++ Enum.map(projected, & &1.mission_event_id),
        :desc
      )

    assert Enum.map(rows, & &1.mission_event_id) == expected

    assert Enum.find(rows, &(&1.mission_event_id == "mission_event:alpha")).title ==
             "Corrected canonical evidence"
  end

  test "an empty bounded page can continue to an older endpoint-derived spacecraft event" do
    assert {:ok, _} =
             SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{
                 spacecraft_id: "wanted",
                 mission_id: @mission,
                 display_name: "Wanted"
               })
             )

    assert {:ok, _} =
             SourceEndpoints.persist_source_endpoint(
               @org,
               SourceEndpoint.new(%{
                 source_endpoint_id: "wanted-endpoint",
                 mission_id: @mission,
                 spacecraft_id: "wanted"
               })
             )

    old = event("older-wanted", @at) |> Map.put(:scope, %{source_endpoint_ref: "wanted-endpoint"})
    persist(old)

    rows =
      for i <- 1..1001,
          do:
            event("noise-#{i}", DateTime.add(@at, i))
            |> Map.put(:scope, %{spacecraft_id: "other"})
            |> EventRow.insert_attrs(@at)

    assert {1001, nil} = Repo.insert_all(EventRow, rows)
    first = MissionTimeline.page_for_mission(@org, @mission, spacecraft_id: "wanted", limit: 10)
    assert first.entries == []
    assert first.next_cursor != nil

    second =
      MissionTimeline.page_for_mission(@org, @mission,
        spacecraft_id: "wanted",
        limit: 10,
        cursor: first.next_cursor
      )

    assert [entry] = second.entries
    assert entry.mission_event_id == "mission_event:older-wanted"
    assert entry.spacecraft_id == "wanted"
    assert second.next_cursor == nil

    assert {:ok, ^entry} =
             MissionTimeline.fetch_for_mission(@org, @mission, entry.mission_event_id)

    assert SourceEndpoints.spacecraft_for_source_endpoints(@org, @mission, [
             "wanted-endpoint",
             "unavailable"
           ]) == %{"wanted-endpoint" => "wanted"}

    assert SourceEndpoints.spacecraft_for_source_endpoints("foreign", @mission, [
             "wanted-endpoint"
           ]) == %{}
  end

  test "a canonical override excluded by filters cannot reappear as its obsolete raw event" do
    persist(%{event("overridden", @at) | severity: :critical})

    {:ok, original} =
      MissionTimeline.fetch_for_mission(@org, @mission, "mission_event:overridden")

    assert {:ok, 1} = Projection.persist_entries(Repo, [%{original | severity: :warning}])

    assert %{entries: [], next_cursor: nil} =
             MissionTimeline.page_for_mission(@org, @mission, severity: :critical)

    assert [row] = MissionTimeline.list_for_mission(@org, @mission, severity: :warning)
    assert row.severity == :warning
  end

  defp collect_pages(_rows, _cursor, 0), do: flunk("timeline cursor did not terminate")

  defp collect_pages(rows, cursor, remaining) do
    page = MissionTimeline.page_for_mission(@org, @mission, limit: 3, cursor: cursor)
    assert length(page.entries) <= 3

    case page.next_cursor do
      nil ->
        rows ++ page.entries

      next ->
        assert(next != cursor)
        collect_pages(rows ++ page.entries, next, remaining - 1)
    end
  end

  defp persist(event), do: assert({:ok, _} = OperationalEvents.persist_event(event))

  defp event(id, at),
    do:
      Event.new(%{
        event_id: id,
        organization_id: @org,
        mission_id: @mission,
        occurred_at: at,
        category: :data_source,
        kind: :source_health_degraded,
        severity: :warning,
        subject: %{kind: :data_source, id: "flight"},
        current: %{status: "degraded"}
      })
end

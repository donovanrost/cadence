defmodule Cadence.Reads.AlarmEventsTest do
  @moduledoc """
  The dashboards' limits source reads a point's latest state, event history and watermark from the
  runtime's alarm states and transitions (#451 T3e), as the limit events its frames already read:
  the alarm level is the normalized state (critical red, caution yellow, normal green), the
  history is the point's transitions, the event id is the transition id, and a state that raises
  and clears nothing is not an event. Definition intervals are empty (bands for monitoring rules
  are not shown yet, #1127).
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Limits.Event
  alias Cadence.Reads.AlarmEvents
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.SemanticObservations

  @org "org-alarm-events"
  @mission "mission-alarm-events"
  @t0 ~U[2026-11-28 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "#{@mission}-other")
    :ok
  end

  defp at(n), do: DateTime.add(@t0, n)

  defp persist!(parameter, craft, states, n, opts \\ []) do
    mission = Keyword.get(opts, :mission, @mission)

    :ok =
      SemanticObservations.persist_many([
        transition(
          @org,
          mission,
          craft,
          parameter,
          states,
          at(n),
          "#{mission}-#{parameter}-#{craft}-#{n}"
        )
      ])
  end

  defp history(point, opts \\ []), do: LimitReads.event_history(@org, @mission, point, opts)

  test "the latest state is the worst-newest state of the point as a limit event" do
    persist!("P1", "sc-1", {:normal, :warning}, 1)
    persist!("P1", "sc-1", {:warning, :critical}, 5)

    assert %Event{
             spacecraft_id: "sc-1",
             point_id: "P1",
             normalized_state: :red,
             violation: true,
             evaluated_value: nil,
             limit_state: nil,
             limit_definition_id: "policy-P1"
           } = event = LimitReads.latest_state(@org, @mission, "P1", [])

    assert event.receipt_time == at(5)
    assert LimitReads.latest_state(@org, @mission, "P1", spacecraft_id: "sc-2") == nil
    assert LimitReads.latest_state(@org, @mission, "unknown", []) == nil
  end

  test "the mission-only call reads the same, and another mission's states never appear" do
    persist!("P1", "sc-1", {:normal, :warning}, 1)
    persist!("P1", "sc-1", {:normal, :critical}, 2, mission: "#{@mission}-other")

    assert %Event{normalized_state: :yellow} = LimitReads.latest_state(@mission, "P1", [])

    assert [%Event{normalized_state: :yellow}] = history("P1")
  end

  test "the history is the transitions, newest first, bounded by order, limit and time" do
    persist!("P1", "sc-1", {:normal, :warning}, 1)
    persist!("P1", "sc-1", {:warning, :critical}, 5)
    persist!("P1", "sc-1", {:critical, :normal}, 9)

    assert Enum.map(history("P1"), & &1.normalized_state) == [:green, :red, :yellow]
    assert Enum.map(history("P1", order: :asc), & &1.normalized_state) == [:yellow, :red, :green]
    assert [%{normalized_state: :green}] = history("P1", limit: 1)

    assert [%{normalized_state: :red}] =
             history("P1", from_receipt_time: at(3), to_receipt_time: at(7))

    # The state as of a time is the newest transition up to it.
    assert %Event{normalized_state: :yellow} =
             LimitReads.latest_state(@org, @mission, "P1", to_receipt_time: at(3))

    assert Enum.map(history("P1", spacecraft_id: "sc-9"), & &1.normalized_state) == []
  end

  test "a state that raises and clears nothing is not an event" do
    persist!("P1", "sc-1", {:normal, :critical}, 1)
    persist!("P1", "sc-1", {:critical, :disabled}, 5)

    assert [%{normalized_state: :red}] = history("P1")
    # The point's latest state row is the disabled one, which says nothing.
    assert LimitReads.latest_state(@org, @mission, "P1", []) == nil
  end

  test "the watermark merges the states and the transitions" do
    persist!("P1", "sc-1", {:normal, :warning}, 1)
    persist!("P1", "sc-1", {:warning, :critical}, 5)

    assert {:ok, watermark} = LimitReads.watermark_result(@org, @mission, "P1", [])

    assert watermark.latest_receipt_time == at(5)
    assert watermark.retention_starts_at == at(1)
    assert watermark.confidence == :best_effort
    assert watermark.projection_sources == %{latest_state_count: 1, event_count: 2}

    assert {:ok, %{confidence: :unknown, sample_count: 0}} =
             LimitReads.watermark_result(@org, @mission, "none", [])
  end

  test "a limit event link resolves by the transition id, and an unknown id is not found" do
    persist!("P1", "sc-1", {:normal, :critical}, 1)
    [%{limit_event_id: id}] = history("P1")

    assert {:ok, %Event{limit_event_id: ^id, normalized_state: :red, point_id: "P1"}} =
             AlarmEvents.fetch(@org, @mission, id)

    assert {:error, :limit_event_not_found} = AlarmEvents.fetch(@org, @mission, "nope")
    assert {:error, :limit_event_not_found} = AlarmEvents.fetch(@org, "#{@mission}-other", id)
  end

  test "definition intervals are empty for monitoring rules" do
    persist!("P1", "sc-1", {:normal, :critical}, 1)

    assert LimitReads.definition_intervals(@org, @mission, "P1", []) == []
    assert LimitReads.definition_intervals(@mission, "P1") == []
  end
end

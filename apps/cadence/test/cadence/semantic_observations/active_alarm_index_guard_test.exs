defmodule Cadence.SemanticObservations.ActiveAlarmIndexGuardTest do
  @moduledoc """
  The active-alarm partial index hard-codes the alarm severities in SQL (the migration of #926); the
  level table is `SemanticRuntime.AlarmLevel`'s (#451 T2). The index must name every severity the
  module says raises an alarm, and no other, or the fleet refresh's `@active` filter (built from the
  module) stops matching the index's predicate and the refresh seq-scans. A new severity added to
  `AlarmLevel` fails here until the index moves with it.
  """
  use Cadence.DataCase, async: true

  alias Cadence.SemanticRuntime.AlarmLevel

  test "semantic_latest_alarm_states_active_idx names exactly the alarming severities" do
    %{rows: [[definition]]} =
      Repo.query!("SELECT pg_get_indexdef('semantic_latest_alarm_states_active_idx'::regclass)")

    states = AlarmLevel.states_of(:caution) ++ AlarmLevel.states_of(:critical)

    for state <- states do
      assert definition =~ "'#{state}'",
             "the index predicate does not name #{state}: #{definition}"
    end

    # The predicate's `effective_state IN (...)` list has no severity the module does not know.
    [_, predicate] = String.split(definition, "WHERE", parts: 2)

    [list] =
      Regex.run(~r/effective_state\)?::text = ANY \(ARRAY\[(.*?)\]\)/s, predicate,
        capture: :all_but_first
      ) || [""]

    named = ~r/'([a-z_]+)'/ |> Regex.scan(list, capture: :all_but_first) |> List.flatten()
    assert Enum.sort(named) == Enum.sort(states), "index predicate: #{predicate}"
  end
end

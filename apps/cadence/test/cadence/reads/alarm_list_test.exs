defmodule Cadence.Reads.AlarmListTest do
  use ExUnit.Case, async: true

  alias Cadence.Limits.Event
  alias Cadence.Reads.AlarmList

  defp event(state, minute), do: %Event{normalized_state: state, generation_time: at(minute)}
  defp at(minute), do: DateTime.add(~U[2026-11-08 02:00:00Z], minute * 60)

  test "first crossing is the oldest event of the current unbroken run" do
    history = [event(:red, 5), event(:red, 4), event(:yellow, 3), event(:red, 2)]
    assert AlarmList.first_crossed_from_history(:red, history) == at(4)
  end

  test "is nil when the newest evaluation is not in the current state" do
    assert AlarmList.first_crossed_from_history(:red, [event(:green, 5)]) == nil
    assert AlarmList.first_crossed_from_history(:red, []) == nil
  end
end

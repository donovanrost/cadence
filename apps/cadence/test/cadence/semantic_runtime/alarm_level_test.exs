defmodule Cadence.SemanticRuntime.AlarmLevelTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Alarms.Sources
  alias Cadence.SemanticRuntime.AlarmLevel

  @table [
    {:normal, :normal},
    {:watch, :caution},
    {:warning, :caution},
    {:distress, :critical},
    {:critical, :critical},
    {:severe, :critical},
    {:unknown, :ignore},
    {:disabled, :ignore}
  ]

  test "the fixed severity to alarm level table, from the atom or its text" do
    for {severity, level} <- @table do
      assert AlarmLevel.level(severity) == level
      assert AlarmLevel.level(Atom.to_string(severity)) == level
    end

    # Anything else changes nothing, and text no one has an atom for is never made one.
    assert AlarmLevel.level("severity_nobody_declared_#{System.unique_integer([:positive])}") ==
             :ignore

    assert AlarmLevel.level(nil) == :ignore
    assert AlarmLevel.level(42) == :ignore
  end

  test "which severities raise an alarm, and the SQL lists built from the table" do
    assert AlarmLevel.alarm_states() == [:watch, :warning, :distress, :critical, :severe]
    assert Enum.all?(AlarmLevel.alarm_states(), &AlarmLevel.alarming?/1)
    refute Enum.any?([:normal, :unknown, :disabled], &AlarmLevel.alarming?/1)

    assert AlarmLevel.states_of(:caution) == ["watch", "warning"]
    assert AlarmLevel.states_of(:critical) == ["distress", "critical", "severe"]
    assert AlarmLevel.sql_in([:critical]) == "'distress', 'critical', 'severe'"

    assert AlarmLevel.sql_in([:caution, :critical]) ==
             "'watch', 'warning', 'distress', 'critical', 'severe'"
  end

  test "the alarm episodes read the level from it" do
    update = %{generation_time: nil, receipt_time: ~U[2026-11-28 12:00:00Z], value: 1}

    for {severity, level} <- @table do
      attrs = %{
        organization_id: "o",
        mission_id: "m",
        spacecraft_id: "sc",
        parameter_id: "p",
        policy_id: "pol",
        mission_model_revision_id: "r",
        effective_state: Atom.to_string(severity)
      }

      assert %{level: ^level} = Sources.catalog(attrs, update, "t")
    end
  end
end

defmodule CadenceSimulator.Providers.ScenarioProviderTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.Providers.ScenarioProvider
  alias CadenceSimulator.Scenario.Parser

  @scenario """
  version: "1.0"
  name: "Battery Ramp"
  target_id: "SIM-1"
  baseline:
    HEALTH.battery_voltage: 14.5
    HEALTH.mode: "NOMINAL"
  timeline:
    - step: 2
      inject:
        HEALTH.battery_voltage:
          type: ramp
          from: 14.5
          to: 12.0
          steps: 2
          noise: 0.0
      description: "Voltage dropping"
    - step: 5
      end: true
  """

  test "parses and normalizes a scenario document" do
    assert {:ok, scenario} = Parser.parse_string(@scenario)
    assert scenario.name == "Battery Ramp"
    assert scenario.baseline["HEALTH.mode"] == "NOMINAL"
    assert Enum.at(scenario.timeline, 0).inject["HEALTH.battery_voltage"].type == :ramp
  end

  test "applies injections over time and marks completion" do
    {:ok, state} = ScenarioProvider.init(%{scenario: elem(Parser.parse_string(@scenario), 1)})

    {:ok, values_0, state} = ScenarioProvider.generate_values(state, 0)
    {:ok, values_2, state} = ScenarioProvider.generate_values(state, 2)
    {:ok, values_4, state} = ScenarioProvider.generate_values(state, 4)
    {:ok, values_5, state} = ScenarioProvider.generate_values(state, 5)
    {:ok, values_6, state} = ScenarioProvider.generate_values(state, 6)

    assert values_0["HEALTH.battery_voltage"] == 14.5
    assert values_2["HEALTH.battery_voltage"] == 14.5
    assert values_4["HEALTH.battery_voltage"] == 12.0
    assert state.completed
    assert values_5["HEALTH.battery_voltage"] == 12.0
    assert values_6["HEALTH.battery_voltage"] == 14.5
  end
end

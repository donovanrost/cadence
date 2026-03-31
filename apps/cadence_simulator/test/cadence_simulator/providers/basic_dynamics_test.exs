defmodule CadenceSimulator.Providers.BasicDynamicsTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.Providers.BasicDynamics

  test "generates the expected point families" do
    {:ok, state} = BasicDynamics.init(%{packets: [:health, :power], noise_amplitude: 0.0})
    {:ok, values, ^state} = BasicDynamics.generate_values(state, 10)

    assert values["HEALTH.cpu_temp"]
    assert values["HEALTH.uptime_seconds"] == 100
    assert values["POWER.bus_voltage"]
    refute Map.has_key?(values, "ATTITUDE.roll")
  end
end

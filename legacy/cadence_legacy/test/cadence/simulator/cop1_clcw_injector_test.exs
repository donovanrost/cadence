defmodule Cadence.Simulator.COP1.CLCWInjectorTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Simulator.COP1.CLCWInjector

  test "applies static overrides" do
    injector =
      CLCWInjector.new(overrides: %{lockout: 1, wait: true, report_value: "7"})

    clcw = %CLCW{vcid: 5, report_value: 3}
    updated = CLCWInjector.apply(injector, clcw, 0)

    assert updated.lockout == 1
    assert updated.wait == 1
    assert updated.report_value == 7
    assert updated.vcid == 5
  end

  test "applies schedule overrides by step" do
    injector =
      CLCWInjector.new(
        schedule: [
          %{at: 5, overrides: %{wait: 1}},
          %{at: 10, overrides: %{wait: 0, lockout: 1}}
        ]
      )

    clcw = %CLCW{}

    assert CLCWInjector.apply(injector, clcw, 4).wait == 0
    assert CLCWInjector.apply(injector, clcw, 5).wait == 1

    updated = CLCWInjector.apply(injector, clcw, 12)
    assert updated.wait == 0
    assert updated.lockout == 1
  end
end

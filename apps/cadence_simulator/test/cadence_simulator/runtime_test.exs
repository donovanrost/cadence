defmodule CadenceSimulator.RuntimeTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Coordinator

  @definitions """
  version: "1.0.0"
  packets:
    - name: HK
      apid: 1
      items:
        - name: uptime_seconds
          bit_offset: 0
          bit_size: 16
          data_type: uint
          endianness: big
  """

  test "start_simulator starts a coordinator under the runtime supervisor" do
    {:ok, pid} =
      CadenceSimulator.start_simulator(
        target_id: "SIM-1",
        rate_hz: 5.0,
        definitions_content: @definitions,
        output: nil
      )

    on_exit(fn ->
      if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
    end)

    assert Process.alive?(pid)
    assert %{target_id: "SIM-1"} = Coordinator.stats(pid)
    assert :ok = CadenceSimulator.set_simulator_rate(pid, 20.0)
    assert %{rate_hz: 20.0} = Coordinator.stats(pid)

    assert :ok = CadenceSimulator.stop_simulator(pid)
    refute Process.alive?(pid)
  end
end

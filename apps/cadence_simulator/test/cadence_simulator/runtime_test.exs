defmodule CadenceSimulator.RuntimeTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Coordinator
  alias CadenceSimulator.Providers.DatabaseDynamics

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

  @command_definitions """
  packets:
    - name: HK
      apid: 1
      items:
        - name: mode
          bit_offset: 0
          bit_size: 8
          data_type: uint
          conversion:
            type: state_table
            states:
              0: SAFE
              1: NOMINAL
  commands:
    - name: SET_MODE
      opcode: 3
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
      effects:
        - target: HK.mode
          operation: set
          argument: mode
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

  test "runtime command APIs apply named and encoded compiled commands" do
    {:ok, pid} =
      CadenceSimulator.start_simulator(
        target_id: "SIM-COMMAND",
        rate_hz: 5.0,
        definitions_content: @command_definitions,
        provider: DatabaseDynamics,
        output: nil
      )

    on_exit(fn ->
      if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
    end)

    assert {:ok, %{command_name: "SET_MODE", arguments: %{"mode" => 1}}} =
             CadenceSimulator.execute_command(pid, "SET_MODE", %{"mode" => 1})

    assert %{provider_status: %{command_count: 1, overridden_point_count: 1}} =
             CadenceSimulator.simulator_stats(pid)

    assert {:ok, %{command_name: "SET_MODE", arguments: %{"mode" => 0}}} =
             CadenceSimulator.execute_encoded_command(pid, <<3, 0>>)

    assert %{provider_status: %{command_count: 2}} = CadenceSimulator.simulator_stats(pid)
  end
end

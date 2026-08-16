defmodule CadenceSimulator.Providers.DatabaseDynamicsTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.Providers.DatabaseDynamics

  @definitions """
  version: "1.0.0"
  packets:
    - name: HK
      apid: 1
      items:
        - name: cpu_temp
          bit_size: 32
          data_type: float
          limits:
            yellow_low: 10.0
            yellow_high: 20.0

        - name: uptime_seconds
          bit_size: 16
          data_type: uint

        - name: mode
          bit_size: 8
          data_type: uint
          conversion:
            type: state_table
            states:
              0: "SAFE"
              1: "NOMINAL"

        - name: label
          bit_size: 64
          data_type: string

        - name: blob
          bit_size: 16
          data_type: binary
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
              0: "SAFE"
              1: "NOMINAL"
  commands:
    - name: SET_MODE
      opcode: 3
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
          valid_values: [0, 1]
      effects:
        - target: HK.mode
          operation: set
          argument: mode
  """

  test "precompiled definitions still generate the expected value shapes" do
    {:ok, state} =
      DatabaseDynamics.init(%{
        definitions_content: @definitions,
        noise_amplitude: 0.0
      })

    assert DatabaseDynamics.status(state) == %{
             provider: "DatabaseDynamics",
             packet_count: 1,
             item_count: 5,
             noise_amplitude: 0.0,
             command_count: 0,
             last_command: nil,
             overridden_point_count: 0
           }

    {:ok, values_at_0, same_state} = DatabaseDynamics.generate_values(state, 0)
    {:ok, values_at_10, ^same_state} = DatabaseDynamics.generate_values(same_state, 10)

    assert values_at_0["HK.cpu_temp"] >= 10.0
    assert values_at_0["HK.cpu_temp"] <= 20.0
    assert values_at_0["HK.uptime_seconds"] == 0
    assert values_at_10["HK.uptime_seconds"] == 10
    assert values_at_10["HK.label"] == "HK_label_v10"
    assert byte_size(values_at_10["HK.blob"]) == 2
    assert values_at_0["HK.mode"] in ["NOMINAL", "SAFE"]
    assert values_at_10["HK.mode"] in ["NOMINAL", "SAFE"]
    assert values_at_0["HK.mode"] != values_at_10["HK.mode"]
  end

  test "precompiled definitions generate packet-scoped values in yaml order" do
    {:ok, state} =
      DatabaseDynamics.init(%{
        definitions_content: @definitions,
        noise_amplitude: 0.0
      })

    {:ok, [{"HK", [cpu_temp, uptime_seconds, mode, label, blob]}], ^state} =
      DatabaseDynamics.generate_packet_values(state, 10)

    assert uptime_seconds == 10
    assert label == "HK_label_v10"
    assert byte_size(blob) == 2
    assert mode in ["NOMINAL", "SAFE"]
    assert cpu_temp >= 10.0
    assert cpu_temp <= 20.0
  end

  test "compiled commands change subsequent generated telemetry" do
    {:ok, state} =
      DatabaseDynamics.init(%{
        definitions_content: @command_definitions,
        noise_amplitude: 0.0
      })

    assert {:ok, %{"HK.mode" => "SAFE"}, ^state} =
             DatabaseDynamics.generate_values(state, 0)

    assert {:ok, command_result, ^state} =
             DatabaseDynamics.execute_command(state, "SET_MODE", %{"mode" => 1})

    assert command_result.command_name == "SET_MODE"

    assert [
             %{
               target_ref: target_ref,
               operation: :set,
               value: "NOMINAL"
             } = applied_effect
           ] = command_result.applied_effects

    assert String.starts_with?(target_ref, "semantic:parameter:")
    assert applied_effect.effect_id == "command_effect:0:0"

    assert {:ok, %{"HK.mode" => "NOMINAL"}, ^state} =
             DatabaseDynamics.generate_values(state, 0)

    assert {:ok, encoded_result, ^state} =
             DatabaseDynamics.execute_encoded_command(state, <<3, 0>>)

    assert encoded_result.arguments == %{"mode" => 0}

    assert {:ok, %{"HK.mode" => "SAFE"}, ^state} =
             DatabaseDynamics.generate_values(state, 0)

    assert %{
             command_count: 2,
             last_command: %{command_name: "SET_MODE"},
             overridden_point_count: 1
           } = DatabaseDynamics.status(state)
  end

  test "the demo spacecraft database changes mode telemetry after SET_MODE" do
    demo_path =
      Path.expand(
        "../../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml",
        __DIR__
      )

    assert {:ok, state} =
             DatabaseDynamics.init(%{
               definitions_path: demo_path,
               noise_amplitude: 0.0
             })

    assert {:ok, %{command_name: "SET_MODE"}, ^state} =
             DatabaseDynamics.execute_command(state, "SET_MODE", %{"mode" => 4})

    assert {:ok, values, ^state} = DatabaseDynamics.generate_values(state, 0)
    assert values["HK.sc_mode"] == "SCIENCE"
  end
end

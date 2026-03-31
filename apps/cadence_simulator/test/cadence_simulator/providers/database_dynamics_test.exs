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
             noise_amplitude: 0.0
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
end

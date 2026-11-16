defmodule Cadence.Catalog.TelemetryCalibrationSwitchTest do
  @moduledoc """
  Calibration (telemetry contract 3, #92 (c)) is OFF unless the server's configuration turns it on
  (director, 11-16: the user's call, recorded in DECISIONS). Off, an import compiles exactly as it
  did before calibration: telemetry contract 2 and the same plans, byte for byte. The golden
  hashes and diagnostics below are what the code before calibration (3a128038c; the catalog
  package is unchanged from there to the head) compiles for this catalog.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.MissionModel.{Compiler, Target}
  alias Cadence.Catalog.Source

  # A polynomial, a state table, a plain field, and a verifier comparing the state parameter
  # calibrated against a number (the comparison calibration warns about).
  @database """
  version: "1.0.0"
  packets:
    - name: THERM
      apid: 43
      items:
        - name: temp
          bit_offset: 0
          bit_size: 16
          data_type: uint
          conversion:
            type: polynomial
            coefficients: [-40.0, 0.01]
        - name: mode
          bit_offset: 16
          bit_size: 8
          data_type: uint
          conversion:
            type: state_table
            states:
              0: SAFE
              1: NOMINAL
        - name: plain
          bit_offset: 24
          bit_size: 8
          data_type: uint
  commands:
    - name: SET_MODE
      apid: 77
      opcode: 3
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
          valid_values: [0, 1]
      verifiers:
        - name: Mode applied
          phase: completion
          timeout_ms: 30000
          success_criteria:
            criteria_type: comparison
            subject_ref: telemetry:THERM.mode
            comparison: equal
            value: 1
  """

  @golden [
    {:algorithm, "1", "cdefc024e4ed1912bdb287ce6ed05b03a07a2900afb7f550bae211e146205425", []},
    {:command, "2", "0de507c506705152a946ed3b3c981bdc8ce6ca98a43c189a9bc1fd3c91a748a5", []},
    {:monitoring, "1", "27629f058ef9a8a70a6e373a47236d68bdba4581f7c361958c4f9fcc2637aeb2", []},
    {:telemetry, "2", "8de7b6efebfa6baa968640c0ce216ea96f800901f0bc64768cf80e3d9158fa4b",
     ["MM_CALIBRATOR_RUNTIME_UNSUPPORTED"]}
  ]

  describe "calibration off (the default)" do
    test "the server setting defaults to off" do
      refute Target.calibration?()
      assert Target.contracts().telemetry == "2"
    end

    test "a calibrated catalog compiles to the plans it compiled to before calibration" do
      compilation = compile([])

      assert compilation.plans.telemetry.target_contract_version == "2"
      [packet] = compilation.plans.telemetry.plan["packet_definitions"]

      for field <- packet["fields"] do
        refute Map.has_key?(field, "calibrator")
        refute Map.has_key?(field, "enumerations")
      end

      assert golden(compilation) == @golden
    end
  end

  describe "calibration on" do
    test "the option (or the server setting) compiles telemetry contract 3" do
      assert Target.calibration?(telemetry_calibration: true)
      assert Target.contracts(telemetry_calibration: true).telemetry == "3"

      compilation = compile(telemetry_calibration: true)
      assert compilation.plans.telemetry.target_contract_version == "3"
      [packet] = compilation.plans.telemetry.plan["packet_definitions"]
      fields = Map.new(packet["fields"], &{&1["name"], &1})

      assert fields["temp"]["calibrator"] == %{
               "type" => "polynomial",
               "coefficients" => [-40.0, 0.01]
             }

      assert "MM_CALIBRATED_COMPARISON_NUMERIC_ON_STATES" in codes(compilation.plans.command)
    end
  end

  defp compile(opts) do
    {:ok, import_result} =
      CadenceYamlDatabase.import(source(), %{import_run_id: "calibration-switch"})

    [layer] = import_result.bundle.declaration_layers
    {:ok, compilation} = Compiler.compile([layer], opts)
    compilation
  end

  defp golden(compilation) do
    compilation.plans
    |> Enum.map(fn {target, plan} ->
      {target, plan.target_contract_version, plan.content_sha256, codes(plan)}
    end)
    |> Enum.sort()
  end

  defp codes(plan), do: plan.diagnostics |> Enum.map(& &1.code) |> Enum.sort()

  defp source do
    Source.new(%{
      artifact_id: "calibration-switch-database",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      catalog_family: :combined,
      artifact_name: "calibration-switch.yaml",
      format_key: "cadence_yaml",
      media_type: "application/yaml",
      source_artifact: @database
    })
  end
end

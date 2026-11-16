defmodule Cadence.Catalog.VerifierArgumentCriteriaTest do
  @moduledoc """
  `value_from_argument` (#38 verifier scope): a verifier compares telemetry with the value the
  command was sent with. The argument must exist and its type must match what's compared.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.Catalog.Source

  test "SET_MODE verifies HK.mode (raw) == its mode argument; the argument binds to its id" do
    source = source(criteria("telemetry:HK.mode", "mode", false))
    assert :ok = CadenceYamlDatabase.validate(source)

    {:ok, compilation} = compile(source)
    assert compilation.revision.diagnostics == []

    assert [%{"argument_specs" => [argument]}] =
             compilation.plans.command.plan["runtime_definitions"]

    assert [%{"success_criteria" => success}] = compilation.plans.command.plan["verifier_plans"]
    assert success["value_from_argument"] == argument["argument_id"]
    assert String.starts_with?(success["subject_ref"], "semantic:parameter:")
    assert success["use_calibrated"] == false
  end

  test "the importer rejects an argument the command doesn't have, or value alongside it" do
    assert {:error, {:validation_error, unknown}} =
             CadenceYamlDatabase.validate(source(criteria("telemetry:HK.mode", "speed", false)))

    assert unknown =~ "value_from_argument names 'speed', which isn't an argument of this command"

    both = criteria("telemetry:HK.mode", "mode", false, ["value: 1"])

    assert {:error, {:validation_error, reason}} = CadenceYamlDatabase.validate(source(both))
    assert reason =~ "can't have both value and value_from_argument"
  end

  test "lowering rejects a type mismatch: a state-table parameter compared calibrated reads a label" do
    # use_calibrated defaults to true: HK.mode's engineering value is "SAFE"/"NOMINAL", not 0/1.
    source = source(criteria("telemetry:HK.mode", "mode", nil))
    assert :ok = CadenceYamlDatabase.validate(source)

    assert {:error, diagnostics} = compile(source)

    assert Enum.any?(
             List.wrap(diagnostics),
             &(inspect(&1) =~ "verifier_argument_type_mismatch")
           )
  end

  test "lowering rejects value_from_argument on a non-telemetry subject" do
    source = source(criteria("transport:completed", "mode", false))
    assert :ok = CadenceYamlDatabase.validate(source)
    assert {:error, diagnostics} = compile(source)

    assert Enum.any?(
             List.wrap(diagnostics),
             &(inspect(&1) =~ "verifier_argument_subject_not_parameter")
           )
  end

  describe "a calibrated comparison on a state parameter (#92 (c))" do
    test "against a number warns: the calibrated value is the label" do
      {:ok, compilation} = compile_with_warnings(source(value_criteria("1", nil)))

      assert [warning] =
               Enum.filter(
                 compilation.plans.command.diagnostics,
                 &(&1.code == "MM_CALIBRATED_COMPARISON_NUMERIC_ON_STATES")
               )

      assert warning.severity == :warning
      assert warning.message =~ "SAFE, NOMINAL"
      assert warning.message =~ "use_calibrated: false"
      assert compilation.plans.command.status == :ready
    end

    test "against the label, or raw against a number, doesn't" do
      for criteria <- [value_criteria("NOMINAL", nil), value_criteria("1", false)] do
        assert {:ok, _compilation} = compile(source(criteria))
      end
    end
  end

  defp compile_with_warnings(source) do
    {:ok, import_result} = CadenceYamlDatabase.import(source, %{import_run_id: "verifier-args"})
    [layer] = import_result.bundle.declaration_layers
    Compiler.compile([layer])
  end

  defp value_criteria(value, calibrated) do
    [
      "criteria_type: comparison",
      "subject_ref: telemetry:HK.mode",
      "comparison: equal",
      "value: #{value}"
    ]
    |> Kernel.++(if is_nil(calibrated), do: [], else: ["use_calibrated: #{calibrated}"])
    |> Enum.map_join("\n", &("          " <> &1))
  end

  defp compile(source) do
    {:ok, import_result} = CadenceYamlDatabase.import(source, %{import_run_id: "verifier-args"})
    [layer] = import_result.bundle.declaration_layers

    # Lowering errors are the command plan's diagnostics, not the revision's.
    case Compiler.compile([layer]) do
      {:ok, compilation} ->
        case compilation.revision.diagnostics ++ compilation.plans.command.diagnostics do
          [] -> {:ok, compilation}
          diagnostics -> {:error, diagnostics}
        end

      {:error, diagnostics} ->
        {:error, diagnostics}
    end
  end

  # The criteria block, indented under `success_criteria:` in the YAML below.
  defp criteria(subject, argument, calibrated, extra \\ []) do
    [
      "criteria_type: comparison",
      "subject_ref: #{subject}",
      "comparison: equal",
      "value_from_argument: #{argument}"
    ]
    |> Kernel.++(if is_nil(calibrated), do: [], else: ["use_calibrated: #{calibrated}"])
    |> Kernel.++(extra)
    |> Enum.map_join("\n", &("          " <> &1))
  end

  defp source(criteria) do
    Source.new(%{
      artifact_id: "verifier-argument-database",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      catalog_family: :combined,
      artifact_name: "verifier.yaml",
      format_key: "cadence_yaml",
      media_type: "application/yaml",
      source_artifact: """
      version: "1.0.0"
      packets:
        - name: HK
          apid: 42
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
      #{criteria}
      """
    })
  end
end

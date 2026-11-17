defmodule Cadence.Catalog.CadenceYamlDatabaseTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.Catalog.Source

  @database """
  version: "1.0.0"
  packets:
    - name: HK
      apid: 42
      items:
        - name: temperature_c
          bit_offset: 0
          bit_size: 32
          data_type: float
        - name: mode
          bit_offset: 32
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
      effects:
        - target: HK.mode
          operation: set
          argument: mode
  """

  test "imports and compiles a combined database without Cadence persistence" do
    source =
      Source.new(%{
        artifact_id: "simulator-database",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: "simulator.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: @database
      })

    assert :ok = CadenceYamlDatabase.validate(source)

    assert {:ok, import_result} =
             CadenceYamlDatabase.import(source, %{import_run_id: "simulator-import"})

    assert import_result.imported_definition_count == 2
    assert [layer] = import_result.bundle.declaration_layers

    assert Enum.any?(layer.declarations, &(&1.kind == :container and &1.name == "HK"))
    assert Enum.any?(layer.declarations, &(&1.kind == :monitoring_policy)) == false

    assert {:ok, compilation} = Compiler.compile([layer])
    assert compilation.revision.diagnostics == []

    assert [packet_definition] = compilation.plans.telemetry.plan["packet_definitions"]
    assert packet_definition["packet_name"] == "HK"
    assert Enum.map(packet_definition["fields"], & &1["name"]) == ["temperature_c", "mode"]

    assert [runtime_definition] = compilation.plans.command.plan["runtime_definitions"]
    assert runtime_definition["name"] == "SET_MODE"
    assert runtime_definition["apid"] == 77
    assert runtime_definition["mission_model_revision_id"] == compilation.revision.revision_id
    assert [argument] = runtime_definition["argument_specs"]
    assert argument["name"] == "mode"

    assert [state_effect] = runtime_definition["state_effects"]
    assert String.starts_with?(state_effect["target_ref"], "semantic:parameter:")
    assert state_effect["operation"] == "set"

    assert state_effect["argument_id"] ==
             argument["argument_id"]
  end

  # #92 (c), 11-15: telemetry contract 3. A polynomial calibrator and a state table reach the
  # field, so decom can compute the engineering value (it took raw as engineering before).
  test "a field carries its polynomial calibrator and its states (telemetry contract 3)" do
    database = """
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
                1: NOMINAL
                0: SAFE
          - name: plain
            bit_offset: 24
            bit_size: 8
            data_type: uint
    commands: []
    """

    {:ok, import_result} =
      CadenceYamlDatabase.import(source(database), %{import_run_id: "calibration-import"})

    [layer] = import_result.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])
    assert compilation.plans.telemetry.target_contract_version == "3"

    refute Enum.any?(
             compilation.revision.diagnostics,
             &(&1.code == "MM_CALIBRATOR_RUNTIME_UNSUPPORTED")
           )

    [packet] = compilation.plans.telemetry.plan["packet_definitions"]
    fields = Map.new(packet["fields"], &{&1["name"], &1})

    assert fields["temp"]["calibrator"] == %{
             "type" => "polynomial",
             "coefficients" => [-40.0, 0.01]
           }

    assert fields["temp"]["enumerations"] == []
    assert fields["mode"]["calibrator"] == nil

    assert fields["mode"]["enumerations"] == [
             %{"value" => 0, "label" => "SAFE"},
             %{"value" => 1, "label" => "NOMINAL"}
           ]

    assert fields["plain"]["calibrator"] == nil
    assert fields["plain"]["enumerations"] == []
  end

  test "states with a non-integer value or a repeated value are warned about; the first label wins" do
    database = """
    packets:
      - name: EPS
        apid: 44
        items:
          - name: mode
            bit_offset: 0
            bit_size: 8
            data_type: uint
            conversion:
              type: state_table
              states:
                0: OFF
                1: ON
    commands: []
    """

    {:ok, import_result} =
      CadenceYamlDatabase.import(source(database), %{import_run_id: "enumeration-import"})

    [layer] = import_result.bundle.declaration_layers

    # Hand-edit the type's states (the YAML importer only emits valid integers).
    declarations =
      Enum.map(layer.declarations, fn
        %{kind: :parameter_type} = type ->
          %{
            type
            | definition:
                Map.put(type.definition, :enumerations, [
                  %{value: 0, label: "OFF"},
                  %{value: "0x1", label: "ON"},
                  %{value: 0, label: "STANDBY"}
                ])
          }

        other ->
          other
      end)

    assert {:ok, compilation} = Compiler.compile([%{layer | declarations: declarations}])
    codes = Enum.map(compilation.plans.telemetry.diagnostics, & &1.code)
    assert "MM_ENUMERATION_VALUE_INVALID" in codes
    assert "MM_ENUMERATION_VALUE_DUPLICATE" in codes

    [packet] = compilation.plans.telemetry.plan["packet_definitions"]
    [field] = packet["fields"]
    assert field["enumerations"] == [%{"value" => 0, "label" => "OFF"}]
  end

  defp source(database) do
    Source.new(%{
      artifact_id: "calibration-database",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      catalog_family: :combined,
      artifact_name: "calibration.yaml",
      format_key: "cadence_yaml",
      media_type: "application/yaml",
      source_artifact: database
    })
  end

  # 2026-11-12: YAML limits lower to the same default_rules the XTCE importer gives, so they
  # reach the monitoring plan (before, they lowered to no rules and never alarmed).
  test "limits become COSMOS-style monitoring rules in the monitoring plan" do
    database = """
    version: "1.0.0"
    packets:
      - name: HK
        apid: 42
        items:
          - name: error_count
            bit_offset: 0
            bit_size: 16
            data_type: uint
            limits:
              red_low: -1
              yellow_low: 0
              yellow_high: 5
              red_high: 20
    commands: []
    """

    source =
      Source.new(%{
        artifact_id: "limits-database",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: "limits.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: database
      })

    assert {:ok, import_result} =
             CadenceYamlDatabase.import(source, %{import_run_id: "limits-import"})

    assert [layer] = import_result.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])
    assert [policy] = compilation.plans.monitoring.plan["policies"]

    # The stored plan is JSON (string keys and values); compare in that form.
    rules =
      policy["default_rules"]
      |> Enum.map(fn rule -> Map.new(rule, fn {k, v} -> {to_string(k), json_value(v)} end) end)
      |> Enum.sort_by(&{&1["severity"], &1["value"]})

    assert rules == [
             %{
               "kind" => "comparison",
               "operator" => "<",
               "value" => -1,
               "severity" => "critical"
             },
             %{
               "kind" => "comparison",
               "operator" => ">",
               "value" => 20,
               "severity" => "critical"
             },
             %{"kind" => "comparison", "operator" => "<", "value" => 0, "severity" => "warning"},
             %{"kind" => "comparison", "operator" => ">", "value" => 5, "severity" => "warning"}
           ]
  end

  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  test "rejects command APIDs outside the Space Packet field" do
    source =
      Source.new(%{
        artifact_id: "invalid-command-apid",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :command,
        artifact_name: "invalid.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        commands:
          - name: INVALID
            apid: 2048
            opcode: 1
        """
      })

    assert CadenceYamlDatabase.validate(source) ==
             {:error,
              {:validation_error, "Command 'INVALID' APID must be between 0 and 2047, got 2048"}}
  end
end

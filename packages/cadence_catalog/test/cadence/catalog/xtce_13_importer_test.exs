defmodule Cadence.Catalog.Xtce13ImporterTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.Xtce13
  alias Cadence.Catalog.MissionModel.{Compiler, Xtce13Exporter}
  alias Cadence.Catalog.Source

  test "imports SpaceSystems, telemetry, algorithms, alarms, and commands into one graph" do
    source = source(xtce_document())

    assert :ok = Xtce13.validate(source)
    assert {:ok, result} = Xtce13.import(source, %{import_run_id: "import-xtce-1"})
    assert [layer] = result.bundle.declaration_layers

    assert Enum.any?(result.diagnostics, fn diagnostic ->
             diagnostic.code == "XTCE_ALGORITHM_REQUIRES_REGISTERED_IMPLEMENTATION"
           end)

    assert {:ok, compilation} = Compiler.compile([layer])

    declarations = Map.values(compilation.revision.declarations)

    assert declaration?(declarations, :space_system, "/Vehicle")
    assert declaration?(declarations, :space_system, "/Vehicle/POBC")
    assert declaration?(declarations, :parameter_type, "/Vehicle/types/TemperatureType")
    assert declaration?(declarations, :parameter, "/Vehicle/parameters/temperature")
    assert declaration?(declarations, :container, "/Vehicle/containers/HK")
    assert declaration?(declarations, :algorithm, "/Vehicle/algorithms/DoubleTemperature")
    assert declaration?(declarations, :monitoring_policy, "/Vehicle/monitoring/temperature")
    assert declaration?(declarations, :command, "/Vehicle/commands/SET_MODE")

    refute Enum.any?(compilation.revision.diagnostics, &(&1.severity == :error))
    assert compilation.plans.telemetry.status == :blocked
    assert compilation.plans.algorithm.status == :blocked
    assert compilation.plans.monitoring.status == :ready
    assert compilation.plans.command.status == :blocked

    assert diagnostic?(
             compilation.plans.telemetry,
             "MM_TELEMETRY_CONTAINER_NOT_LOWERABLE"
           )

    assert diagnostic?(
             compilation.plans.algorithm,
             "MM_REGISTERED_IMPLEMENTATION_IDENTITY_REQUIRED"
           )

    assert diagnostic?(compilation.plans.command, "MM_COMMAND_DEFINITION_NOT_LOWERABLE")

    # XTCE 1.2 rangeForm defaults to "outside": each range is the acceptable band (above 80 is a
    # warning, above 100 critical). The ChangeAlarmRanges (rate of change) isn't a value range.
    # Both temperature parameters share the type, so both carry these rules.
    assert [policy, _same] = compilation.plans.monitoring.plan["policies"]

    rules =
      policy["default_rules"]
      |> Enum.map(fn rule -> Map.new(rule, fn {k, v} -> {to_string(k), v} end) end)
      |> Enum.sort_by(& &1["upper"])

    assert [
             %{
               "kind" => :range,
               "upper" => warning_max,
               "outside" => true,
               "severity" => :warning
             },
             %{
               "kind" => :range,
               "upper" => critical_max,
               "outside" => true,
               "severity" => :critical
             }
           ] = rules

    assert {warning_max, critical_max} == {80.0, 100.0}
  end

  test "rangeForm inside alarms on values inside the range" do
    xml =
      String.replace(
        xtce_document(),
        "<StaticAlarmRanges>",
        ~s(<StaticAlarmRanges rangeForm="inside">)
      )

    assert {:ok, result} = Xtce13.import(source(xml), %{import_run_id: "import-xtce-inside"})
    assert [layer] = result.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])
    # Both temperature parameters share the type, so both carry these rules.
    assert [policy, _same] = compilation.plans.monitoring.plan["policies"]

    assert Enum.all?(policy["default_rules"], fn rule ->
             Map.get(rule, :outside, Map.get(rule, "outside")) == false
           end)
  end

  test "rejects document types and entity declarations before XML parsing" do
    xml = """
    <!DOCTYPE SpaceSystem [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
      <LongDescription>&secret;</LongDescription>
    </SpaceSystem>
    """

    assert {:error, :xtce_document_type_forbidden} = Xtce13.validate(source(xml))
  end

  test "validates against the pinned normative XTCE schema" do
    xml = """
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214">
      <TelemetryMetaData/>
    </SpaceSystem>
    """

    assert {:error, {:invalid_xtce_schema, diagnostic}} = Xtce13.validate(source(xml))
    assert diagnostic =~ "attribute 'name' is required"
  end

  test "preserves unsupported executable XTCE and blocks only its affected target" do
    xml = """
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
      <TelemetryMetaData>
        <ContainerSet>
          <SequenceContainer name="HK"><EntryList/></SequenceContainer>
        </ContainerSet>
        <MessageSet>
          <Message name="UnsupportedMessage">
            <MatchCriteria>
              <Comparison parameterRef="temperature" value="1"/>
            </MatchCriteria>
            <ContainerRef containerRef="HK"/>
          </Message>
        </MessageSet>
      </TelemetryMetaData>
    </SpaceSystem>
    """

    assert {:ok, imported} = Xtce13.import(source(xml), %{import_run_id: "unsupported"})
    assert [layer] = imported.bundle.declaration_layers

    extension = Enum.find(layer.declarations, &(&1.kind == :extension))
    assert extension.definition.required
    assert extension.definition.applies_to == [:telemetry]
    assert extension.definition.source_element["name"] == "MessageSet"

    assert {:ok, compilation} = Compiler.compile([layer])
    assert compilation.plans.telemetry.status == :blocked
    assert compilation.plans.algorithm.status == :ready
    assert compilation.plans.monitoring.status == :ready
    assert compilation.plans.command.status == :ready
  end

  test "schema-invalid source is rejected before declaration translation" do
    xml = """
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
      <TelemetryMetaData>
        <ParameterSet><Parameter name="missing_type"/></ParameterSet>
      </TelemetryMetaData>
    </SpaceSystem>
    """

    assert {:error, {:invalid_xtce_schema, diagnostic}} =
             Xtce13.import(source(xml), %{import_run_id: "invalid-source"})

    assert diagnostic =~ "parameterTypeRef"
  end

  test "exports supported core deterministically and produces parseable XTCE" do
    assert {:ok, imported} =
             xtce_document()
             |> source()
             |> Xtce13.import(%{import_run_id: "import-xtce-export"})

    assert [layer] = imported.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])

    assert {:ok, first, first_diagnostics} = Xtce13Exporter.export(compilation.revision)
    assert {:ok, second, second_diagnostics} = Xtce13Exporter.export(compilation.revision)

    assert first == second
    assert first_diagnostics == second_diagnostics
    assert first =~ ~s(xmlns="http://www.omg.org/spec/XTCE/20250214")
    assert first =~ ~s(<SpaceSystem name="POBC">)
    assert :ok = Xtce13.validate(source(first))
  end

  describe "calibration (#92 (c))" do
    test "a polynomial DefaultCalibrator becomes the type's calibrator, lowest order first" do
      encoding = """
      <IntegerDataEncoding sizeInBits="16" encoding="unsigned">
        <DefaultCalibrator>
          <PolynomialCalibrator>
            <Term coefficient="2.5" exponent="2"/>
            <Term coefficient="-40" exponent="0"/>
          </PolynomialCalibrator>
        </DefaultCalibrator>
      </IntegerDataEncoding>
      """

      {layer, compilation} = calibrated(integer_type(encoding))

      calibrator = Enum.find(layer.declarations, &(&1.kind == :calibrator))
      assert calibrator.qualified_name == "/Vehicle/calibrators/TempType/default"
      assert calibrator.definition.algorithm_type == :polynomial
      assert calibrator.definition.coefficients == [-40.0, 0.0, 2.5]

      type = Enum.find(layer.declarations, &(&1.kind == :parameter_type))
      assert [reference] = Enum.filter(type.references, &(&1.role == :calibrator))
      assert reference.source_ref == calibrator.qualified_name

      refute Enum.any?(compilation.plans.telemetry.diagnostics, fn diagnostic ->
               String.starts_with?(diagnostic.code, "MM_CALIBRATOR")
             end)
    end

    test "a spline and a context calibrator are declared and reported, never dropped" do
      encoding = """
      <IntegerDataEncoding sizeInBits="16" encoding="unsigned">
        <DefaultCalibrator>
          <SplineCalibrator>
            <SplinePoint raw="0" calibrated="-10"/>
            <SplinePoint raw="100" calibrated="90"/>
          </SplineCalibrator>
        </DefaultCalibrator>
        <ContextCalibratorList>
          <ContextCalibrator>
            <ContextMatch>
              <Comparison parameterRef="temp" value="1"/>
            </ContextMatch>
            <Calibrator>
              <PolynomialCalibrator><Term coefficient="1" exponent="1"/></PolynomialCalibrator>
            </Calibrator>
          </ContextCalibrator>
        </ContextCalibratorList>
      </IntegerDataEncoding>
      """

      {layer, compilation} = calibrated(integer_type(encoding))

      kinds =
        for declaration <- layer.declarations,
            declaration.kind == :calibrator,
            do: {declaration.qualified_name, declaration.definition.algorithm_type}

      assert Enum.sort(kinds) == [
               {"/Vehicle/calibrators/TempType/context_1", :context},
               {"/Vehicle/calibrators/TempType/default", :spline}
             ]

      unsupported =
        Enum.filter(
          compilation.plans.telemetry.diagnostics,
          &(&1.code == "MM_CALIBRATOR_RUNTIME_UNSUPPORTED")
        )

      assert length(unsupported) == 2
      assert Enum.all?(unsupported, &(&1.severity == :warning))
    end

    test "an unreadable polynomial says so at import" do
      encoding = """
      <IntegerDataEncoding sizeInBits="16" encoding="unsigned">
        <DefaultCalibrator>
          <PolynomialCalibrator><Term coefficient="1" exponent="40"/></PolynomialCalibrator>
        </DefaultCalibrator>
      </IntegerDataEncoding>
      """

      assert {:ok, result} =
               Xtce13.import(source(integer_type(encoding)), %{import_run_id: "calibration"})

      assert Enum.any?(result.diagnostics, &(&1.code == "XTCE_CALIBRATOR_DEGREE_UNSUPPORTED"))
      [layer] = result.bundle.declaration_layers
      refute Enum.any?(layer.declarations, &(&1.kind == :calibrator))
    end

    test "an EnumerationList becomes the type's states; a small range expands" do
      type = """
      <EnumeratedParameterType name="TempType">
        <IntegerDataEncoding sizeInBits="8" encoding="unsigned"/>
        <EnumerationList>
          <Enumeration value="0" label="OFF"/>
          <Enumeration value="1" label="ON"/>
          <Enumeration value="2" maxValue="4" label="FAULT"/>
          <Enumeration value="5" maxValue="100000" label="WILD"/>
        </EnumerationList>
      </EnumeratedParameterType>
      """

      assert {:ok, result} =
               Xtce13.import(source(calibration_document(type)), %{import_run_id: "e"})

      assert Enum.any?(result.diagnostics, &(&1.code == "XTCE_ENUMERATION_RANGE_UNSUPPORTED"))

      [layer] = result.bundle.declaration_layers
      type = Enum.find(layer.declarations, &(&1.kind == :parameter_type))

      assert type.definition.enumerations == [
               %{value: 0, label: "OFF"},
               %{value: 1, label: "ON"},
               %{value: 2, label: "FAULT"},
               %{value: 3, label: "FAULT"},
               %{value: 4, label: "FAULT"},
               %{value: 5, label: "WILD"}
             ]
    end
  end

  defp calibrated(xml) do
    assert {:ok, result} = Xtce13.import(source(xml), %{import_run_id: "calibration"})
    assert [layer] = result.bundle.declaration_layers
    assert {:ok, compilation} = Compiler.compile([layer])
    {layer, compilation}
  end

  defp integer_type(encoding) do
    calibration_document("""
    <IntegerParameterType name="TempType">
    #{encoding}
    </IntegerParameterType>
    """)
  end

  defp calibration_document(type) do
    """
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
      <TelemetryMetaData>
        <ParameterTypeSet>
    #{type}
        </ParameterTypeSet>
        <ParameterSet>
          <Parameter name="temp" parameterTypeRef="TempType"/>
        </ParameterSet>
      </TelemetryMetaData>
    </SpaceSystem>
    """
  end

  defp declaration?(declarations, kind, qualified_name) do
    Enum.any?(declarations, fn declaration ->
      declaration.kind == kind and declaration.qualified_name == qualified_name
    end)
  end

  defp diagnostic?(plan, code), do: Enum.any?(plan.diagnostics, &(&1.code == code))

  defp source(xml) do
    Source.new(%{
      artifact_id: "artifact-xtce",
      organization_id: "org-xtce",
      mission_id: "mission-xtce",
      catalog_family: :combined,
      artifact_name: "vehicle.xml",
      format_key: "xtce_1_3",
      format_version: "1.3",
      media_type: "application/xtce+xml",
      source_artifact: xml
    })
  end

  defp xtce_document do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="Vehicle">
      <TelemetryMetaData>
        <ParameterTypeSet>
          <IntegerParameterType name="TemperatureType">
            <UnitSet><Unit>degC</Unit></UnitSet>
            <IntegerDataEncoding sizeInBits="16" encoding="unsigned"/>
            <DefaultAlarm minViolations="2">
              <StaticAlarmRanges>
                <WarningRange maxInclusive="80"/>
                <CriticalRange maxInclusive="100"/>
              </StaticAlarmRanges>
              <ChangeAlarmRanges>
                <WarningRange maxInclusive="5"/>
              </ChangeAlarmRanges>
            </DefaultAlarm>
          </IntegerParameterType>
        </ParameterTypeSet>
        <ParameterSet>
          <Parameter name="temperature" parameterTypeRef="TemperatureType"/>
          <Parameter name="double_temperature" parameterTypeRef="TemperatureType"/>
        </ParameterSet>
        <ContainerSet>
          <SequenceContainer name="HK">
            <EntryList>
              <ParameterRefEntry parameterRef="temperature">
                <LocationInContainerInBits referenceLocation="containerStart">
                  <FixedValue>0</FixedValue>
                </LocationInContainerInBits>
              </ParameterRefEntry>
            </EntryList>
          </SequenceContainer>
        </ContainerSet>
        <AlgorithmSet>
          <CustomAlgorithm name="DoubleTemperature">
            <AlgorithmText language="python">return temperature * 2</AlgorithmText>
            <InputSet>
              <InputParameterInstanceRef parameterRef="temperature"/>
            </InputSet>
            <OutputSet>
              <OutputParameterRef parameterRef="double_temperature"/>
            </OutputSet>
          </CustomAlgorithm>
        </AlgorithmSet>
      </TelemetryMetaData>
      <CommandMetaData>
        <ArgumentTypeSet>
          <IntegerArgumentType name="UInt16">
            <IntegerDataEncoding sizeInBits="16" encoding="unsigned"/>
          </IntegerArgumentType>
        </ArgumentTypeSet>
        <MetaCommandSet>
          <MetaCommand name="SET_MODE">
            <ArgumentList>
              <Argument name="mode" argumentTypeRef="UInt16"/>
            </ArgumentList>
            <TransmissionConstraintList>
              <TransmissionConstraint timeOut="PT2S">
                <Comparison parameterRef="temperature" comparisonOperator="&lt;" value="90"/>
              </TransmissionConstraint>
            </TransmissionConstraintList>
            <VerifierSet>
              <CompleteVerifier>
                <Comparison parameterRef="temperature" comparisonOperator="&lt;" value="95"/>
                <CheckWindow timeToStopChecking="PT5S"/>
              </CompleteVerifier>
            </VerifierSet>
          </MetaCommand>
        </MetaCommandSet>
      </CommandMetaData>
      <SpaceSystem name="POBC">
        <TelemetryMetaData/>
      </SpaceSystem>
    </SpaceSystem>
    """
  end
end

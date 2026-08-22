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
                <WarningRange minInclusive="80" maxInclusive="100"/>
                <CriticalRange minInclusive="100"/>
              </StaticAlarmRanges>
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

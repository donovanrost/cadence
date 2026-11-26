defmodule Cadence.Catalog.MissionModelMountFixtures do
  @moduledoc "Two small imports for #444's mount tests: a YAML bus database and an XTCE payload."

  alias Cadence.Catalog.Importers.{CadenceYamlDatabase, Xtce13}
  alias Cadence.Catalog.Source

  @doc "The YAML database imported as `artifact_name`: packet HK, parameters temperature_c and mode, command SET_MODE."
  def yaml_layer(artifact_name \\ "bus.yaml") do
    source =
      Source.new(%{
        artifact_id: "artifact-" <> artifact_name,
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: artifact_name,
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml_database()
      })

    {:ok, result} =
      CadenceYamlDatabase.import(source, %{import_run_id: "import-" <> artifact_name})

    [layer] = result.bundle.declaration_layers
    layer
  end

  @doc "The XTCE document with root SpaceSystem `root`: packet PAYLOAD_HK and algorithm DoubleTemperature."
  def xtce_layer(root \\ "Vehicle") do
    source =
      Source.new(%{
        artifact_id: "artifact-xtce-" <> root,
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: root <> ".xml",
        format_key: "xtce_1_3",
        format_version: "1.3",
        media_type: "application/xtce+xml",
        source_artifact: xtce_document(root)
      })

    {:ok, result} = Xtce13.import(source, %{import_run_id: "import-xtce-" <> root})
    [layer] = result.bundle.declaration_layers
    layer
  end

  defp yaml_database do
    """
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
  end

  defp xtce_document(root) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <SpaceSystem xmlns="http://www.omg.org/spec/XTCE/20250214" name="#{root}">
      <TelemetryMetaData>
        <ParameterTypeSet>
          <IntegerParameterType name="TemperatureType">
            <UnitSet><Unit>degC</Unit></UnitSet>
            <IntegerDataEncoding sizeInBits="16" encoding="unsigned"/>
          </IntegerParameterType>
        </ParameterTypeSet>
        <ParameterSet>
          <Parameter name="temperature" parameterTypeRef="TemperatureType"/>
          <Parameter name="double_temperature" parameterTypeRef="TemperatureType"/>
        </ParameterSet>
        <ContainerSet>
          <SequenceContainer name="PAYLOAD_HK">
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
      <SpaceSystem name="POBC">
        <TelemetryMetaData/>
      </SpaceSystem>
    </SpaceSystem>
    """
  end
end

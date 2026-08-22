defmodule XTCETest do
  use ExUnit.Case, async: true

  alias XTCE.{Document, Element}

  test "parses an XTCE 1.3 document into a queryable tree" do
    assert {:ok, %Document{} = document} = XTCE.parse(valid_document())
    assert document.version == "1.3"
    assert document.namespace == XTCE.namespace()
    assert Element.attr(document.root, "name") == "Vehicle"

    assert [parameter] = Element.descendants(document.root, "Parameter")
    assert Element.attr(parameter, "name") == "temperature"
    assert Element.attr(parameter, "parameterTypeRef") == "TemperatureType"
  end

  test "validates against the pinned normative schema" do
    assert :ok = XTCE.validate(valid_document())

    invalid = ~s(<SpaceSystem xmlns="#{XTCE.namespace()}"><TelemetryMetaData/></SpaceSystem>)

    assert {:error, {:invalid_xtce_schema, diagnostic}} = XTCE.validate(invalid)
    assert diagnostic =~ "attribute 'name' is required"
  end

  test "optionally validates while parsing" do
    assert {:ok, %Document{}} = XTCE.parse(valid_document(), validate_schema: true)
  end

  test "isolates concurrent schema validations" do
    results =
      1..16
      |> Task.async_stream(fn _index -> XTCE.validate(valid_document()) end,
        max_concurrency: 8,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, :ok}))
  end

  test "rejects unsupported XTCE namespaces" do
    xml = ~s(<SpaceSystem xmlns="urn:example:xtce" name="Vehicle"/>)

    assert {:error, {:unsupported_xtce_namespace, "urn:example:xtce"}} = XTCE.parse(xml)
  end

  test "rejects non-SpaceSystem roots" do
    xml = ~s(<TelemetryMetaData xmlns="#{XTCE.namespace()}"/>)

    assert {:error, :xtce_space_system_root_required} = XTCE.parse(xml)
  end

  test "rejects document type and entity declarations before parsing" do
    xml = """
    <!DOCTYPE SpaceSystem [<!ENTITY secret SYSTEM "file:///etc/passwd">]>
    <SpaceSystem xmlns="#{XTCE.namespace()}" name="Vehicle">
      <LongDescription>&secret;</LongDescription>
    </SpaceSystem>
    """

    assert {:error, :xtce_document_type_forbidden} = XTCE.parse(xml)
  end

  test "enforces explicit parser resource limits" do
    assert {:error, :xtce_artifact_too_large} = XTCE.parse(valid_document(), max_bytes: 10)
    assert {:error, :xtce_maximum_depth_exceeded} = XTCE.parse(valid_document(), max_depth: 2)

    assert {:error, :xtce_maximum_node_count_exceeded} =
             XTCE.parse(valid_document(), max_nodes: 2)
  end

  test "parses and validates files" do
    path = Path.join(System.tmp_dir!(), "xtce_test_#{System.unique_integer([:positive])}.xml")

    try do
      File.write!(path, valid_document())
      assert {:ok, %Document{}} = XTCE.parse_file(path)
      assert :ok = XTCE.validate_file(path)
    after
      File.rm(path)
    end
  end

  test "reports file read failures without raising" do
    assert {:error, {:xtce_file_read_failed, :enoent}} =
             XTCE.parse_file("/path/that/does/not/exist.xtce")
  end

  defp valid_document do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <SpaceSystem xmlns="#{XTCE.namespace()}" name="Vehicle">
      <TelemetryMetaData>
        <ParameterTypeSet>
          <IntegerParameterType name="TemperatureType">
            <IntegerDataEncoding sizeInBits="16" encoding="unsigned"/>
          </IntegerParameterType>
        </ParameterTypeSet>
        <ParameterSet>
          <Parameter name="temperature" parameterTypeRef="TemperatureType"/>
        </ParameterSet>
      </TelemetryMetaData>
    </SpaceSystem>
    """
  end
end

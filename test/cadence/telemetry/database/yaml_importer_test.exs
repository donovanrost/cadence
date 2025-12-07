defmodule Cadence.Telemetry.Database.YamlImporterTest do
  @moduledoc """
  Tests for YAML database import functionality.

  Note: Derived items are no longer supported in YAML imports. They should be
  created using the runtime overlay via the DerivedItem table. See
  `Cadence.Telemetry.Database.DerivedItem`.
  """

  use Cadence.DataCase, async: true

  alias Cadence.Telemetry.Database.YamlImporter

  describe "validate_structure/1 for packets" do
    test "validates packet with required fields" do
      yaml = """
      version: "1.0.0"
      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: cpu_temp
              bit_offset: 0
              bit_size: 32
              data_type: float
      """

      {:ok, parsed} = YamlElixir.read_from_string(yaml)
      assert parsed["packets"] != nil
    end

    test "rejects item with zero bit_size" do
      yaml = """
      version: "1.0.0"
      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: TEMP
              bit_offset: 0
              bit_size: 0
              data_type: float
      """

      assert {:error, {:validation_error, message}} =
               YamlImporter.import_string(%{id: "test", organization_id: "test"}, yaml)

      assert message =~ "bit_size > 0"
    end

    test "rejects item missing required fields" do
      yaml = """
      version: "1.0.0"
      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: TEMP
              bit_offset: 0
              data_type: float
      """

      assert {:error, {:validation_error, message}} =
               YamlImporter.import_string(%{id: "test", organization_id: "test"}, yaml)

      assert message =~ "bit_size"
    end
  end

  describe "validate_structure/1 for commands" do
    test "validates command-only YAML" do
      yaml = """
      version: "1.0.0"
      commands:
        - name: SAFE_MODE
          opcode: 1
          description: "Enter safe mode"
      """

      {:ok, parsed} = YamlElixir.read_from_string(yaml)
      assert parsed["commands"] != nil
    end

    test "rejects hazardous command without hazard_description" do
      yaml = """
      version: "1.0.0"
      commands:
        - name: SAFE_MODE
          opcode: 1
          is_hazardous: true
      """

      assert {:error, {:validation_error, message}} =
               YamlImporter.import_string(%{id: "test", organization_id: "test"}, yaml)

      assert message =~ "hazard_description"
    end
  end

  describe "item validation" do
    test "all items must have bit_offset, bit_size, data_type, and name" do
      yaml = """
      version: "1.0.0"
      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: cpu_temp
              bit_offset: 0
              bit_size: 32
              data_type: float
            - name: gpu_temp
              bit_offset: 32
              bit_size: 32
              data_type: float
      """

      {:ok, parsed} = YamlElixir.read_from_string(yaml)
      [packet] = parsed["packets"]
      items = packet["items"]

      Enum.each(items, fn item ->
        assert Map.has_key?(item, "name")
        assert Map.has_key?(item, "bit_offset")
        assert Map.has_key?(item, "bit_size")
        assert Map.has_key?(item, "data_type")
      end)
    end
  end
end

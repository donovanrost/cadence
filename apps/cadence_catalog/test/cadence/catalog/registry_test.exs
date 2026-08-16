defmodule Cadence.Catalog.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.{ImporterDescriptor, Registry}

  test "publishes an exact validated first-party built-in definition" do
    importers = Registry.list_builtin_importers()
    assert Enum.map(importers, & &1.descriptor.importer_key) == ["cadence_yaml", "xtce_1_3"]

    assert %{descriptor: descriptor} =
             Enum.find(importers, &(&1.descriptor.importer_key == "cadence_yaml"))

    assert descriptor.importer_key == "cadence_yaml"
    assert descriptor.version == 2
    assert descriptor.trust == :first_party
    assert :ok = ImporterDescriptor.validate(descriptor)

    assert {:ok, %{descriptor: ^descriptor}} =
             Registry.fetch_builtin_importer("cadence_yaml", 2)

    assert {:error, :catalog_importer_version_not_found} =
             Registry.fetch_builtin_importer("cadence_yaml", 1)

    assert {:error, :catalog_importer_not_found} =
             Registry.fetch_builtin_importer("unknown")

    assert {:ok, %{descriptor: xtce_descriptor}} =
             Registry.fetch_builtin_importer("xtce_1_3", 1)

    assert xtce_descriptor.trust == :first_party
    assert :ok = ImporterDescriptor.validate(xtce_descriptor)
  end

  test "rejects malformed descriptors" do
    assert {:error, :invalid_catalog_importer_descriptor} =
             ImporterDescriptor.validate(%ImporterDescriptor{
               importer_key: "cadence.invalid",
               version: 0,
               trust: :first_party,
               display_name: "Invalid",
               catalog_family: :combined,
               source_formats: ["invalid"],
               media_types: ["application/octet-stream"]
             })
  end

  describe "detect_importer/2" do
    test "matches by media type" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", "application/yaml")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "matches when media type is a known text/yaml synonym" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", "text/yaml")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "falls back to filename extension when media type is generic" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yml", "application/octet-stream")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "falls back to filename extension when media type is missing" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", nil)

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "detects XTCE XML" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.xml", "application/xml")

      assert descriptor.importer_key == "xtce_1_3"
    end

    test "returns :no_matching_importer when both filename and media type are unknown" do
      assert {:error, :no_matching_importer} =
               Registry.detect_importer("mission.bin", "application/octet-stream")
    end
  end
end

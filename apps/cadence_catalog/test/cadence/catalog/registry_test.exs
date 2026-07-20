defmodule Cadence.Catalog.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Registry

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

    test "returns :no_matching_importer for unknown files" do
      assert {:error, :no_matching_importer} =
               Registry.detect_importer("mission.xml", "application/xml")
    end

    test "returns :no_matching_importer when both filename and media type are unknown" do
      assert {:error, :no_matching_importer} =
               Registry.detect_importer("mission.bin", "application/octet-stream")
    end
  end
end

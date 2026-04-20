defmodule Cadence.Catalog.ArtifactTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.ImporterDescriptor

  describe "build_from_upload/4" do
    test "builds an Artifact from raw bytes + descriptor + filename + uploader" do
      descriptor =
        ImporterDescriptor.new(%{
          importer_key: "cadence_yaml",
          display_name: "Cadence YAML Database",
          catalog_family: :combined,
          source_formats: ["cadence_yaml"],
          media_types: ["application/yaml"]
        })

      bytes = "packets: []\ncommands: []\n"

      artifact =
        Artifact.build_from_upload(
          "mission_abc",
          descriptor,
          %{filename: "mission.yaml", bytes: bytes, client_type: "application/yaml"},
          uploaded_by: %{user_id: "user_1", email: "a@example.com"}
        )

      assert %Artifact{} = artifact
      assert artifact.mission_id == "mission_abc"
      assert artifact.artifact_name == "mission.yaml"
      assert artifact.format_key == "cadence_yaml"
      assert artifact.catalog_family == :combined
      assert artifact.media_type == "application/yaml"
      assert artifact.source_artifact == bytes
      assert artifact.uploaded_by == %{user_id: "user_1", email: "a@example.com"}
      assert is_binary(artifact.content_sha256)
    end

    test "uses the descriptor's first media type when the upload has no client_type" do
      descriptor =
        ImporterDescriptor.new(%{
          importer_key: "cadence_yaml",
          display_name: "Cadence YAML Database",
          catalog_family: :combined,
          source_formats: ["cadence_yaml"],
          media_types: ["application/yaml", "text/yaml"]
        })

      artifact =
        Artifact.build_from_upload(
          "mission_abc",
          descriptor,
          %{filename: "mission.yaml", bytes: "anything"}
        )

      assert artifact.media_type == "application/yaml"
    end

    test "prefers the client-supplied type when present" do
      descriptor =
        ImporterDescriptor.new(%{
          importer_key: "cadence_yaml",
          display_name: "Cadence YAML Database",
          catalog_family: :combined,
          source_formats: ["cadence_yaml"],
          media_types: ["application/yaml", "text/yaml"]
        })

      artifact =
        Artifact.build_from_upload(
          "mission_abc",
          descriptor,
          %{filename: "mission.yaml", bytes: "anything", client_type: "text/yaml"}
        )

      assert artifact.media_type == "text/yaml"
    end
  end

  describe "download_payload/1" do
    test "returns {bytes, media_type} for a raw binary source artifact" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: "payload-bytes"
        })

      assert {"payload-bytes", "application/yaml"} = Artifact.download_payload(artifact)
    end

    test "unwraps a %{\"yaml\" => bytes} source artifact" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: %{"yaml" => "inner-bytes"}
        })

      assert {"inner-bytes", "application/yaml"} = Artifact.download_payload(artifact)
    end

    test "falls back to application/octet-stream when media_type is nil for raw bytes" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.bin",
          format_key: "cadence_yaml",
          source_artifact: "raw"
        })

      assert {"raw", "application/octet-stream"} = Artifact.download_payload(artifact)
    end
  end
end

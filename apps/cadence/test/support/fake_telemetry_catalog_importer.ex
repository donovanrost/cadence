defmodule Cadence.TestSupport.FakeTelemetryCatalogImporter do
  @moduledoc false

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Diagnostic, ImporterDescriptor, ImportResult}
  alias Cadence.Catalog.Telemetry.{Packet, Snapshot}

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "fake_tm_json",
      display_name: "Fake TM JSON",
      catalog_family: :telemetry,
      source_formats: ["fake_tm_json"],
      media_types: ["application/json"],
      description: "Test-only importer for catalog substrate coverage"
    })
  end

  @impl true
  def validate_artifact(%Artifact{source_artifact: %{"packets" => packets}})
      when is_list(packets),
      do: :ok

  def validate_artifact(_artifact), do: {:error, :invalid_fake_tm_json}

  @impl true
  def import(%Artifact{} = artifact, %{import_run_id: import_run_id}) do
    packets = artifact.source_artifact["packets"]
    packet_names = Enum.map(packets, &Map.get(&1, "name"))

    snapshot =
      Snapshot.new(%{
        snapshot_id: "telemetry_snapshot:" <> import_run_id,
        organization_id: artifact.organization_id,
        mission_id: artifact.mission_id,
        artifact_id: artifact.artifact_id,
        import_run_id: import_run_id,
        importer_key: descriptor().importer_key,
        snapshot_name: artifact.artifact_name,
        packets:
          Enum.with_index(packet_names)
          |> Enum.map(fn {packet_name, index} ->
            Packet.new(%{
              packet_id: "telemetry_snapshot:#{import_run_id}:packet:#{index}",
              snapshot_id: "telemetry_snapshot:" <> import_run_id,
              name: packet_name
            })
          end)
      })

    with {:ok, persisted_snapshot} <-
           Catalog.persist_telemetry_snapshot(artifact.organization_id, snapshot) do
      {:ok,
       ImportResult.new(%{
         snapshot_id: persisted_snapshot.snapshot_id,
         imported_definition_count: length(packets),
         diagnostics: [
           Diagnostic.new(%{
             severity: :warning,
             code: "fake_tm_json.warning",
             message: "Importer preserved format-specific extensions",
             path: ["packets"],
             metadata: %{"packet_names" => packet_names}
           })
         ],
         result_document: %{
           "import_run_id" => import_run_id,
           "packet_names" => packet_names,
           "snapshot" => %{
             "snapshot_id" => persisted_snapshot.snapshot_id,
             "snapshot_name" => persisted_snapshot.snapshot_name,
             "packet_count" => length(persisted_snapshot.packets),
             "point_count" => 0,
             "type_count" => 0,
             "unit_count" => 0,
             "calibration_algorithm_count" => 0
           }
         }
       })}
    end
  end
end

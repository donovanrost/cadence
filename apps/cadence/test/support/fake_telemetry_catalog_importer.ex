defmodule Cadence.TestSupport.FakeTelemetryCatalogImporter do
  @moduledoc false

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog.{Diagnostic, ImporterDescriptor, ImportResult, Source}
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
  def validate(%Source{source_artifact: %{"packets" => packets}})
      when is_list(packets),
      do: :ok

  def validate(_source), do: {:error, :invalid_fake_tm_json}

  @impl true
  def import(%Source{} = source, %{import_run_id: import_run_id}) do
    packets = source.source_artifact["packets"]
    packet_names = Enum.map(packets, &Map.get(&1, "name"))

    snapshot =
      Snapshot.new(%{
        snapshot_id: "telemetry_snapshot:" <> import_run_id,
        organization_id: source.organization_id,
        mission_id: source.mission_id,
        artifact_id: source.artifact_id,
        import_run_id: import_run_id,
        importer_key: descriptor().importer_key,
        snapshot_name: source.artifact_name,
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

    {:ok,
     ImportResult.new(%{
       telemetry_snapshot: snapshot,
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
       metadata: %{"packet_names" => packet_names}
     })}
  end
end

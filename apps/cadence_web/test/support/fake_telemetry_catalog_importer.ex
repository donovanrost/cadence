defmodule CadenceWeb.TestSupport.FakeTelemetryCatalogImporter do
  @moduledoc false

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog.{Diagnostic, ImporterDescriptor, ImportResult, Source}
  alias Cadence.Catalog.MissionModel.Layer

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "fake_tm_json",
      display_name: "Fake TM JSON",
      catalog_family: :telemetry,
      source_formats: ["fake_tm_json"],
      media_types: ["application/json"],
      description: "Test-only importer for API coverage"
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

    layer =
      Layer.new(%{
        organization_id: source.organization_id,
        mission_id: source.mission_id,
        name: source.artifact_name,
        source: %{"artifact_id" => source.artifact_id, "import_run_id" => import_run_id},
        declarations:
          [%{kind: :space_system, qualified_name: "/"}] ++
            Enum.map(Enum.with_index(packet_names), fn {packet_name, index} ->
              %{
                kind: :container,
                qualified_name: "/packets/#{packet_name}",
                definition: %{apid: index, entries: []}
              }
            end)
      })

    {:ok,
     ImportResult.new(%{
       declaration_layers: [layer],
       imported_definition_count: length(packets),
       diagnostics: [
         Diagnostic.new(%{
           severity: :warning,
           code: "fake_tm_json.warning",
           message: "Importer preserved format-specific extensions",
           path: ["packets"]
         })
       ],
       metadata: %{"packet_names" => packet_names}
     })}
  end
end

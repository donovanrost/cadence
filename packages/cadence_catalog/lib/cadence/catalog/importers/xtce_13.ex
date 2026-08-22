defmodule Cadence.Catalog.Importers.Xtce13 do
  @moduledoc """
  First-party XTCE 1.3 importer.

  The standalone `xtce` package parses and validates the source document before
  this Cadence adapter translates it into an immutable Mission Model declaration
  layer. Unsupported source constructs are retained in declaration extensions
  and diagnosed instead of executed.
  """

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog.{ImporterDescriptor, ImportResult, Source}
  alias Cadence.Catalog.Importers.Xtce13.Translator

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "xtce_1_3",
      version: 1,
      trust: :first_party,
      display_name: "XTCE 1.3",
      catalog_family: :combined,
      source_formats: ["xtce", "xtce_1_3"],
      media_types: ["application/xtce+xml", "application/xml", "text/xml"],
      description: "XTCE 1.3 telemetry, algorithm, monitoring, and command importer"
    })
  end

  @impl true
  def validate(%Source{source_artifact: xml}) when is_binary(xml) do
    XTCE.validate(xml)
  end

  def validate(%Source{}), do: {:error, :xtce_source_must_be_xml}

  @impl true
  def import(%Source{source_artifact: xml} = source, %{import_run_id: import_run_id})
      when is_binary(xml) and is_binary(import_run_id) do
    with {:ok, document} <- XTCE.parse(xml, validate_schema: true),
         {:ok, layer, diagnostics} <-
           Translator.translate(document.root, source, import_run_id) do
      {:ok,
       ImportResult.new(%{
         declaration_layers: [layer],
         imported_definition_count: length(layer.declarations),
         diagnostics: diagnostics,
         metadata: %{
           "import_run_id" => import_run_id,
           "xtce_namespace" => document.namespace,
           "xtce_importer_version" => descriptor().version,
           "xtce_schema_sha256" => XTCE.schema_sha256()
         }
       })}
    end
  end

  def import(%Source{}, _context), do: {:error, :xtce_import_run_id_required}
end

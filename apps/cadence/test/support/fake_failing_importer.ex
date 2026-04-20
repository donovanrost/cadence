defmodule Cadence.TestSupport.FakeFailingImporter do
  @moduledoc false

  @behaviour Cadence.Catalog.Importer

  alias Cadence.Catalog.{Artifact, ImporterDescriptor}

  @impl true
  def descriptor do
    ImporterDescriptor.new(%{
      importer_key: "fake_failing",
      display_name: "Fake Failing Importer",
      catalog_family: :telemetry,
      source_formats: ["fake_failing"],
      media_types: ["application/json"],
      description: "Test-only importer that always fails during import/2"
    })
  end

  @impl true
  def validate_artifact(%Artifact{}), do: :ok

  @impl true
  def import(%Artifact{}, _context) do
    {:error, :simulated_failure}
  end
end

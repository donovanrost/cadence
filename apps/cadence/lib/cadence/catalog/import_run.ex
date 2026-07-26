defmodule Cadence.Catalog.ImportRun do
  @moduledoc """
  One durable execution of a catalog importer against a preserved artifact.
  """

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Diagnostic
  alias Cadence.Ids

  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
          import_run_id: binary(),
          snapshot_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_database_id: binary() | nil,
          artifact_id: binary(),
          catalog_family: Artifact.catalog_family(),
          importer_key: binary(),
          importer_version: pos_integer(),
          status: status(),
          imported_definition_count: non_neg_integer(),
          diagnostics: [Diagnostic.t()],
          result_document: map(),
          failure_reason: term() | nil,
          requested_by: map(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :import_run_id,
    :snapshot_id,
    :organization_id,
    :mission_id,
    :catalog_database_id,
    :artifact_id,
    :catalog_family,
    :importer_key,
    :importer_version,
    :status,
    :imported_definition_count,
    :diagnostics,
    :result_document,
    :failure_reason,
    :requested_by,
    :started_at,
    :completed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      import_run_id: Map.get(attrs, :import_run_id, Ids.new("catalog_import_run")),
      snapshot_id: Map.get(attrs, :snapshot_id, Map.get(attrs, "snapshot_id")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      catalog_database_id:
        Map.get(attrs, :catalog_database_id, Map.get(attrs, "catalog_database_id")),
      artifact_id: Map.fetch!(attrs, :artifact_id),
      catalog_family: Map.fetch!(attrs, :catalog_family),
      importer_key: Map.fetch!(attrs, :importer_key),
      importer_version: Map.get(attrs, :importer_version, 1),
      status: Map.get(attrs, :status, :running),
      imported_definition_count: Map.get(attrs, :imported_definition_count, 0),
      diagnostics: Map.get(attrs, :diagnostics, []),
      result_document: Map.get(attrs, :result_document, %{}),
      failure_reason: Map.get(attrs, :failure_reason),
      requested_by: Map.get(attrs, :requested_by, %{}),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end

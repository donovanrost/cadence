defmodule Cadence.Catalog.Revision do
  @moduledoc """
  Immutable imported version of a catalog database.
  """

  alias Cadence.Catalog.Artifact
  alias Cadence.Ids

  @type t :: %__MODULE__{
          catalog_revision_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_database_id: binary(),
          revision_number: pos_integer(),
          revision_label: binary(),
          catalog_family: Artifact.catalog_family(),
          artifact_id: binary(),
          import_run_id: binary(),
          telemetry_snapshot_id: binary() | nil,
          command_snapshot_id: binary() | nil,
          content_sha256: binary(),
          created_by: map(),
          notes: binary() | nil,
          metadata: map()
        }

  defstruct [
    :catalog_revision_id,
    :organization_id,
    :mission_id,
    :catalog_database_id,
    :revision_number,
    :revision_label,
    :catalog_family,
    :artifact_id,
    :import_run_id,
    :telemetry_snapshot_id,
    :command_snapshot_id,
    :content_sha256,
    :notes,
    created_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      catalog_revision_id: get(attrs, :catalog_revision_id) || Ids.new("catalog_revision"),
      organization_id: get(attrs, :organization_id),
      mission_id: fetch!(attrs, :mission_id),
      catalog_database_id: fetch!(attrs, :catalog_database_id),
      revision_number: fetch!(attrs, :revision_number),
      revision_label: fetch!(attrs, :revision_label),
      catalog_family: fetch!(attrs, :catalog_family),
      artifact_id: fetch!(attrs, :artifact_id),
      import_run_id: fetch!(attrs, :import_run_id),
      telemetry_snapshot_id: get(attrs, :telemetry_snapshot_id),
      command_snapshot_id: get(attrs, :command_snapshot_id),
      content_sha256: fetch!(attrs, :content_sha256),
      created_by: get(attrs, :created_by, %{}),
      notes: get(attrs, :notes),
      metadata: get(attrs, :metadata, %{})
    }
  end

  defp fetch!(attrs, key) do
    Map.fetch!(attrs, key)
  rescue
    KeyError ->
      Map.fetch!(attrs, Atom.to_string(key))
  end

  defp get(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end

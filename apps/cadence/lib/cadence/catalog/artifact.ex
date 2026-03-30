defmodule Cadence.Catalog.Artifact do
  @moduledoc """
  Preserved source artifact for one catalog import input.
  """

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type catalog_family :: :telemetry | :command | :combined

  @type t :: %__MODULE__{
          artifact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_family: catalog_family(),
          artifact_name: binary(),
          format_key: binary(),
          format_version: binary() | nil,
          media_type: binary() | nil,
          source_artifact: term(),
          content_sha256: binary(),
          uploaded_by: map(),
          uploaded_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :artifact_id,
    :organization_id,
    :mission_id,
    :catalog_family,
    :artifact_name,
    :format_key,
    :format_version,
    :media_type,
    :source_artifact,
    :content_sha256,
    :uploaded_at,
    uploaded_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    source_artifact = Map.fetch!(attrs, :source_artifact)

    %__MODULE__{
      artifact_id: Map.get(attrs, :artifact_id, Ids.new("catalog_artifact")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      catalog_family: Map.fetch!(attrs, :catalog_family),
      artifact_name: Map.fetch!(attrs, :artifact_name),
      format_key: Map.fetch!(attrs, :format_key),
      format_version: Map.get(attrs, :format_version),
      media_type: Map.get(attrs, :media_type),
      source_artifact: source_artifact,
      content_sha256: Map.get(attrs, :content_sha256, content_sha256(source_artifact)),
      uploaded_by: Map.get(attrs, :uploaded_by, %{}),
      uploaded_at: Map.get(attrs, :uploaded_at, DateTime.utc_now()),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp content_sha256(source_artifact) do
    source_artifact
    |> JsonDocument.encode()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

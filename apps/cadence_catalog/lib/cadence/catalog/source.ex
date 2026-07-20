defmodule Cadence.Catalog.Source do
  @moduledoc """
  Persistence-independent source input supplied to catalog importers.

  Consuming applications translate their stored artifacts, uploads, or remote
  objects into this value before invoking an importer.
  """

  @type t :: %__MODULE__{
          artifact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_family: :telemetry | :command | :combined,
          artifact_name: binary(),
          format_key: binary(),
          format_version: binary() | nil,
          media_type: binary() | nil,
          source_artifact: term(),
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
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      artifact_id: fetch!(attrs, :artifact_id),
      organization_id: get(attrs, :organization_id),
      mission_id: fetch!(attrs, :mission_id),
      catalog_family: fetch!(attrs, :catalog_family),
      artifact_name: fetch!(attrs, :artifact_name),
      format_key: fetch!(attrs, :format_key),
      format_version: get(attrs, :format_version),
      media_type: get(attrs, :media_type),
      source_artifact: fetch!(attrs, :source_artifact),
      metadata: get(attrs, :metadata, %{})
    }
  end

  defp fetch!(attrs, key) do
    Map.fetch!(attrs, key)
  rescue
    KeyError -> Map.fetch!(attrs, Atom.to_string(key))
  end

  defp get(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end

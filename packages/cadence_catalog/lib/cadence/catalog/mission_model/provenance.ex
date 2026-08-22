defmodule Cadence.Catalog.MissionModel.Provenance do
  @moduledoc "Source and transformation evidence attached to a semantic declaration."

  @type t :: %__MODULE__{
          artifact_id: binary() | nil,
          importer_key: binary() | nil,
          importer_version: binary() | nil,
          source_path: [binary()],
          source_location: map() | nil,
          transformations: [map()],
          metadata: map()
        }

  defstruct [
    :artifact_id,
    :importer_key,
    :importer_version,
    :source_location,
    source_path: [],
    transformations: [],
    metadata: %{}
  ]

  @spec new(map() | nil) :: t() | nil
  def new(nil), do: nil

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      artifact_id: value(attrs, :artifact_id),
      importer_key: value(attrs, :importer_key),
      importer_version: value(attrs, :importer_version),
      source_path: value(attrs, :source_path, []),
      source_location: value(attrs, :source_location),
      transformations: value(attrs, :transformations, []),
      metadata: value(attrs, :metadata, %{})
    }
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end

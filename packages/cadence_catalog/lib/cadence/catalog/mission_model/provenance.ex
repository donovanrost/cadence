defmodule Cadence.Catalog.MissionModel.Provenance do
  @moduledoc "Source and transformation evidence attached to a semantic declaration."

  alias Cadence.Catalog.MissionModel.Canonical

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

  @doc """
  The versioned hash basis (#166). Only what describes the content: `artifact_id` and `metadata`
  (the import run) are per-import facts and stay out (#119), so identical content imported again
  hashes the same. `nil` provenance hashes as `nil`.
  """
  @spec hash_basis(t() | nil) :: Canonical.basis() | nil
  def hash_basis(nil), do: nil

  def hash_basis(%__MODULE__{} = provenance) do
    {:mission_model_provenance, 1,
     %{
       importer_key: provenance.importer_key,
       importer_version: provenance.importer_version,
       source_path: provenance.source_path,
       source_location: provenance.source_location,
       transformations: provenance.transformations
     }}
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end

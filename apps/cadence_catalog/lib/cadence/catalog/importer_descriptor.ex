defmodule Cadence.Catalog.ImporterDescriptor do
  @moduledoc """
  Published description for one registered catalog importer.
  """

  alias Cadence.Catalog.Artifact

  @type t :: %__MODULE__{
          importer_key: binary(),
          display_name: binary(),
          catalog_family: Artifact.catalog_family(),
          source_formats: [binary()],
          media_types: [binary()],
          description: binary() | nil
        }

  defstruct [
    :importer_key,
    :display_name,
    :catalog_family,
    source_formats: [],
    media_types: [],
    description: nil
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      importer_key: Map.fetch!(attrs, :importer_key),
      display_name: Map.fetch!(attrs, :display_name),
      catalog_family: Map.fetch!(attrs, :catalog_family),
      source_formats: Map.get(attrs, :source_formats, []),
      media_types: Map.get(attrs, :media_types, []),
      description: Map.get(attrs, :description)
    }
  end
end

defmodule Cadence.Catalog.Database do
  @moduledoc """
  Mission-scoped logical catalog library entry.
  """

  alias Cadence.Catalog.Artifact
  alias Cadence.Ids

  @type t :: %__MODULE__{
          catalog_database_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          name: binary(),
          slug: binary(),
          description: binary() | nil,
          catalog_family: Artifact.catalog_family(),
          default_importer_key: binary() | nil,
          created_by: map(),
          metadata: map()
        }

  defstruct [
    :catalog_database_id,
    :organization_id,
    :mission_id,
    :name,
    :slug,
    :description,
    :catalog_family,
    :default_importer_key,
    created_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    name = fetch!(attrs, :name)

    %__MODULE__{
      catalog_database_id: get(attrs, :catalog_database_id) || Ids.new("catalog_database"),
      organization_id: get(attrs, :organization_id),
      mission_id: fetch!(attrs, :mission_id),
      name: name,
      slug: get(attrs, :slug) || slugify(name),
      description: get(attrs, :description),
      catalog_family: fetch!(attrs, :catalog_family),
      default_importer_key: get(attrs, :default_importer_key),
      created_by: get(attrs, :created_by, %{}),
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

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> Ids.new("catalog")
      slug -> slug
    end
  end
end

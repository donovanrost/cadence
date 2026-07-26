defmodule Cadence.Catalog.ImporterDescriptor do
  @moduledoc """
  Published description for one registered catalog importer.
  """

  alias Cadence.Catalog.Artifact

  @type t :: %__MODULE__{
          importer_key: binary(),
          version: pos_integer(),
          trust: :first_party | :configured,
          display_name: binary(),
          catalog_family: Artifact.catalog_family(),
          source_formats: [binary()],
          media_types: [binary()],
          description: binary() | nil
        }

  defstruct [
    :importer_key,
    :version,
    :trust,
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
      version: Map.get(attrs, :version, 1),
      trust: Map.get(attrs, :trust, :configured),
      display_name: Map.fetch!(attrs, :display_name),
      catalog_family: Map.fetch!(attrs, :catalog_family),
      source_formats: Map.get(attrs, :source_formats, []),
      media_types: Map.get(attrs, :media_types, []),
      description: Map.get(attrs, :description)
    }
  end

  @spec validate(t()) :: :ok | {:error, :invalid_catalog_importer_descriptor}
  def validate(%__MODULE__{} = descriptor) do
    with true <- valid_text?(descriptor.importer_key),
         true <- is_integer(descriptor.version) and descriptor.version > 0,
         true <- descriptor.trust in [:first_party, :configured],
         true <- valid_text?(descriptor.display_name),
         true <- descriptor.catalog_family in [:telemetry, :command, :combined],
         true <- valid_text_list?(descriptor.source_formats),
         true <- valid_text_list?(descriptor.media_types),
         true <- is_nil(descriptor.description) or valid_text?(descriptor.description) do
      :ok
    else
      _invalid -> {:error, :invalid_catalog_importer_descriptor}
    end
  end

  def validate(_descriptor), do: {:error, :invalid_catalog_importer_descriptor}

  defp valid_text_list?(values) when is_list(values) and values != [],
    do: Enum.all?(values, &valid_text?/1) and length(Enum.uniq(values)) == length(values)

  defp valid_text_list?(_values), do: false
  defp valid_text?(value), do: is_binary(value) and value != ""
end

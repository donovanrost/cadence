defmodule Cadence.Catalog.Registry do
  @moduledoc """
  Registry of configured first-party catalog importers.
  """

  alias Cadence.Catalog.ImporterDescriptor

  @type importer_registration :: %{module: module(), descriptor: ImporterDescriptor.t()}

  @extension_by_media_type %{
    "application/yaml" => [".yaml", ".yml"],
    "application/x-yaml" => [".yaml", ".yml"],
    "text/yaml" => [".yaml", ".yml"],
    "text/x-yaml" => [".yaml", ".yml"]
  }

  @spec list_importers(keyword()) :: [importer_registration()]
  def list_importers(opts \\ []) when is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)

    configured_importers()
    |> Enum.filter(fn %{descriptor: descriptor} ->
      is_nil(catalog_family) or descriptor.catalog_family == catalog_family
    end)
    |> Enum.sort_by(fn %{descriptor: descriptor} ->
      {Atom.to_string(descriptor.catalog_family), descriptor.importer_key}
    end)
  end

  @spec fetch_importer(binary()) :: {:ok, importer_registration()} | {:error, term()}
  def fetch_importer(importer_key) when is_binary(importer_key) do
    case Enum.find(list_importers(), fn %{descriptor: descriptor} ->
           descriptor.importer_key == importer_key
         end) do
      nil -> {:error, :catalog_importer_not_found}
      importer -> {:ok, importer}
    end
  end

  @spec detect_importer(binary(), binary() | nil) ::
          {:ok, importer_registration()} | {:error, :no_matching_importer}
  def detect_importer(filename, media_type)
      when is_binary(filename) and (is_binary(media_type) or is_nil(media_type)) do
    importers = list_importers()

    with :error <- find_by_media_type(importers, media_type),
         :error <- find_by_extension(importers, filename) do
      {:error, :no_matching_importer}
    else
      {:ok, registration} -> {:ok, registration}
    end
  end

  defp find_by_media_type(_importers, nil), do: :error

  defp find_by_media_type(importers, media_type) do
    normalized = String.downcase(media_type)

    case Enum.find(importers, fn %{descriptor: descriptor} ->
           Enum.any?(descriptor.media_types, &(String.downcase(&1) == normalized))
         end) do
      nil -> :error
      registration -> {:ok, registration}
    end
  end

  defp find_by_extension(importers, filename) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension == "" do
      :error
    else
      case Enum.find(importers, &matches_extension?(&1, extension)) do
        nil -> :error
        registration -> {:ok, registration}
      end
    end
  end

  defp matches_extension?(%{descriptor: descriptor}, extension) do
    Enum.any?(descriptor.media_types, fn media_type ->
      extension in Map.get(@extension_by_media_type, media_type, [])
    end)
  end

  defp configured_importers do
    Application.get_env(:cadence, :catalog_importers, [])
    |> Enum.reduce([], fn module, acc ->
      with true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, :descriptor, 0),
           %ImporterDescriptor{} = descriptor <- module.descriptor() do
        acc ++ [%{module: module, descriptor: descriptor}]
      else
        _other -> acc
      end
    end)
  end
end

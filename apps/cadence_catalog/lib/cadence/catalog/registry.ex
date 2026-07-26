defmodule Cadence.Catalog.Registry do
  @moduledoc """
  Registry of built-in and configured catalog importers.

  The portable Cadence YAML importer is available without application
  configuration. Consumers may replace or extend the registry through the
  `:catalog_importers` application environment.
  """

  alias Cadence.Catalog.ImporterDescriptor
  alias Cadence.Catalog.Importers.CadenceYamlDatabase

  @type importer_registration :: %{module: module(), descriptor: ImporterDescriptor.t()}
  @type fetch_error :: :catalog_importer_not_found | :catalog_importer_version_not_found

  @builtin_importers [CadenceYamlDatabase]

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
    |> filter_and_sort(catalog_family)
  end

  @spec list_builtin_importers(keyword()) :: [importer_registration()]
  def list_builtin_importers(opts \\ []) when is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)

    @builtin_importers
    |> registrations()
    |> Enum.filter(&(&1.descriptor.trust == :first_party))
    |> filter_and_sort(catalog_family)
  end

  defp filter_and_sort(importers, catalog_family) do
    importers
    |> Enum.filter(fn %{descriptor: descriptor} ->
      is_nil(catalog_family) or descriptor.catalog_family == catalog_family
    end)
    |> Enum.sort_by(fn %{descriptor: descriptor} ->
      {Atom.to_string(descriptor.catalog_family), descriptor.importer_key, descriptor.version}
    end)
  end

  @spec fetch_importer(binary(), pos_integer() | :latest | nil) ::
          {:ok, importer_registration()} | {:error, fetch_error()}
  def fetch_importer(importer_key, version \\ :latest) when is_binary(importer_key) do
    importers =
      list_builtin_importers()
      |> Kernel.++(list_importers())
      |> Enum.uniq_by(fn registration ->
        {registration.descriptor.importer_key, registration.descriptor.version}
      end)

    fetch_from(importers, importer_key, version)
  end

  @spec fetch_builtin_importer(binary(), pos_integer() | :latest | nil) ::
          {:ok, importer_registration()} | {:error, fetch_error()}
  def fetch_builtin_importer(importer_key, version \\ :latest) when is_binary(importer_key),
    do: fetch_from(list_builtin_importers(), importer_key, version)

  @doc """
  Detects the importer for an upload.

  Media type is matched first (case-insensitive, exact against each descriptor's
  `media_types`). Filename extension is consulted only when no importer claims
  the media type. Returns `{:error, :no_matching_importer}` when neither step
  finds a match.
  """
  @spec detect_importer(binary(), binary() | nil) ::
          {:ok, importer_registration()} | {:error, :no_matching_importer}
  def detect_importer(filename, media_type)
      when is_binary(filename) and (is_binary(media_type) or is_nil(media_type)) do
    detect_importer(filename, media_type, list_importers())
  end

  @spec detect_importer(binary(), binary() | nil, [importer_registration()]) ::
          {:ok, importer_registration()} | {:error, :no_matching_importer}
  def detect_importer(filename, media_type, importers)
      when is_binary(filename) and (is_binary(media_type) or is_nil(media_type)) and
             is_list(importers) do
    with :error <- find_by_media_type(importers, media_type),
         :error <- find_by_extension(importers, filename) do
      {:error, :no_matching_importer}
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
    :cadence_catalog
    |> Application.get_env(:catalog_importers, @builtin_importers)
    |> registrations()
  end

  defp registrations(modules) do
    modules
    |> Enum.reduce([], fn module, acc ->
      with true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, :descriptor, 0),
           true <- function_exported?(module, :import, 2),
           %ImporterDescriptor{} = descriptor <- module.descriptor(),
           :ok <- ImporterDescriptor.validate(descriptor) do
        acc ++ [%{module: module, descriptor: descriptor}]
      else
        _other -> acc
      end
    end)
  end

  defp fetch_from(importers, importer_key, version) do
    matches =
      Enum.filter(importers, &(&1.descriptor.importer_key == importer_key))

    case {matches, version} do
      {[], _version} ->
        {:error, :catalog_importer_not_found}

      {matches, requested_version} when requested_version in [:latest, nil] ->
        {:ok, Enum.max_by(matches, & &1.descriptor.version)}

      {matches, requested_version} when is_integer(requested_version) ->
        case Enum.find(matches, &(&1.descriptor.version == requested_version)) do
          nil -> {:error, :catalog_importer_version_not_found}
          registration -> {:ok, registration}
        end

      {_matches, _version} ->
        {:error, :catalog_importer_version_not_found}
    end
  end
end

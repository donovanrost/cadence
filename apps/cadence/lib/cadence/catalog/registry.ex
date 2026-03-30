defmodule Cadence.Catalog.Registry do
  @moduledoc """
  Registry of configured first-party catalog importers.
  """

  alias Cadence.Catalog.ImporterDescriptor

  @type importer_registration :: %{module: module(), descriptor: ImporterDescriptor.t()}

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

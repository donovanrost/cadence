defmodule Cadence.Applications.CatalogRegistry do
  @moduledoc "Generic core registry for application-owned compatibility catalog contributions."

  alias Cadence.Applications.{ApplicationDefinition, CatalogContribution, LegacyCommsOverview}

  @contributors [LegacyCommsOverview]

  @spec all() :: [CatalogContribution.t()]
  def all do
    Enum.flat_map(@contributors, fn contributor -> contributor.catalog_contributions() end)
  end

  @spec fetch(binary()) ::
          {:ok, CatalogContribution.t()} | {:error, :unknown_catalog_contribution}
  def fetch(application_key) when is_binary(application_key) do
    case Enum.find(all(), fn %CatalogContribution{definition: definition} ->
           definition.application_key == application_key
         end) do
      %CatalogContribution{} = contribution -> {:ok, contribution}
      nil -> {:error, :unknown_catalog_contribution}
    end
  end

  def fetch(_application_key), do: {:error, :unknown_catalog_contribution}

  @spec fetch_default(ApplicationDefinition.scope()) ::
          {:ok, CatalogContribution.t()} | {:error, :unknown_catalog_contribution}
  def fetch_default(scope) when is_atom(scope) do
    case Enum.find(all(), fn %CatalogContribution{definition: definition} ->
           scope in definition.installable_scopes
         end) do
      %CatalogContribution{} = contribution -> {:ok, contribution}
      nil -> {:error, :unknown_catalog_contribution}
    end
  end

  def fetch_default(_scope), do: {:error, :unknown_catalog_contribution}
end

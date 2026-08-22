defmodule Cadence.Extensions.CatalogImporterContribution do
  @moduledoc "A typed package contribution referencing one built-in catalog importer version."

  @type t :: %__MODULE__{
          importer_key: binary(),
          importer_version: pos_integer()
        }

  @enforce_keys [:importer_key, :importer_version]
  defstruct [:importer_key, :importer_version]

  @spec validate(t()) :: :ok | {:error, :invalid_catalog_importer_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_binary(contribution.importer_key) and contribution.importer_key != "" and
         is_integer(contribution.importer_version) and contribution.importer_version > 0 do
      :ok
    else
      {:error, :invalid_catalog_importer_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_catalog_importer_contribution}
end

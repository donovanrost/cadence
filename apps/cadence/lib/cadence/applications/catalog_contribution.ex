defmodule Cadence.Applications.CatalogContribution do
  @moduledoc "Plain core-owned metadata for a non-installed application catalog entry."

  alias Cadence.Applications.ApplicationDefinition

  @type t :: %__MODULE__{
          definition: ApplicationDefinition.t(),
          package_id: binary(),
          package_version: pos_integer()
        }

  @enforce_keys [:definition, :package_id, :package_version]
  defstruct @enforce_keys
end

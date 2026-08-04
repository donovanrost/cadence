defmodule Cadence.Management.DataSources.Credentials.MaterialPolicy do
  @moduledoc "Compatibility boundary for dashboard credential material policy."

  alias Cadence.Secrets.MaterialPolicy

  @spec normalize_and_validate(map()) :: {:ok, map()} | {:error, term()}
  def normalize_and_validate(material) when is_map(material) do
    MaterialPolicy.normalize_and_validate(material,
      allowed_material_keys: MaterialPolicy.dashboard_keys()
    )
  end
end

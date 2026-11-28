defmodule Cadence.Applications.TelemetryDecomCatalogContribution do
  @moduledoc """
  Application-owned catalog contribution for Telemetry Decom. The application is headless (#669),
  so it contributes no surface queries and no frontend release.
  """

  alias Cadence.Applications.{CatalogContribution, Registry}

  @package_id "cadence.telemetry-decom"
  @package_version 1

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: fetch_definition!(),
        package_id: @package_id,
        package_version: @package_version
      }
    ]
  end

  defp fetch_definition! do
    {:ok, definition} = Registry.fetch("telemetry_decom", 1)
    definition
  end
end

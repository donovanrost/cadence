defmodule Cadence.Applications.TelemetryDecomCatalogContribution do
  @moduledoc "Application-owned frontend release contributions for Telemetry Decom."

  alias Cadence.Applications.{CatalogContribution, Registry, ReleaseContribution}

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

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    [
      %ReleaseContribution{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: "manage",
        surface_version: 1,
        federation: :module_federation,
        release_id: "telemetry-decom-v1",
        remote_name: "cadence_telemetry_decom",
        manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
        exposed_module: "./Application"
      },
      %ReleaseContribution{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: "packet_bindings",
        surface_version: 1,
        federation: :module_federation,
        release_id: "telemetry-decom-v1",
        remote_name: "cadence_telemetry_decom",
        manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
        exposed_module: "./Application"
      }
    ]
  end

  defp fetch_definition! do
    {:ok, definition} = Registry.fetch("telemetry_decom", 1)
    definition
  end
end

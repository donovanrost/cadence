defmodule Cadence.Applications.DerivedTelemetry do
  @moduledoc "Application-owned contribution metadata for Derived Telemetry."

  alias Cadence.Applications.{
    CatalogContribution,
    Registry,
    ReleaseContribution,
    SurfaceQueryContribution
  }

  @application_key "derived_telemetry"

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.DerivedTelemetry.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    [
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.derived_telemetry.manage",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.DerivedTelemetry
      }
    ]
  end

  def catalog_contributions do
    {:ok, definition} = Registry.fetch("derived_telemetry", 1)

    [
      %CatalogContribution{
        definition: definition,
        package_id: "cadence.derived-telemetry",
        package_version: 1
      }
    ]
  end

  def release_contributions do
    [
      %ReleaseContribution{
        application_key: "derived_telemetry",
        application_version: 1,
        surface_id: "manage",
        surface_version: 1,
        federation: :module_federation,
        release_id: "ops-console-v1",
        remote_name: "cadence_ops_console",
        manifest_path: "/assets/application-host/ops-console/mf-manifest.json",
        exposed_module: "./DerivedTelemetry"
      }
    ]
  end
end

defmodule Cadence.Applications.Limits do
  @moduledoc "Application-owned contribution metadata for mission limits."

  alias Cadence.Applications.{
    CatalogContribution,
    Registry,
    ReleaseContribution,
    SurfaceQueryContribution
  }

  @application_key "limits"

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.Limits.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    [
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.limits.manage",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.Limits
      },
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.limits.activity",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.Limits
      }
    ]
  end

  def catalog_contributions do
    {:ok, definition} = Registry.fetch("limits", 1)

    [
      %CatalogContribution{
        definition: definition,
        package_id: "cadence.mission-assurance",
        package_version: 1
      }
    ]
  end

  def release_contributions do
    for surface <- ["manage", "activity"] do
      %ReleaseContribution{
        application_key: "limits",
        application_version: 1,
        surface_id: surface,
        surface_version: 1,
        federation: :module_federation,
        release_id: "ops-console-v1",
        remote_name: "cadence_ops_console",
        manifest_path: "/assets/application-host/ops-console/mf-manifest.json",
        exposed_module: "./Limits"
      }
    end
  end
end

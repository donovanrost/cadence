defmodule Cadence.Applications.LegacyCommsOverview do
  @moduledoc "Core-owned compatibility definition for the legacy Comms overview host entry."

  alias Cadence.Applications.{
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition
  }

  @identity %{
    application_key: "comms_overview",
    application_version: 1,
    package_id: "cadence.comms_overview",
    package_version: 1,
    surface_id: "overview",
    surface_version: 1,
    query_id: "cadence.comms.overview",
    release_id: "comms-overview-v1",
    remote_name: "cadence_comms_overview",
    manifest_path: "/assets/application-host/comms-overview/mf-manifest.json",
    exposed_module: "./Application"
  }

  @spec identity() :: map()
  def identity, do: @identity

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    [
      %ReleaseContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        surface_id: @identity.surface_id,
        surface_version: @identity.surface_version,
        federation: :module_federation,
        release_id: @identity.release_id,
        remote_name: @identity.remote_name,
        manifest_path: @identity.manifest_path,
        exposed_module: @identity.exposed_module
      }
    ]
  end

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @identity.package_id,
        package_version: @identity.package_version
      }
    ]
  end

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Communications Overview",
      description: "Review the saved communications setup for a mission.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      surfaces: [surface()]
    }
  end

  defp surface do
    %SurfaceDefinition{
      surface_id: @identity.surface_id,
      version: @identity.surface_version,
      purpose: :overview,
      scope: :mission,
      placement: :application_workspace,
      navigation: %{label: "Overview", order: 10, fallback_path: "/comms"},
      data_contract: %{query_id: @identity.query_id, version: @identity.surface_version},
      actions: [],
      refresh: :static,
      renderer: {:trusted, "cadence.comms.overview"}
    }
  end
end

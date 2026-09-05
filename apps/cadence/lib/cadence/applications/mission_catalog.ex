defmodule Cadence.Applications.MissionCatalog do
  @moduledoc "Domain-owned application and frontend release contributions for missions and catalogs."

  alias Cadence.Applications.{
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition
  }

  @package_id "cadence.mission-catalog"
  @package_version 1
  @application_key "mission_catalog"
  @application_version 1
  @remote_name "cadence_mission_catalog"
  @manifest_path "/assets/application-host/mission-catalog/mf-manifest.json"

  @surface_specs [
    %{
      id: "mission_list",
      purpose: :overview,
      scope: :organization,
      label: "Missions",
      order: 10,
      query_id: "cadence.mission_catalog.mission_list",
      fallback_path: "/missions",
      exposed_module: "./MissionList"
    },
    %{
      id: "mission_new",
      purpose: :configuration,
      scope: :organization,
      label: "New mission",
      order: 20,
      query_id: "cadence.mission_catalog.mission_new",
      fallback_path: "/missions/new",
      exposed_module: "./MissionNew"
    },
    %{
      id: "mission_overview",
      purpose: :overview,
      scope: :mission,
      label: "Mission overview",
      order: 30,
      query_id: "cadence.mission_catalog.mission_overview",
      fallback_path: "/missions/:mission_id",
      exposed_module: "./MissionOverview"
    },
    %{
      id: "mission_applications",
      purpose: :configuration,
      scope: :mission,
      label: "Applications",
      order: 40,
      query_id: "cadence.mission_catalog.mission_applications",
      fallback_path: "/missions/:mission_id/applications",
      exposed_module: "./MissionApplicationsPage"
    },
    %{
      id: "catalog_index",
      purpose: :overview,
      scope: :mission,
      label: "Catalog",
      order: 50,
      query_id: "cadence.mission_catalog.catalog_index",
      fallback_path: "/missions/:mission_id/catalog",
      exposed_module: "./CatalogIndex"
    },
    %{
      id: "catalog_database_new",
      purpose: :configuration,
      scope: :mission,
      label: "New database",
      order: 60,
      query_id: "cadence.mission_catalog.catalog_database_new",
      fallback_path: "/missions/:mission_id/catalog/databases/new",
      exposed_module: "./CatalogDatabaseNew"
    },
    %{
      id: "catalog_database_show",
      purpose: :subject_detail,
      scope: :mission,
      label: "Database",
      order: 70,
      query_id: "cadence.mission_catalog.catalog_database_show",
      fallback_path: "/missions/:mission_id/catalog/databases/:catalog_database_id",
      exposed_module: "./CatalogDatabaseShow"
    },
    %{
      id: "catalog_revision_show",
      purpose: :subject_detail,
      scope: :mission,
      label: "Revision",
      order: 80,
      query_id: "cadence.mission_catalog.catalog_revision_show",
      fallback_path: "/missions/:mission_id/catalog/revisions/:catalog_revision_id",
      exposed_module: "./CatalogRevisionShow"
    },
    %{
      id: "catalog_artifact_show",
      purpose: :subject_detail,
      scope: :mission,
      label: "Artifact",
      order: 90,
      query_id: "cadence.mission_catalog.catalog_artifact_show",
      fallback_path: "/missions/:mission_id/catalog/artifacts/:artifact_id",
      exposed_module: "./CatalogArtifactShowPage"
    },
    %{
      id: "catalog_import_run_show",
      purpose: :activity,
      scope: :mission,
      label: "Import run",
      order: 100,
      query_id: "cadence.mission_catalog.catalog_import_run_show",
      fallback_path: "/missions/:mission_id/catalog/imports/:import_run_id",
      exposed_module: "./CatalogImportRunShow"
    }
  ]

  @spec package_identity() :: %{package_id: binary(), package_version: pos_integer()}
  def package_identity, do: %{package_id: @package_id, package_version: @package_version}

  @spec application_identity() :: %{application_key: binary(), application_version: pos_integer()}
  def application_identity,
    do: %{application_key: @application_key, application_version: @application_version}

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @package_id,
        package_version: @package_version
      }
    ]
  end

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @application_key,
        application_version: @application_version,
        surface_id: spec.id,
        surface_version: 1,
        federation: :module_federation,
        release_id: "mission-catalog-#{spec.id}-v1",
        remote_name: @remote_name,
        manifest_path: @manifest_path,
        exposed_module: "./Application"
      }
    end)
  end

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @application_key,
      version: @application_version,
      display_name: "Mission & Catalog",
      description: "Manage missions and the immutable catalog records they use.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:organization, :mission],
      surfaces: Enum.map(@surface_specs, &surface/1)
    }
  end

  defp surface(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: 1,
      purpose: spec.purpose,
      scope: spec.scope,
      placement: :application_workspace,
      navigation: %{
        label: spec.label,
        order: spec.order,
        fallback_path: spec.fallback_path
      },
      data_contract: %{query_id: spec.query_id, version: 1},
      actions: [],
      refresh: :static,
      renderer: {:trusted, "cadence.mission_catalog.#{spec.id}"}
    }
  end
end

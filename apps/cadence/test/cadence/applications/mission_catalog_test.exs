defmodule Cadence.Applications.MissionCatalogTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ApplicationDefinition, MissionCatalog, ReleaseContribution}

  test "contributes one valid mission and catalog application with complete surfaces" do
    definition = MissionCatalog.definition()

    assert :ok = ApplicationDefinition.validate(definition)
    assert definition.application_key == "mission_catalog"
    assert definition.installable_scopes == [:organization, :mission]

    assert Enum.map(definition.surfaces, & &1.surface_id) == [
             "mission_list",
             "mission_new",
             "mission_overview",
             "mission_applications",
             "catalog_index",
             "catalog_database_new",
             "catalog_database_show",
             "catalog_revision_show",
             "catalog_artifact_show",
             "catalog_import_run_show"
           ]

    assert Enum.all?(definition.surfaces, fn surface ->
             surface.placement == :application_workspace and
               surface.renderer == {:trusted, "cadence.mission_catalog.#{surface.surface_id}"}
           end)
  end

  test "contributes one release identity for every page surface" do
    contributions = MissionCatalog.release_contributions()

    assert length(contributions) == length(MissionCatalog.definition().surfaces)
    assert Enum.all?(contributions, &(ReleaseContribution.validate(&1) == :ok))

    assert Enum.map(contributions, &{&1.surface_id, &1.exposed_module}) == [
             {"mission_list", "./MissionList"},
             {"mission_new", "./MissionNew"},
             {"mission_overview", "./MissionOverview"},
             {"mission_applications", "./MissionApplicationsPage"},
             {"catalog_index", "./CatalogIndex"},
             {"catalog_database_new", "./CatalogDatabaseNew"},
             {"catalog_database_show", "./CatalogDatabaseShow"},
             {"catalog_revision_show", "./CatalogRevisionShow"},
             {"catalog_artifact_show", "./CatalogArtifactShowPage"},
             {"catalog_import_run_show", "./CatalogImportRunShow"}
           ]

    assert Enum.uniq(Enum.map(contributions, &ReleaseContribution.key/1)) ==
             Enum.map(contributions, &ReleaseContribution.key/1)
  end

  test "catalog contribution carries the same package and application identity" do
    [contribution] = MissionCatalog.catalog_contributions()

    assert contribution.package_id == "cadence.mission-catalog"
    assert contribution.package_version == 1
    assert contribution.definition == MissionCatalog.definition()
  end
end

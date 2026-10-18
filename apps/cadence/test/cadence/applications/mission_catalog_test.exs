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

    assert Enum.all?(contributions, &(&1.exposed_module == "./Application"))

    assert Enum.uniq(Enum.map(contributions, &ReleaseContribution.key/1)) ==
             Enum.map(contributions, &ReleaseContribution.key/1)
  end

  test "registers every surface query and interactive action contract" do
    assert length(MissionCatalog.surface_query_contributions()) == 10

    assert Enum.map(MissionCatalog.surface_query_contributions(), & &1.query_id) ==
             Enum.map(
               MissionCatalog.definition().surfaces,
               &Map.fetch!(&1.data_contract, :query_id)
             )

    assert MissionCatalog.definition().actions
           |> Enum.map(& &1.action_id)
           |> Enum.sort() ==
             [
               "cancel-upload",
               "disable",
               "install",
               "reimport",
               "save",
               "toggle-revision-form",
               "uninstall",
               "validate"
             ]
  end

  test "catalog contribution carries the same package and application identity" do
    [contribution] = MissionCatalog.catalog_contributions()

    assert contribution.package_id == "cadence.mission-catalog"
    assert contribution.package_version == 1
    assert contribution.definition == MissionCatalog.definition()
  end
end

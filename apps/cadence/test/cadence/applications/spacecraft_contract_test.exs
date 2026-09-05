defmodule Cadence.Applications.SpacecraftContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ApplicationDefinition, CatalogContribution, ReleaseContribution}
  alias Cadence.Applications.Spacecraft

  @surface_ids ~w(
    list
    new
    profile_list
    profile_new
    profile_show
    show
    edit
    readiness
    routing
    commanding
    applications
    telemetry_decom
  )

  test "domain contributions match the exact spacecraft remote manifest identity" do
    assert Spacecraft.identity() == %{
             application_key: "spacecraft",
             package_id: "cadence.spacecraft",
             package_version: 1,
             remote_name: "cadence_spacecraft",
             manifest_path: "/assets/application-host/spacecraft/mf-manifest.json",
             exposed_module: "./Application"
           }

    definition = Spacecraft.definition()
    assert %ApplicationDefinition{} = definition
    assert :ok = ApplicationDefinition.validate(definition)
    assert definition.application_key == "spacecraft"
    assert definition.package_id == "cadence.spacecraft"
    assert definition.package_version == 1
    assert Enum.map(definition.surfaces, & &1.surface_id) == @surface_ids

    assert Enum.map(definition.surfaces, & &1.data_contract.query_id) == [
             "cadence.spacecraft.list",
             "cadence.spacecraft.new",
             "cadence.spacecraft.profiles",
             "cadence.spacecraft.profile.new",
             "cadence.spacecraft.profile.show",
             "cadence.spacecraft.show",
             "cadence.spacecraft.edit",
             "cadence.spacecraft.readiness",
             "cadence.spacecraft.routing",
             "cadence.spacecraft.commanding",
             "cadence.spacecraft.applications",
             "cadence.telemetry_decom.manage"
           ]

    assert [
             %CatalogContribution{
               definition: ^definition,
               package_id: "cadence.spacecraft",
               package_version: 1
             }
           ] = Spacecraft.catalog_contributions()

    releases = Spacecraft.release_contributions()
    assert length(releases) == length(@surface_ids)

    assert Enum.map(releases, & &1.surface_id) == @surface_ids

    assert Enum.all?(releases, fn contribution ->
             %ReleaseContribution{
               application_key: "spacecraft",
               package_id: "cadence.spacecraft",
               package_version: 1,
               release_id: "spacecraft-v1",
               federation: :module_federation,
               remote_name: "cadence_spacecraft",
               manifest_path: "/assets/application-host/spacecraft/mf-manifest.json",
               exposed_module: "./Application",
               surface_version: 1
             } = contribution
           end)
  end
end

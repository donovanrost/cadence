defmodule Cadence.Applications.SpacecraftContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution
  }

  alias Cadence.Applications.Spacecraft

  # Host-action sweep row 2: new, profile_new and edit are gone.
  @surface_ids ~w(
    list
    profile_list
    profile_show
    show
    readiness
    routing
    commanding
    applications
    telemetry_decom
  )

  test "domain contributions match the exact spacecraft remote manifest identity" do
    assert Spacecraft.identity() == %{
             application_key: "spacecraft",
             application_version: 1,
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
    assert Enum.map(definition.surfaces, & &1.surface_id) == @surface_ids

    assert Spacecraft.surface_query_contributions()
           |> Enum.map(& &1.query_id)
           |> Enum.sort() ==
             [
               "cadence.spacecraft.list",
               "cadence.spacecraft.profiles",
               "cadence.spacecraft.profile.show",
               "cadence.spacecraft.show",
               "cadence.spacecraft.readiness",
               "cadence.spacecraft.routing",
               "cadence.spacecraft.commanding",
               "cadence.spacecraft.applications"
             ]
             |> Enum.sort()

    assert Spacecraft.action_provider() == Cadence.Applications.Spacecraft.ActionProvider

    assert Enum.map(definition.surfaces, & &1.data_contract.query_id) == [
             "cadence.spacecraft.list",
             "cadence.spacecraft.profiles",
             "cadence.spacecraft.profile.show",
             "cadence.spacecraft.show",
             "cadence.spacecraft.readiness",
             "cadence.spacecraft.routing",
             "cadence.spacecraft.commanding",
             "cadence.spacecraft.applications",
             "cadence.telemetry_decom.manage"
           ]

    assert definition.lifecycle_contract.actions == []

    surface_actions =
      definition.surfaces
      |> Enum.flat_map(& &1.actions)
      |> Enum.uniq()

    declared_actions = Enum.map(definition.actions, & &1.action_id)

    assert Enum.sort(surface_actions) ==
             Enum.sort([
               "disable",
               "install",
               "request_activation",
               "save_configuration",
               "uninstall"
             ])

    assert MapSet.subset?(MapSet.new(surface_actions), MapSet.new(declared_actions))
    assert Enum.all?(definition.actions, &(ActionDefinition.validate(&1) == :ok))

    assert %{
             "install" => %{scope: :spacecraft, required_permission: "operate_mission"},
             "disable" => %{scope: :spacecraft, required_permission: "operate_mission"},
             "uninstall" => %{scope: :spacecraft, required_permission: "operate_mission"},
             "save_configuration" => %{
               scope: :spacecraft,
               required_permission: "operate_mission"
             },
             "request_activation" => %{
               scope: :spacecraft,
               required_permission: "request_activation"
             }
           } =
             Map.new(definition.actions, fn %ActionDefinition{} = action ->
               {action.action_id, Map.from_struct(action)}
             end)

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

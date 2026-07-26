defmodule Cadence.Applications.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    LifecycleActionDefinition,
    LifecycleContract,
    Registry,
    ResourceClaimDefinition,
    ResourceContract,
    StatusPlacement,
    SurfaceDefinition
  }

  alias Cadence.Extensions.Presentation.ReferenceDefinition

  test "resolves the latest registered application and its default spacecraft surface" do
    assert {:ok, %ApplicationDefinition{} = definition} =
             Registry.fetch("telemetry_decom")

    assert definition.version == 1
    assert definition.installable_scopes == [:spacecraft]
    assert definition.status_query_id == "cadence.telemetry_decom.status"

    assert definition.status_placements == [
             %StatusPlacement{
               placement: :comms_validation,
               scope: :spacecraft,
               required?: true
             }
           ]

    assert definition.preflight_query_id == "cadence.telemetry_decom.activation_preflight"

    assert %LifecycleContract{
             actions: ["save_configuration", "request_activation", "disable"]
           } = definition.lifecycle_contract

    assert {:ok,
            %LifecycleActionDefinition{
              required_permission: "request_activation",
              execution: :approval_required
            }} =
             LifecycleContract.fetch_action(
               definition.lifecycle_contract,
               "request_activation"
             )

    assert %ResourceContract{
             claims: [
               %ResourceClaimDefinition{
                 claim_type: :packet_apid,
                 scope: :spacecraft,
                 mode: :exclusive
               }
             ]
           } = definition.resource_contract

    assert {:ok, %SurfaceDefinition{} = surface} =
             Registry.fetch_default_surface(definition, :spacecraft)

    assert surface.surface_id == "manage"
    assert surface.renderer == {:trusted, "cadence.telemetry_decom.manage"}
    assert "request_activation" in surface.actions

    assert surface.references == %{
             "catalog_revision_id" => %ReferenceDefinition{
               provider_id: "cadence.catalog.telemetry_revisions",
               version: 1
             }
           }
  end

  test "distinguishes unknown applications, unsupported versions, and unavailable definitions" do
    assert {:error, :unknown_application} = Registry.fetch("not_registered")

    assert {:error, :unsupported_application_version} =
             Registry.fetch("telemetry_decom", 99)

    assert {:ok, derived} = Registry.fetch_available("derived_telemetry")
    assert derived.availability == :available
    assert derived.installable_scopes == [:mission]

    assert {:ok, cfdp} = Registry.fetch("cfdp")
    assert cfdp.availability == :roadmap
    assert {:error, :application_unavailable} = Registry.fetch_available("cfdp")
  end

  test "available definitions are safe choices for a spacecraft profile" do
    assert Enum.all?(Registry.all(), &(ApplicationDefinition.validate(&1) == :ok))

    assert Enum.all?(Registry.all(), fn definition ->
             LifecycleContract.validate(definition.lifecycle_contract) == :ok
           end)

    assert Enum.all?(Registry.all(), fn definition ->
             Enum.all?(definition.actions, &(ActionDefinition.validate(&1) == :ok))
           end)

    assert Enum.map(Registry.available_for_scope(:spacecraft), & &1.application_key) == [
             "telemetry_decom"
           ]

    assert Enum.map(Registry.available_for_scope(:mission), & &1.application_key) == [
             "derived_telemetry",
             "limits"
           ]

    assert Enum.sort(Registry.known_keys()) == [
             "cfdp",
             "derived_telemetry",
             "limits",
             "telemetry_decom"
           ]
  end

  test "resolves ordered workspace surfaces by stable id" do
    assert {:ok, definition} = Registry.fetch_available("limits")

    assert {:ok, %SurfaceDefinition{} = manage} =
             Registry.fetch_surface(definition, :mission, "manage")

    assert manage.references == %{
             "point_id" => %ReferenceDefinition{
               provider_id: "cadence.telemetry.canonical_points",
               version: 1,
               mode: :search,
               result_limit: 20
             }
           }

    assert Enum.map(Registry.workspace_surfaces(definition, :mission), & &1.surface_id) == [
             "manage",
             "activity"
           ]

    assert {:ok, %SurfaceDefinition{} = activity} =
             Registry.fetch_surface(definition, :mission, "activity")

    assert activity.purpose == :activity
    assert activity.navigation.label == "Current posture"
    assert activity.actions == []

    assert {:error, :unknown_surface} =
             Registry.fetch_surface(definition, :mission, "not-declared")

    assert {:error, :unknown_surface} =
             Registry.fetch_surface(definition, :spacecraft, "activity")
  end
end

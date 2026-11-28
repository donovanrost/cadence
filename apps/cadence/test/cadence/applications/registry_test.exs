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
    SurfaceDefinition
  }

  alias Cadence.Extensions.Presentation.ReferenceDefinition

  test "installation policy is explicit, scoped, and defaults to optional" do
    assert {:ok, optional} = Registry.fetch_available("telemetry_decom")
    assert optional.installation_policy == :optional
    refute Registry.platform?("telemetry_decom", :spacecraft)
    refute Registry.platform?("unknown", :mission)

    for key <- ["ops_console"] do
      assert Registry.platform?(key, :mission)
    end

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%{optional | installation_policy: :automatic})
  end

  test "resolves the latest registered application and its default spacecraft surface" do
    assert {:ok, %ApplicationDefinition{} = definition} =
             Registry.fetch("telemetry_decom")

    assert definition.version == 1
    assert definition.installable_scopes == [:spacecraft]
    assert definition.status_query_id == "cadence.telemetry_decom.status"

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
                 mode: :shared
               }
             ]
           } = definition.resource_contract

    assert {:ok, %SurfaceDefinition{} = surface} =
             Registry.fetch_default_surface(definition, :spacecraft)

    assert surface.surface_id == "packet_bindings"
    assert surface.renderer == {:trusted, "cadence.telemetry_decom.packet_bindings"}
    assert "save_packet_bindings" in surface.actions
    assert surface.references == %{}

    assert Enum.map(Registry.workspace_surfaces(definition, :spacecraft), & &1.surface_id) == [
             "packet_bindings",
             "manage"
           ]
  end

  test "distinguishes unknown applications, unsupported versions, and unavailable definitions" do
    assert {:error, :unknown_application} = Registry.fetch("not_registered")

    assert {:error, :unsupported_application_version} =
             Registry.fetch("telemetry_decom", 99)

    assert {:ok, decom} = Registry.fetch_available("telemetry_decom")
    assert decom.availability == :available
    assert decom.installable_scopes == [:spacecraft]

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
             "ops_console"
           ]

    assert Enum.sort(Registry.known_keys()) == [
             "cfdp",
             "ops_console",
             "telemetry_decom"
           ]
  end

  test "resolves ordered workspace surfaces by stable id" do
    assert {:ok, definition} = Registry.fetch_available("telemetry_decom")

    assert {:ok, %SurfaceDefinition{} = manage} =
             Registry.fetch_surface(definition, :spacecraft, "manage")

    assert manage.references == %{
             "catalog_revision_id" => %ReferenceDefinition{
               provider_id: "cadence.catalog.telemetry_revisions",
               version: 1
             }
           }

    # Ordered by navigation order (20, 30), not by declaration order.
    assert Enum.map(Registry.workspace_surfaces(definition, :spacecraft), & &1.surface_id) == [
             "packet_bindings",
             "manage"
           ]

    assert {:ok, %SurfaceDefinition{} = bindings} =
             Registry.fetch_surface(definition, :spacecraft, "packet_bindings")

    assert bindings.navigation.label == "Packet bindings"
    assert bindings.actions == ["save_packet_bindings"]

    assert {:error, :unknown_surface} =
             Registry.fetch_surface(definition, :spacecraft, "not-declared")

    assert {:error, :unknown_surface} =
             Registry.fetch_surface(definition, :mission, "manage")
  end
end

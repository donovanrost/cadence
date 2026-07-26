defmodule Cadence.Applications.ApplicationDefinitionTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    ApplicationDependency,
    LifecycleContract,
    ResourceClaimDefinition,
    ResourceContract,
    StatusPlacement,
    SurfaceDefinition
  }

  alias Cadence.Extensions.Presentation.ReferenceDefinition

  test "accepts a bounded application definition with declared surface actions" do
    assert :ok = ApplicationDefinition.validate(valid_application())
  end

  test "rejects surface actions that are absent from both application contracts" do
    application = valid_application()
    [surface] = application.surfaces
    surface = %SurfaceDefinition{surface | actions: ["not_declared"]}

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | surfaces: [surface]
             })
  end

  test "rejects domain actions that collide with host lifecycle identities" do
    application = valid_application()
    [action] = application.actions
    action = %ActionDefinition{action | action_id: "disable"}

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | actions: [action],
                 lifecycle_contract: %LifecycleContract{actions: ["disable"]}
             })
  end

  test "requires every available installation scope to have a host workspace" do
    application = valid_application()

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{application | surfaces: []})

    assert :ok =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | availability: :roadmap,
                 surfaces: []
             })
  end

  test "requires status placements to be scoped, distinct, and backed by a status query" do
    application = valid_application()

    placement = %StatusPlacement{
      placement: :comms_validation,
      scope: :mission,
      required?: true
    }

    assert :ok =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | status_query_id: "cadence.example.status",
                 status_placements: [placement]
             })

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | status_placements: [placement]
             })

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | status_query_id: "cadence.example.status",
                 status_placements: [placement, placement]
             })

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | status_query_id: "cadence.example.status",
                 status_placements: [
                   %StatusPlacement{placement | scope: :spacecraft}
                 ]
             })
  end

  test "rejects self dependencies and duplicate resource claim identities" do
    application = valid_application()

    self_dependency = %ApplicationDependency{
      application_key: application.application_key,
      scope: :same_host
    }

    assert {:error, :invalid_application_definition} =
             ApplicationDefinition.validate(%ApplicationDefinition{
               application
               | dependencies: [self_dependency]
             })

    claim = %ResourceClaimDefinition{
      claim_type: :canonical_point,
      scope: :mission,
      mode: :shared,
      description: "Canonical telemetry input."
    }

    assert {:error, :invalid_application_resource_contract} =
             ResourceContract.validate(%ResourceContract{claims: [claim, claim]})
  end

  test "surface definitions reject unbounded reference and presentation metadata" do
    [surface] = valid_application().surfaces

    invalid_reference = %ReferenceDefinition{
      provider_id: "cadence.telemetry.points",
      version: 1,
      mode: :search,
      result_limit: 51
    }

    assert {:error, :invalid_application_surface_definition} =
             SurfaceDefinition.validate(%SurfaceDefinition{
               surface
               | references: %{"point_id" => invalid_reference}
             })

    assert {:error, :invalid_application_surface_definition} =
             SurfaceDefinition.validate(%SurfaceDefinition{
               surface
               | navigation: %{label: "Manage", class: "application-owned-css"}
             })
  end

  defp valid_application do
    action = %ActionDefinition{
      action_id: "save_configuration",
      version: 1,
      intent: :configuration,
      scope: :mission,
      input_contract: %{schema_id: "cadence.example.input", version: 1},
      result_contract: %{schema_id: "cadence.example.configuration", version: 1},
      required_permission: "operate_mission",
      effect: :durable,
      execution: :immediate,
      concurrency: %{strategy: :append_version}
    }

    surface = %SurfaceDefinition{
      surface_id: "manage",
      version: 1,
      purpose: :configuration,
      scope: :mission,
      placement: :application_workspace,
      navigation: %{label: "Manage", order: 10},
      data_contract: %{query_id: "cadence.example.manage", version: 1},
      actions: [action.action_id],
      refresh: :after_action,
      renderer: {:declarative, "cadence.host.surface.v1"}
    }

    %ApplicationDefinition{
      application_key: "example",
      version: 1,
      display_name: "Example",
      description: "A bounded application definition.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      configuration_contract: %{schema_id: "cadence.example.configuration", version: 1},
      actions: [action],
      surfaces: [surface]
    }
  end
end
